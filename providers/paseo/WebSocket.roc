## A minimal RFC 6455 WebSocket client, pure. The daemon writes the handshake,
## checks the response's status line, then reads each frame in three steps: 2
## bytes, `header_rest_size` more, then the header's `length` bytes of payload,
## which `unmask` decodes. A message split over frames arrives as a first frame
## without `fin` and `Continuation` frames up to one with `fin`.
WebSocket := [].{
	Opcode : [Continuation, Text, Binary, Close, Ping, Pong, Other(U8)]

	## `mask` is empty for an unmasked frame, as servers send.
	Header : { fin : Bool, opcode : Opcode, mask : List(U8), length : U64 }

	## The opening request. `key` is 16 bytes in base64, which any fixed value
	## satisfies.
	handshake : { host : Str, port : U16, path : Str, protocol : Str, key : Str } -> Str
	handshake = |{ host, port, path, protocol, key }|
		"GET ${path} HTTP/1.1\r\nHost: ${host}:${port.to_str()}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: ${protocol}\r\n\r\n"

	## Whether the response's status line switches protocols. Sec-WebSocket-Accept
	## goes unchecked: it needs SHA-1, and Roc's builtins have only SHA-256 and
	## BLAKE3.
	accepted : Str -> Bool
	accepted = |status_line| status_line.trim().starts_with("HTTP/1.1 101")

	## How many header bytes follow a frame's first two: the extended length and
	## the mask.
	header_rest_size : List(U8) -> U64
	header_rest_size = |first_two| {
		second = first_two.get(1) ?? 0
		(if (second >= 0x80) 4 else 0) + extended_length_size(second.bitwise_and(0x7F))
	}

	## Reads a frame header from its first two bytes and the
	## `header_rest_size` after them.
	header : List(U8) -> Header
	header = |bytes| {
		first = bytes.get(0) ?? 0
		second = bytes.get(1) ?? 0
		short_length = second.bitwise_and(0x7F)
		extended = extended_length_size(short_length)
		{
			fin: first >= 0x80,
			opcode: opcode_of(first.bitwise_and(0x0F)),
			mask: if (second >= 0x80) bytes.drop_first(2 + extended).take_first(4) else [],
			length: if (extended == 0) short_length.to_u64() else bytes.drop_first(2).take_first(extended).fold(0, |length, byte| length * 256 + byte.to_u64()),
		}
	}

	## Masks or unmasks a payload: the same XOR both ways.
	unmask : List(U8), List(U8) -> List(U8)
	unmask = |payload, mask|
		if (mask.is_empty()) payload else payload.map_with_index(|byte, index| byte.bitwise_xor(mask.get(index % 4) ?? 0))

	## One final frame, masked with the 4 bytes of `mask` as a client must.
	## A `Ping` is answered with a `Pong` of the same payload.
	frame : Opcode, List(U8), List(U8) -> List(U8)
	frame = |opcode, payload, mask| {
		length = payload.len()
		size =
			if length < 126 {
				[0x80 + length.to_u8_wrap()]
			} else if length < 65536 {
				[0x80 + 126].concat(big_endian(length, 2))
			} else {
				[0x80 + 127].concat(big_endian(length, 8))
			}
		[0x80 + code_of(opcode)].concat(size).concat(mask).concat(unmask(payload, mask))
	}

	text : Str, List(U8) -> List(U8)
	text = |message, mask| WebSocket.frame(Text, message.to_utf8(), mask)

	## Closes with status 1000, a normal closure.
	close : List(U8) -> List(U8)
	close = |mask| WebSocket.frame(Close, [0x03, 0xE8], mask)

	## A close frame's status code (0 for none) and reason.
	closed : List(U8) -> { code : U16, reason : Str }
	closed = |payload| {
		code = payload.take_first(2).fold(0, |so_far, byte| so_far * 256 + byte.to_u16())
		{ code: if (payload.len() < 2) 0 else code, reason: Str.from_utf8(payload.drop_first(2)) ?? "" }
	}
}

extended_length_size : U8 -> U64
extended_length_size = |short_length| if (short_length == 126) 2 else if (short_length == 127) 8 else 0

big_endian : U64, U64 -> List(U8)
big_endian = |value, count| if (count == 0) [] else big_endian(value // 256, count - 1).append((value % 256).to_u8_wrap())

opcode_of : U8 -> WebSocket.Opcode
opcode_of = |code|
	match code {
		0 => Continuation
		1 => Text
		2 => Binary
		8 => Close
		9 => Ping
		10 => Pong
		_ => Other(code)
	}

code_of : WebSocket.Opcode -> U8
code_of = |opcode|
	match opcode {
		Continuation => 0
		Text => 1
		Binary => 2
		Close => 8
		Ping => 9
		Pong => 10
		Other(code) => code
	}

mask : List(U8)
mask = [0x12, 0x34, 0x56, 0x78]

## Reads a frame back as the daemon would: header, then payload.
read_back : List(U8) -> { header : WebSocket.Header, payload : List(U8) }
read_back = |bytes| {
	header_size = 2 + WebSocket.header_rest_size(bytes.take_first(2))
	header = WebSocket.header(bytes.take_first(header_size))
	{ header, payload: WebSocket.unmask(bytes.drop_first(header_size), header.mask) }
}

expect WebSocket.text("hi", mask).take_first(2) == [0x81, 0x82]
expect WebSocket.frame(Binary, List.repeat(0, 200), mask).take_first(4) == [0x82, 0xFE, 0x00, 0xC8]
expect WebSocket.frame(Text, List.repeat(0, 70000), mask).take_first(10) == [0x81, 0xFF, 0, 0, 0, 0, 0, 0x01, 0x11, 0x70]
expect WebSocket.header_rest_size([0x81, 0xFF]) == 12

expect {
	payload = List.repeat(7, 300)
	read_back(WebSocket.frame(Text, payload, mask)) == { header: { fin: Bool.True, opcode: Text, mask, length: 300 }, payload }
}

expect read_back([0x01, 0x02, 0x68, 0x69]) == { header: { fin: Bool.False, opcode: Text, mask: [], length: 2 }, payload: "hi".to_utf8() }
expect read_back(WebSocket.close(mask)).header.opcode == Close
expect WebSocket.closed([0x11, 0x31].concat("Incorrect password".to_utf8())) == { code: 4401, reason: "Incorrect password" }
expect WebSocket.closed([]) == { code: 0, reason: "" }
expect WebSocket.accepted("HTTP/1.1 101 Switching Protocols\r\n")
expect !WebSocket.accepted("HTTP/1.1 403 Forbidden\r\n")

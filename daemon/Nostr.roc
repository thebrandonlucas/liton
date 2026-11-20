import Sha256

## Nostr events (NIP-01), as the daemon's relay keeps them: what an event
## is, the bytes its id is the SHA-256 of, and whether an event is well
## formed and its id right. Signatures are not checked here: the relay
## takes an event only from the device its pubkey is bound to.
Nostr := [].{

	## An event as NIP-01 sends it: ids, pubkeys and signatures as lowercase
	## hex, `created_at` in seconds.
	Event : { id : Str, pubkey : Str, created_at : U64, kind : U32, tags : List(List(Str)), content : Str, sig : Str }

	## The event from its JSON, NIP-01's fields and no others needed.
	from_json : Str -> Try(Event, [Invalid])
	from_json = |text| Json.parse(text).map_err(|_| Invalid)

	## What `event`'s id is the SHA-256 of:
	## `[0,<pubkey>,<created_at>,<kind>,<tags>,<content>]`, its strings
	## escaped as NIP-01 says and nothing else.
	serialized : Event -> Str
	serialized = |{ pubkey, created_at, kind, tags, content, .. }| {
		quoted = |text| "\"${Nostr.escaped(text)}\""
		tags_json = Str.join_with(tags.map(|tag| "[${Str.join_with(tag.map(quoted), ",")}]"), ",")
		"[0,${quoted(pubkey)},${created_at.to_str()},${kind.to_str()},[${tags_json}],${quoted(content)}]"
	}

	## `text` with a line feed, double quote, backslash, carriage return,
	## tab, backspace and form feed escaped, and every other byte as it is.
	escaped : Str -> Str
	escaped = |text| {
		var $bytes = []
		for byte in text.to_utf8() {
			$bytes = $bytes.concat(
				match byte {
					0x0A => ['\\', 'n']
					0x22 => ['\\', '"']
					0x5C => ['\\', '\\']
					0x0D => ['\\', 'r']
					0x09 => ['\\', 't']
					0x08 => ['\\', 'b']
					0x0C => ['\\', 'f']
					other => [other]
				},
			)
		}
		Str.from_utf8_lossy($bytes)
	}

	## The id `event` should have.
	id_of : Event -> Str
	id_of = |event| Sha256.hex(Nostr.serialized(event).to_utf8())

	## `event` if its id, pubkey and signature are hex of the right length
	## and its id is the one its fields give.
	checked : Event -> Try(Event, [Malformed(Str), WrongId])
	checked = |event|
		if !Nostr.hex(event.id, 64) {
			Err(Malformed("id"))
		} else if !Nostr.hex(event.pubkey, 64) {
			Err(Malformed("pubkey"))
		} else if !Nostr.hex(event.sig, 128) {
			Err(Malformed("sig"))
		} else if Nostr.id_of(event) != event.id {
			Err(WrongId)
		} else {
			Ok(event)
		}

	## The room an event is in: its first `h` tag's value (NIP-29), or "".
	room : Event -> Str
	room = |event| event.tags.find_first(|tag| tag.first() == Ok("h")).map_ok(|tag| tag.get(1) ?? "") ?? ""

	## NIP-01's answer to an event: `["OK", <id>, <accepted>, <why>]`.
	answer : Str, Bool, Str -> Str
	answer = |id, accepted, why| "[\"OK\",${Json.to_str(id)},${if (accepted) "true" else "false"},${Json.to_str(why)}]"

	## Whether `text` is `length` lowercase hex digits.
	hex : Str, U64 -> Bool
	hex = |text, length| {
		bytes = text.to_utf8()
		bytes.len() == length and bytes.all(|byte| (byte >= '0' and byte <= '9') or (byte >= 'a' and byte <= 'f'))
	}
}

# Made by nak 0.21 with the secret key 1.
expect {
	empty = { id: "1d60156c7d5c3d752ed401ba085300ea90869712b4acc88edff9601de4c0b15c", pubkey: "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798", created_at: 0, kind: 1, tags: [], content: "", sig: "e817317210f3991ba20259c44953453c2dd6cdd840af98ad69908b43404bc59cda7f0c7e87ceeb13e832e2ce5867d2ba107e16c511fd589d3b05a06d9bd18930" }
	Nostr.checked(empty) == Ok(empty)
}
expect {
	json = "{\"kind\":9,\"id\":\"f1ec467898a01da790f505a3339bc21c8d5ac148f4bcb335cdf3bf0fae190a5c\",\"pubkey\":\"79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798\",\"created_at\":1700000000,\"tags\":[[\"h\",\"general\"],[\"e\",\"abc\",\"\",\"root\"]],\"content\":\"Scout, look at \\\"Auth.roc\\\"\\nline two\\ttab \\\\ back é\",\"sig\":\"fdc43a02113f24da57d2a98faaac80fbb922e19b43f31df0893da5585bd932a99b0a7eabd3a71f3773da263f0fd90ba44d985f4cff9060f53600abaf3ef4ed27\"}"
	parsed = Nostr.from_json(json)
	parsed.map_ok(|event| event.content) == Ok("Scout, look at \"Auth.roc\"\nline two\ttab \\ back é") and parsed.map_ok(|event| Nostr.checked(event).is_ok()) == Ok(Bool.True)
}
expect {
	event = { id: "1d60156c7d5c3d752ed401ba085300ea90869712b4acc88edff9601de4c0b15c", pubkey: "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798", created_at: 0, kind: 1, tags: [], content: "", sig: "e817317210f3991ba20259c44953453c2dd6cdd840af98ad69908b43404bc59cda7f0c7e87ceeb13e832e2ce5867d2ba107e16c511fd589d3b05a06d9bd18930" }
	Nostr.checked({ ..event, content: "changed" }) == Err(WrongId) and Nostr.checked({ ..event, id: "1D60" }) == Err(Malformed("id"))
}
expect Nostr.room({ id: "", pubkey: "", created_at: 0, kind: 9, tags: [["e", "x"], ["h", "general"], ["h", "other"]], content: "", sig: "" }) == "general"
expect Nostr.answer("ab", Bool.False, "invalid: \"id\"") == "[\"OK\",\"ab\",false,\"invalid: \\\"id\\\"\"]"

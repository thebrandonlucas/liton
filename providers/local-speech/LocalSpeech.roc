## Speech to text from a local engine, as LITON_STT names it:
## sherpa-onnx's offline WebSocket server (`sherpa=ws://127.0.0.1:6006`),
## which takes one binary message of float samples and answers JSON, or
## whisper.cpp's whisper-server (`whisper=http://127.0.0.1:8178`), which takes
## a WAV file posted to /inference. An utterance is 16 kHz 16-bit mono PCM,
## little-endian, as the audio route receives it.
import cap.Capability
import cap.Manifest

LocalSpeech := [].{
	Engine : [Sherpa({ host : Str, port : U16, path : Str }), Whisper(Str)]

	provider : Manifest.Provider
	provider = { id: "local-speech", name: "Local speech", capabilities: [Capability.voice_v1] }

	sample_rate : U32
	sample_rate = 16_000

	## The engine LITON_STT names.
	engine : Str -> Try(Engine, Str)
	engine = |text|
		match text.trim().split_on("=") {
			["sherpa", url] if url.starts_with("ws://") => {
				(address, path) = match url.drop_prefix("ws://").split_first("/") {
					Ok({ before, after }) => (before, "/${after}")
					Err(_) => (url.drop_prefix("ws://"), "/")
				}
				match address.split_on(":") {
					[host, port] if host != "" => U16.from_str(port).map_ok(|number| Sherpa({ host, port: number, path })).map_err(|_| "LITON_STT: ${port} is not a port")
					_ => Err("LITON_STT: expected sherpa=ws://host:port, not ${text}")
				}
			}
			["whisper", url] if url.starts_with("http://") or url.starts_with("https://") => Ok(Whisper(url.drop_suffix("/")))
			_ => Err("LITON_STT: expected sherpa=ws://host:port or whisper=http://host:port, not ${text}")
		}

	## Where the engine is, as logs and errors name it.
	named : Engine -> Str
	named = |given|
		match given {
			Sherpa({ host, port, path }) => "sherpa-onnx at ws://${host}:${port.to_str()}${path}"
			Whisper(url) => "whisper-server at ${url}"
		}

	## sherpa-onnx's one binary message: the sample rate and the samples'
	## byte count as 32-bit integers, then each sample as a 32-bit float, all
	## little-endian.
	samples : List(U8) -> List(U8)
	samples = |pcm| {
		header = little_endian(LocalSpeech.sample_rate.to_u64(), 4).concat(little_endian(pcm.len() // 2 * 4, 4))
		pcm.chunks_of(2).fold(header, |bytes, pair| bytes.concat(little_endian((sample(pair).to_f32() / 32768.0).to_bits().to_u64(), 4)))
	}

	## The text of sherpa-onnx's answer.
	sherpa_text : Str -> Try(Str, [NotAnAnswer(Str)])
	sherpa_text = |answer| {
		decoded : Try({ text : Str }, _)
		decoded = Json.parse(answer)
		decoded.map_ok(|{ text }| text.trim()).map_err(|_| NotAnAnswer(answer))
	}

	## A WAV file of the utterance.
	wav : List(U8) -> List(U8)
	wav = |pcm| {
		size = pcm.len()
		"RIFF".to_utf8()
			.concat(little_endian(36 + size, 4))
			.concat("WAVEfmt ".to_utf8())
			.concat(little_endian(16, 4))
			.concat(little_endian(1, 2)) # PCM
			.concat(little_endian(1, 2)) # mono
			.concat(little_endian(LocalSpeech.sample_rate.to_u64(), 4))
			.concat(little_endian(LocalSpeech.sample_rate.to_u64() * 2, 4)) # bytes per second
			.concat(little_endian(2, 2)) # bytes per sample
			.concat(little_endian(16, 2)) # bits per sample
			.concat("data".to_utf8())
			.concat(little_endian(size, 4))
			.concat(pcm)
	}

	## whisper-server's /inference request: the utterance as a WAV file, and
	## its answer as JSON, decoded greedily.
	inference : List(U8) -> { content_type : Str, body : List(U8) }
	inference = |pcm| {
		field = |name| "--${boundary}\r\nContent-Disposition: form-data; name=\"${name}\""
		opening = "${field("file")}; filename=\"utterance.wav\"\r\nContent-Type: audio/wav\r\n\r\n"
		closing = "\r\n${field("response_format")}\r\n\r\njson\r\n${field("temperature")}\r\n\r\n0.0\r\n--${boundary}--\r\n"
		{ content_type: "multipart/form-data; boundary=${boundary}", body: opening.to_utf8().concat(LocalSpeech.wav(pcm)).concat(closing.to_utf8()) }
	}

	## The text of whisper-server's answer, without the space and newline it
	## puts around it.
	whisper_text : Str -> Try(Str, [NotAnAnswer(Str)])
	whisper_text = LocalSpeech.sherpa_text
}

boundary : Str
boundary = "liton-utterance-6c69746f6e"

## A 16-bit little-endian sample.
sample : List(U8) -> I16
sample = |pair| ((pair.get(1) ?? 0).to_u16() * 256 + (pair.get(0) ?? 0).to_u16()).to_i16_wrap()

little_endian : U64, U64 -> List(U8)
little_endian = |value, count| if (count == 0) [] else [(value % 256).to_u8_wrap()].concat(little_endian(value // 256, count - 1))

expect LocalSpeech.engine("sherpa=ws://127.0.0.1:6006") == Ok(Sherpa({ host: "127.0.0.1", port: 6006, path: "/" }))
expect LocalSpeech.engine(" sherpa=ws://speech.lan:80/asr ") == Ok(Sherpa({ host: "speech.lan", port: 80, path: "/asr" }))
expect LocalSpeech.engine("whisper=http://127.0.0.1:8178/") == Ok(Whisper("http://127.0.0.1:8178"))
expect ["", "sherpa", "sherpa=http://a:1", "sherpa=ws://a", "sherpa=ws://a:x", "whisper=ws://a:1", "vosk=ws://a:1"].all(|text| LocalSpeech.engine(text).is_err())

# Samples 16384, -16384 and -32768 are 0.5, -0.5 and -1.0.
expect LocalSpeech.samples([0x00, 0x40, 0x00, 0xC0, 0x00, 0x80]) == [0x80, 0x3E, 0, 0, 12, 0, 0, 0, 0, 0, 0, 0x3F, 0, 0, 0, 0xBF, 0, 0, 0x80, 0xBF]

expect {
	header = LocalSpeech.wav([1, 2, 3, 4]).take_first(44)
	header == "RIFF".to_utf8().concat([40, 0, 0, 0]).concat("WAVEfmt ".to_utf8()).concat([16, 0, 0, 0, 1, 0, 1, 0, 0x80, 0x3E, 0, 0, 0, 0x7D, 0, 0, 2, 0, 16, 0]).concat("data".to_utf8()).concat([4, 0, 0, 0]) and LocalSpeech.wav([1, 2, 3, 4]).drop_first(44) == [1, 2, 3, 4]
}

expect {
	{ content_type, body } = LocalSpeech.inference([1, 2])
	opening = "--liton-utterance-6c69746f6e\r\nContent-Disposition: form-data; name=\"file\"; filename=\"utterance.wav\"\r\nContent-Type: audio/wav\r\n\r\n"
	closing = "\r\n--liton-utterance-6c69746f6e\r\nContent-Disposition: form-data; name=\"response_format\"\r\n\r\njson\r\n--liton-utterance-6c69746f6e\r\nContent-Disposition: form-data; name=\"temperature\"\r\n\r\n0.0\r\n--liton-utterance-6c69746f6e--\r\n"
	content_type == "multipart/form-data; boundary=liton-utterance-6c69746f6e" and body == opening.to_utf8().concat(LocalSpeech.wav([1, 2])).concat(closing.to_utf8())
}

expect LocalSpeech.sherpa_text("{\"lang\": \"\", \"text\": \"Open the module.\", \"tokens\": [\" O\"], \"timestamps\": [0.00]}") == Ok("Open the module.")
expect LocalSpeech.whisper_text("{\"text\":\" Open the module.\\n\"}") == Ok("Open the module.") and LocalSpeech.whisper_text("busy").is_err()

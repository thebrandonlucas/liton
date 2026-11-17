# The local speech rig (rig/speech/README.md): a speech engine for liton's
# local-speech provider, so audio never leaves the machine. Each engine
# downloads its model first and runs in the foreground, under nixpkgs' when
# it isn't on PATH.
import pf.Cmd
import pf.OsStr
import pf.Path
import pf.Stderr
import Exec

Speech := [].{

	Settings : { rig : Str, models : Str, sherpa_port : Str, whisper_port : Str, threads : Str }

	settings! : () => Try(Settings, _)
	settings! = || {
		rig = Exec.from_root!("rig/speech")?
		Ok({
			rig,
			# Where the models go, which git ignores.
			models: Exec.setting!("RIG_MODELS", "${rig}/models"),
			sherpa_port: Exec.setting!("RIG_SHERPA_PORT", "6006"),
			whisper_port: Exec.setting!("RIG_WHISPER_PORT", "8178"),
			threads: Exec.setting!("RIG_THREADS", "4"),
		})
	}

	Model : [Parakeet, Whisper]

	parakeet : Str
	parakeet = "sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8"

	whisper_model : Str
	whisper_model = "ggml-base.en.bin"

	## Downloads a model into RIG_MODELS, checks its SHA-256 and unpacks it:
	## Parakeet, sherpa's (a 482 MB download, 631 MB unpacked), or whisper's
	## base.en (148 MB). One already there is left alone.
	model! : Settings, Model => Try({}, _)
	model! = |{ models, .. }, model| {
		Path.create_all!(Path.utf8(models))?
		match model {
			Parakeet => {
				if Path.is_file!(Path.utf8("${models}/${parakeet}/tokens.txt")) ?? Bool.False {
					return Ok({})
				}
				part = "${parakeet}.tar.bz2.part"
				downloaded!(models, "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${parakeet}.tar.bz2", part, "6fc4426b54aa549a0019b8a75b8dea59164e71790a37ac56a045ad57f915f714")?
				Exec.call!(models, "tar", ["-xjf", part].concat(["README.md", "tokens.txt", "encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx"].map(|file| "${parakeet}/${file}")))?
				Path.delete!(Path.utf8("${models}/${part}"))
			}
			Whisper => {
				if Path.is_file!(Path.utf8("${models}/${whisper_model}")) ?? Bool.False {
					return Ok({})
				}
				part = "${whisper_model}.part"
				downloaded!(models, "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${whisper_model}", part, "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002")?
				Path.rename!(Path.utf8("${models}/${part}"), Path.utf8("${models}/${whisper_model}"))
			}
		}
	}

	## Runs sherpa-onnx's offline WebSocket server with Parakeet TDT 0.6B v2
	## int8 on RIG_SHERPA_PORT. It writes its log to log.txt, in the rig.
	sherpa! : Settings => Try({}, _)
	sherpa! = |settings| {
		{ rig, models, sherpa_port, threads, .. } = settings
		Speech.model!(settings, Parakeet)?
		model = "${models}/${parakeet}"
		Stderr.line!("Point liton's daemon at it with LITON_STT=sherpa=ws://127.0.0.1:${sherpa_port}")?
		# The server listens on every interface; a firewall keeps it local, or
		# run it in a network namespace of its own.
		Exec.replace!(
			rig,
			|_| Bool.False,
			[],
			"sherpa-onnx-offline-websocket-server",
			[
				"--port=${sherpa_port}",
				"--num-work-threads=1",
				"--num-io-threads=1",
				"--num-threads=${threads}",
				"--model-type=nemo_transducer",
				"--tokens=${model}/tokens.txt",
				"--encoder=${model}/encoder.int8.onnx",
				"--decoder=${model}/decoder.int8.onnx",
				"--joiner=${model}/joiner.int8.onnx",
			],
		)
	}

	## Runs whisper.cpp's whisper-server with base.en on
	## 127.0.0.1:RIG_WHISPER_PORT.
	whisper! : Settings => Try({}, _)
	whisper! = |settings| {
		{ models, whisper_port, threads, .. } = settings
		Speech.model!(settings, Whisper)?
		Stderr.line!("Point liton's daemon at it with LITON_STT=whisper=http://127.0.0.1:${whisper_port}")?
		Exec.replace!(Exec.from_root!("")?, |_| Bool.False, [], "whisper-server", ["-m", "${models}/${whisper_model}", "--host", "127.0.0.1", "--port", whisper_port, "-t", threads])
	}
}

## Download `url` to `part` in `directory` and check its SHA-256.
downloaded! : Str, Str, Str, Str => Try({}, _)
downloaded! = |directory, url, part, sha256| {
	Exec.call!(directory, "curl", ["-fL", "--retry", "3", "-o", part, url])?
	Cmd.new(OsStr.from_str("sha256sum"))
		.args(["-c", "-"].map(OsStr.from_str))
		.cwd(Path.utf8(directory))
		.stdin(Bytes("${sha256}  ${part}\n".to_utf8()))
		.call!()
}

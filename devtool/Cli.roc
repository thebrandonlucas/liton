## The development tool's pure part: what its arguments ask for.
Cli := [].{

	Command : [Help, Usage(Str), Ui({ roc_ui : Str, output : Str, runtime_files : List(Str), flags : List(Str) }), Specs(Str), Previews(Str), Docs({ roc : Str, roc_ui : Str, output : Str }), Paseo([Daemon, Relay, Bridge, Cli(List(Str))]), Speech([Model([Parakeet, Whisper]), Sherpa, Whisper])]

	usage : Str
	usage =
		\\Usage: zig build devtool -- <command> [arguments]
		\\
		\\Commands:
		\\  paseo daemon          a throwaway Paseo daemon on 127.0.0.1:16767 (rig/paseo/)
		\\  paseo cli <args>...   Paseo's CLI against it
		\\  paseo relay           Paseo's relay, locally in workerd
		\\  paseo bridge          liton's relay bridge, paired with the daemon through the relay
		\\  speech model parakeet|whisper
		\\                        download a speech model into rig/speech/models
		\\  speech sherpa         sherpa-onnx with Parakeet on port 6006 (rig/speech/)
		\\  speech whisper        whisper.cpp's whisper-server on 127.0.0.1:8178
		\\  ui <roc-ui> <output> <runtime.mjs> <environment.mjs> <startup.mjs> <worker.mjs> [<flag>...]
		\\                        build the browser UI into the directory output (zig build ui)
		\\  spec <runner>         run the UI's specs in roc-signals's native runner (zig build spec)
		\\  previews <cdp.mjs>    render each surface and part into ui/previews/*.webp in headless
		\\                        Chrome (CHROME), against the mock daemon (zig build devtool -Dfast
		\\                        -- previews, which builds the UI and the daemon first)
		\\  docs <roc> <roc-ui> <output>
		\\                        the packages' and apps' API docs into the directory output (zig build docs)
		\\  help
		\\
		\\liton's development tasks, in Roc, run from the repository's root.
		\\The rigs run in the foreground; rig/paseo/README.md and
		\\rig/speech/README.md list the settings that override their defaults.

	parse : List(Str) -> Command
	parse = |arguments|
		match arguments {
			[] | ["help"] | ["--help"] | ["-h"] => Help
			["ui", roc_ui, output, runtime, environment, startup, worker, .. as flags] => Ui({ roc_ui, output, runtime_files: [runtime, environment, startup, worker], flags })
			["spec", runner] => Specs(runner)
			["previews", cdp] => Previews(cdp)
			["docs", roc, roc_ui, output] => Docs({ roc, roc_ui, output })
			["paseo", "daemon"] => Paseo(Daemon)
			["paseo", "relay"] => Paseo(Relay)
			["paseo", "bridge"] => Paseo(Bridge)
			["paseo", "cli", .. as rest] => Paseo(Cli(rest))
			["speech", "model", "parakeet"] => Speech(Model(Parakeet))
			["speech", "model", "whisper"] => Speech(Model(Whisper))
			["speech", "sherpa"] => Speech(Sherpa)
			["speech", "whisper"] => Speech(Whisper)
			[command, ..] => Usage("unknown command or arguments for ${command}")
		}
}

expect Cli.parse([]) == Help and Cli.parse(["help"]) == Help
expect Cli.parse(["previews", "cdp.mjs"]) == Previews("cdp.mjs") and Cli.parse(["previews"]) == Usage("unknown command or arguments for previews")
expect Cli.parse(["deploy"]) == Usage("unknown command or arguments for deploy")
expect Cli.parse(["paseo", "cli", "daemon", "pair", "--json"]) == Paseo(Cli(["daemon", "pair", "--json"])) and Cli.parse(["paseo", "relay"]) == Paseo(Relay)
expect Cli.parse(["speech", "model", "parakeet"]) == Speech(Model(Parakeet)) and Cli.parse(["speech", "model"]) == Usage("unknown command or arguments for speech")
expect Cli.parse(["ui", "roc-ui", "www", "r.mjs", "e.mjs", "s.mjs", "w.mjs", "--specialize=no"]) == Ui({ roc_ui: "roc-ui", output: "www", runtime_files: ["r.mjs", "e.mjs", "s.mjs", "w.mjs"], flags: ["--specialize=no"] })
expect Cli.parse(["docs", "roc", "roc-ui", "docs"]) == Docs({ roc: "roc", roc_ui: "roc-ui", output: "docs" })

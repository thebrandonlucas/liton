## liton's development tool: the tasks that would otherwise be shell scripts,
## as kai's devtool does them. Cli.roc decides what the arguments ask for;
## this runs it. Exits 2 on a usage error.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.0/2yhxoR7cZPSYbyUzPWULFw8AA6QEcdsgFNRmzu7pZbst.tar.zst",
}

import pf.OsStr
import pf.Stderr
import pf.Stdout
import Cli
import Exec
import Paseo
import Speech

main! : List(OsStr) => Try({}, _)
main! = |arguments| {
	given = arguments.map(OsStr.display)
	match Cli.parse(given) {
		Help => Stdout.line!(Cli.usage)
		Usage(problem) => {
			Stderr.line!("liton-devtool: ${problem}\n\n${Cli.usage}")?
			Err(Exit(2))
		}
		Paseo(command) => {
			Exec.needs!("node", "nodejs", given)?
			settings = Paseo.settings!()?
			match command {
				Daemon => Paseo.daemon!(settings)
				Relay => Paseo.relay!(settings)
				Bridge => Paseo.bridge!(settings)
				Cli(rest) => Paseo.cli!(settings, rest)
			}
		}
		Speech(Model(model)) => Speech.model!(Speech.settings!()?, model)
		Speech(Sherpa) => {
			Exec.needs!("sherpa-onnx-offline-websocket-server", "sherpa-onnx", given)?
			Speech.sherpa!(Speech.settings!()?)
		}
		Speech(Whisper) => {
			Exec.needs!("whisper-server", "whisper-cpp", given)?
			Speech.whisper!(Speech.settings!()?)
		}
	}
}

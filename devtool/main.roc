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

main! : List(OsStr) => Try({}, _)
main! = |arguments|
	match Cli.parse(arguments.map(OsStr.display)) {
		Help => Stdout.line!(Cli.usage)
		Usage(problem) => {
			Stderr.line!("liton-devtool: ${problem}\n\n${Cli.usage}")?
			Err(Exit(2))
		}
	}

## The development tool's pure part: what its arguments ask for.
Cli := [].{

	Command : [Help, Usage(Str)]

	usage : Str
	usage =
		\\Usage: zig build devtool -- <command> [arguments]
		\\
		\\Commands:
		\\  help
		\\
		\\liton's development tasks, in Roc, run from the repository's root.

	parse : List(Str) -> Command
	parse = |arguments|
		match arguments {
			[] | ["help"] | ["--help"] | ["-h"] => Help
			[command, ..] => Usage("unknown command or arguments for ${command}")
		}
}

expect Cli.parse([]) == Help and Cli.parse(["help"]) == Help
expect Cli.parse(["deploy"]) == Usage("unknown command or arguments for deploy")

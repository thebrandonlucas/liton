# Commands as the rigs run them: tools on the developer's PATH, run from the
# repository's root, and a last one that takes this process's place, as a
# shell script's `exec` does.
import pf.Cmd
import pf.Env
import pf.OsStr
import pf.Path
import pf.System

Exec := [].{

	## The setting `name` holds in the environment, or `default`.
	setting! : Str, Str => Str
	setting! = |name, default| Env.var_str!(OsStr.from_str(name)) ?? default

	## The absolute path of `relative`, from the repository's root, where
	## `zig build` runs the development tool.
	from_root! : Str => Try(Str, _)
	from_root! = |relative| Ok("${Env.cwd!()?.display()}/${relative}")

	## Run `program` with `arguments` in `directory` on this terminal, failing
	## unless it exits 0.
	call! : Str, Str, List(Str) => Try({}, _)
	call! = |directory, program, arguments|
		Cmd.new(OsStr.from_str(program)).args(arguments.map(OsStr.from_str)).cwd(Path.utf8(directory)).call!()

	## Run `program` with `arguments` in `directory` in place of this process,
	## in this process's environment without `dropped` and with `settings`.
	## Its PATH finds `program`, through env(1).
	replace! : Str, (Str -> Bool), List((Str, Str)), Str, List(Str) => Try({}, _)
	replace! = |directory, dropped, settings, program, arguments| {
		unix = match System.target!().os() {
			Linux(linux) => linux.unix()
			MacOS(mac) => mac.unix()
			Windows(_) => return Err(Unsupported("the rigs run on Linux and macOS"))
		}
		inherited = Env.dict!().keep_oks(|(name, value)| Ok((OsStr.display(name), OsStr.display(value))))
		environment_arguments = Exec.environment(inherited, dropped, settings)
		Env.set_cwd!(Path.utf8(directory))?
		Cmd.exec!(unix, Path.utf8("/usr/bin/env"), ["-i"].concat(environment_arguments).append(program).concat(arguments).map(OsStr.from_str))
	}

	## env(1)'s NAME=VALUE arguments for `inherited` without `dropped` or a
	## name `settings` sets, then `settings`.
	environment : List((Str, Str)), (Str -> Bool), List((Str, Str)) -> List(Str)
	environment = |inherited, dropped, settings| {
		set = settings.map(|(name, _)| name)
		inherited
			.drop_if(|(name, _)| dropped(name) or set.contains(name))
			.concat(settings)
			.map(|(name, value)| "${name}=${value}")
	}

	## Run this tool again under `nix shell nixpkgs#<nix_package>` when `program`
	## isn't on PATH, as the rigs do for what the development environment
	## doesn't hold.
	needs! : Str, Str, List(Str) => Try({}, _)
	needs! = |program, nix_package, arguments|
		if Cmd.check_available!(program) {
			Ok({})
		} else {
			tool = Env.exe_path!()?.display()
			directory = Env.cwd!()?.display()
			Exec.replace!(directory, |_| Bool.False, [], "nix", ["shell", "nixpkgs#${nix_package}", "-c", tool].concat(arguments))
		}
}

expect Exec.environment([("PATH", "/bin"), ("PASEO_HOST", "elsewhere"), ("HOME", "/home/me")], |name| name.starts_with("PASEO_"), [("HOME", "/rig"), ("PASEO_PASSWORD", "p")]) == ["PATH=/bin", "HOME=/rig", "PASEO_PASSWORD=p"]

# The local Paseo rig (rig/paseo/README.md): a throwaway Paseo 0.15.3 daemon,
# its CLI, Paseo's relay and liton's relay bridge, each on 127.0.0.1 only and
# in the foreground. Each forgets any PASEO_* setting this shell inherited,
# such as those Paseo gives the agents it runs: they would point the rig at
# another daemon or agent. Each installs its pinned npm packages first.
import pf.Cmd
import pf.OsStr
import pf.Path
import pf.Stderr
import Exec

Paseo := [].{

	## The rig's settings, each overridden from the environment. The
	## throwaway home is both HOME and PASEO_HOME, so the daemon and its
	## agents read no real credentials or history; deleting it resets it.
	Settings : { rig : Str, home : Str, port : Str, password : Str, relay_enabled : Str, relay_port : Str, bridge_port : Str }

	settings! : () => Try(Settings, _)
	settings! = || {
		rig = Exec.from_root!("rig/paseo")?
		Ok({
			rig,
			home: Exec.setting!("RIG_HOME", "${rig}/home"),
			port: Exec.setting!("RIG_PORT", "16767"),
			password: Exec.setting!("RIG_PASSWORD", "liton-rig-password"),
			relay_enabled: Exec.setting!("RIG_RELAY", "false"),
			relay_port: Exec.setting!("RIG_RELAY_PORT", "18787"),
			bridge_port: Exec.setting!("RIG_BRIDGE_PORT", "18767"),
		})
	}

	inherited_paseo : Str -> Bool
	inherited_paseo = |name| name.starts_with("PASEO_")

	## Paseo's config, with voice, dictation and the web UI off, as the sandbox
	## architecture has them, and the relay the local one, if enabled.
	config : Settings -> Str
	config = |{ relay_enabled, relay_port, .. }|
		\\{"features":{"dictation":{"enabled":false},"voiceMode":{"enabled":false},"webUi":{"enabled":false}},
		\\ "daemon":{"relay":{"enabled":${relay_enabled},"endpoint":"127.0.0.1:${relay_port}","useTls":false,"requireProtectedSecurity":true}}}
		\\

	## Runs a throwaway Paseo daemon; RIG_RELAY=true also connects it to the
	## local relay. It never connects to Paseo's hosted one.
	daemon! : Settings => Try({}, _)
	daemon! = |settings| {
		{ rig, home, port, password, relay_enabled, relay_port, .. } = settings
		installed!(rig, "paseo", ["--ignore-scripts"])?
		Path.create_all!(Path.utf8(home))?
		Path.write_utf8!(Path.utf8("${home}/config.json"), Paseo.config(settings))?
		Stderr.line!(
			\\Point liton's daemon at it with:
			\\  PASEO_HOST=127.0.0.1 PASEO_PORT=${port} PASEO_PASSWORD=${password}
			\\Use Paseo's CLI against it with `zig build devtool -- paseo cli`, as in `zig build devtool -- paseo cli ls`
		)?
		# PASEO_NODE_ENV=development enables Paseo's "mock" provider, a scripted
		# agent that needs no model or account (see README.md).
		Exec.replace!(
			rig,
			inherited_paseo,
			[
				("HOME", home),
				("PASEO_HOME", home),
				("PASEO_LISTEN", "127.0.0.1:${port}"),
				("PASEO_PASSWORD", password),
				("PASEO_RELAY_ENABLED", relay_enabled),
				("PASEO_RELAY_ENDPOINT", "127.0.0.1:${relay_port}"),
				("PASEO_RELAY_USE_TLS", "false"),
				("PASEO_WEB_UI_ENABLED", "false"),
				("PASEO_DICTATION_ENABLED", "false"),
				("PASEO_VOICE_MODE_ENABLED", "false"),
				("PASEO_NODE_ENV", "development"),
			],
			"${rig}/node_modules/.bin/paseo",
			["daemon", "run", "--home", home],
		)
	}

	## Paseo's CLI against the rig's daemon, as in `paseo cli ls`.
	cli! : Settings, List(Str) => Try({}, _)
	cli! = |{ rig, home, password, .. }, arguments| {
		installed!(rig, "paseo", ["--ignore-scripts"])?
		directory = Exec.from_root!("")?
		Exec.replace!(directory, inherited_paseo, cli_environment(home, password), "${rig}/node_modules/.bin/paseo", ["--home", home].concat(arguments))
	}

	## Runs Paseo's relay locally in workerd. Its wrangler.toml has no account,
	## routes or upstream, so nothing reaches a hosted relay.
	relay! : Settings => Try({}, _)
	relay! = |{ rig, relay_port, .. }| {
		installed!("${rig}/relay", "wrangler", [])?
		Exec.replace!("${rig}/relay", inherited_paseo, [("WRANGLER_SEND_METRICS", "false")], "node_modules/.bin/wrangler", ["dev", "--local", "--ip", "127.0.0.1", "--port", relay_port])
	}

	## Runs liton's Paseo relay bridge (bridges/paseo-relay), paired with the
	## rig's daemon through the local relay: start the relay, then the daemon
	## with RIG_RELAY=true, then this. It listens on 127.0.0.1:RIG_BRIDGE_PORT.
	bridge! : Settings => Try({}, _)
	bridge! = |{ rig, home, password, bridge_port, .. }| {
		bridge = Exec.from_root!("bridges/paseo-relay")?
		if !(Path.is_dir!(Path.utf8("${bridge}/node_modules/@getpaseo/relay"))?) {
			Exec.call!(bridge, "npm", ["install", "--no-audit", "--no-fund"])?
		}
		paired = Cmd.new(OsStr.from_str("${rig}/node_modules/.bin/paseo"))
			.args(["--home", home, "daemon", "pair", "--json"].map(OsStr.from_str))
			.envs(cli_environment(home, password).map(|(name, value)| (OsStr.from_str(name), OsStr.from_str(value))))
			.capture!()?
		offer_url = match Paseo.offer(paired) {
			Ok(url) => url
			Err(_) => return Err(NoPairingOffer(paired))
		}
		Stderr.line!(
			\\Point liton's daemon at it with (the bridge holds the password; liton's is ignored):
			\\  PASEO_HOST=127.0.0.1 PASEO_PORT=${bridge_port} PASEO_PASSWORD=bridge
		)?
		Exec.replace!(
			Exec.from_root!("")?,
			inherited_paseo,
			[("PASEO_BRIDGE_OFFER", offer_url), ("PASEO_BRIDGE_PASSWORD", password), ("PASEO_BRIDGE_PORT", bridge_port)],
			"node",
			["${bridge}/bridge.mjs"],
		)
	}

	## The pairing offer's URL, from `paseo daemon pair --json`.
	offer : Str -> Try(Str, _)
	offer = |printed| {
		pairing : Try({ url : Str }, _)
		pairing = Json.parse(printed.trim())
		pairing.map_ok(|{ url }| url)
	}
}

cli_environment : Str, Str -> List((Str, Str))
cli_environment = |home, password| [("HOME", home), ("PASEO_HOME", home), ("PASEO_PASSWORD", password)]

## Install `directory`'s pinned npm packages unless its `tool` is there.
installed! : Str, Str, List(Str) => Try({}, _)
installed! = |directory, tool, flags|
	if Path.is_executable!(Path.utf8("${directory}/node_modules/.bin/${tool}")) ?? Bool.False {
		Ok({})
	} else {
		Exec.call!(directory, "npm", ["install"].concat(flags).concat(["--no-audit", "--no-fund"]))
	}

expect Paseo.offer("{\"url\":\"https://app.paseo.sh/#offer=abc\",\"relay\":\"127.0.0.1:18787\"}\n") == Ok("https://app.paseo.sh/#offer=abc")
expect Paseo.config({ rig: "", home: "", port: "", password: "", relay_enabled: "true", relay_port: "18787", bridge_port: "" }).contains("\"enabled\":true,\"endpoint\":\"127.0.0.1:18787\"")

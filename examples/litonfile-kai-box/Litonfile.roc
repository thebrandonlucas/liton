## A Kai box's setup, for a client's staff: rooms alone, in the Sky theme,
## with no agents' sessions, code or attention to show. Its staff and its
## agents hold roles that keep them to the rooms, the staff's UI locked;
## the owner, an operator, signs in on the box with `liton pair`.
## `liton setup examples/litonfile-kai-box/Litonfile.roc` evaluates it into
## the liton.setup.json the box's services.liton.setupFile names (liton.nix).
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	setup: "../../setup/main.roc",
}

import pf.Stdout
import setup.Default
import setup.Setup

setup : Setup.Declared
setup = {
	..Setup.empty,
	presets: [Default.rooms],
	default_preset: Default.rooms.name,
	themes: [Default.sky],
	default_theme: Default.sky.name,
	deck: [Default.rooms.name],
	roles: [
		{ name: "staff", capabilities: ["rooms.v1", "voice.v1", "attention.v1"], presets: [Default.rooms.name], locked: Bool.True },
		{ name: "agent", capabilities: ["rooms.v1"], presets: [], locked: Bool.True },
	],
}

main! = |_arguments| Stdout.line!(Setup.to_json(setup))

expect setup.presets.map(|preset| preset.name) == ["Rooms"] and setup.deck == ["Rooms"] and setup.transformers == [] and setup.roles.map(|role| role.name) == ["staff", "agent"]

## A setup and the layouts its presets hold. A preset is a named snapshot,
## the JSON the UI saves of its layout, so loading one is loading a snapshot.
## Keys and options are still to come.
Setup := [].{

	## Where a column sits: in a Workbench's left drawer, main area or right
	## drawer, or anywhere (`Free`) in Tiling, which takes every widget.
	Slot : [Left, Main, Right, Free]

	## How columns are laid out: freely in Tiling, or in a Workbench's three
	## slots, the left drawer, the main area and the right drawer.
	Shell : [Workbench, Tiling]

	## `pinned` is the session a pane shows whatever the focus is, or "" to
	## follow the focus. `options` holds the values set of its widget's options;
	## the rest have their defaults.
	Pane : { id : Str, widget : Str, pinned : Str, options : List({ key : Str, value : Str }) }

	## Panes side by side make a row of columns. A column stacks its panes, or
	## when `tabbed` shows only its `active` one. `size` weighs its width.
	Column : { id : Str, size : U32, tabbed : Bool, active : Str, panes : List(Pane) }

	## A layout as deterministic JSON others can load. `collapsed` are the
	## Workbench drawers hidden.
	Snapshot : { version : U32, shell : Shell, columns : List(Column), collapsed : List(Slot) }

	Preset : { name : Str, snapshot : Snapshot }

	## A provider outside the daemon, a server of /liton/v1 (docs/protocol.md).
	Remote : { name : Str, url : Str }

	## The remotes the daemon connects, the transformers it hosts by id, the
	## presets its clients offer and the one they start with.
	Declared : { remotes : List(Remote), transformers : List(Str), presets : List(Preset), default_preset : Str }

	## What a daemon's manifest offers of its setup.
	Offered : { presets : List(Preset), default_preset : Str }

	## The version of the snapshots this layout describes.
	snapshot_version : U32
	snapshot_version = 4

	empty : Declared
	empty = { remotes: [], transformers: [], presets: [], default_preset: "" }

	## Adds a remote, in place of one of the same name.
	with_remote : Declared, Remote -> Declared
	with_remote = |setup, remote| { ..setup, remotes: replaced(setup.remotes, remote, |old| old.name == remote.name) }

	without_remote : Declared, Str -> Declared
	without_remote = |setup, name| { ..setup, remotes: setup.remotes.drop_if(|remote| remote.name == name) }

	with_transformer : Declared, Str -> Declared
	with_transformer = |setup, id| { ..setup, transformers: replaced(setup.transformers, id, |old| old == id) }

	without_transformer : Declared, Str -> Declared
	without_transformer = |setup, id| { ..setup, transformers: setup.transformers.drop_if(|old| old == id) }

	## Adds a preset, in place of one of the same name.
	with_preset : Declared, Preset -> Declared
	with_preset = |setup, preset| { ..setup, presets: replaced(setup.presets, preset, |old| old.name == preset.name) }

	without_preset : Declared, Str -> Declared
	without_preset = |setup, name| { ..setup, presets: setup.presets.drop_if(|preset| preset.name == name) }

	with_default_preset : Declared, Str -> Declared
	with_default_preset = |setup, name| { ..setup, default_preset: name }

	## `base` with what `changes` declares added over it: its remotes and
	## presets in place of those of the same name, its transformers, and its
	## default preset if it names one.
	merge : Declared, Declared -> Declared
	merge = |base, changes| {
		with_all = |setup, items, add| items.fold(setup, add)
		merged = with_all(with_all(with_all(base, changes.remotes, Setup.with_remote), changes.transformers, Setup.with_transformer), changes.presets, Setup.with_preset)
		if (changes.default_preset.is_empty()) merged else Setup.with_default_preset(merged, changes.default_preset)
	}

	offered : Declared -> Offered
	offered = |{ presets, default_preset, .. }| { presets, default_preset }

	## The preset a client starts with: the default, or the first if it names
	## none there is.
	starting : Offered -> Try(Preset, [NoPresets])
	starting = |{ presets, default_preset }|
		match presets.find_first(|preset| preset.name == default_preset) {
			Ok(preset) => Ok(preset)
			Err(NotFound) => presets.first().map_err(|_| NoPresets)
		}

	## A setup as JSON, its fields in order, so the same setup is the same text.
	to_json : Declared -> Str
	to_json = |setup| Json.to_str(setup)

	from_json : Str -> Try(Declared, [Invalid])
	from_json = |text| {
		parsed : Try(Declared, _)
		parsed = Json.parse(text)
		parsed.map_err(|_| Invalid)
	}
}

## `items` with `item` in place of the first that `same` picks, or after them.
replaced : List(a), a, (a -> Bool) -> List(a)
replaced = |items, item, same|
	match items.find_first_index(same) {
		Ok(index) => items.map_with_index(|old, at| if (at == index) item else old)
		Err(NotFound) => items.append(item)
	}

layout : Str -> Setup.Snapshot
layout = |widget| { version: Setup.snapshot_version, shell: Tiling, columns: [{ id: "column-1", size: 1, tabbed: Bool.False, active: "pane-1", panes: [{ id: "pane-1", widget, pinned: "", options: [] }] }], collapsed: [] }

chat : Setup.Preset
chat = { name: "Chat", snapshot: layout("chat") }

echo : Setup.Remote
echo = { name: "echo", url: "http://127.0.0.1:8096" }

expect Setup.with_remote(Setup.with_remote(Setup.empty, echo), { ..echo, url: "https://echo.example" }).remotes == [{ ..echo, url: "https://echo.example" }]
expect Setup.without_remote(Setup.with_remote(Setup.empty, echo), "echo").remotes == []
expect Setup.without_transformer(Setup.with_transformer(Setup.with_transformer(Setup.with_transformer(Setup.empty, "attention"), "needs-you"), "attention"), "attention").transformers == ["needs-you"]
expect {
	inbox = { name: "Inbox", snapshot: layout("inbox") }
	presets = Setup.with_preset(Setup.with_preset(Setup.with_preset(Setup.empty, chat), inbox), { ..chat, snapshot: layout("sessions") }).presets
	presets == [{ ..chat, snapshot: layout("sessions") }, inbox] and Setup.without_preset({ ..Setup.empty, presets }, "Chat").presets == [inbox]
}
expect {
	base = { remotes: [echo], transformers: ["attention"], presets: [chat], default_preset: "Chat" }
	team = { remotes: [{ name: "team", url: "https://liton.example" }], transformers: ["needs-you"], presets: [{ name: "Inbox", snapshot: layout("inbox") }], default_preset: "" }
	merged = Setup.merge(base, team)
	merged.remotes.map(|remote| remote.name) == ["echo", "team"] and merged.transformers == ["attention", "needs-you"] and merged.presets.map(|preset| preset.name) == ["Chat", "Inbox"] and merged.default_preset == "Chat" and Setup.merge(base, { ..team, default_preset: "Inbox" }).default_preset == "Inbox"
}
expect Setup.starting({ presets: [chat], default_preset: "Chat" }) == Ok(chat) and Setup.starting({ presets: [chat], default_preset: "Gone" }) == Ok(chat) and Setup.starting({ presets: [], default_preset: "Chat" }) == Err(NoPresets)

# Fields in order, so a setup is always the same text, and it reads back.
expect {
	setup = { remotes: [echo], transformers: ["attention"], presets: [chat], default_preset: "Chat" }
	text = Setup.to_json(setup)
	text == "{\"default_preset\":\"Chat\",\"presets\":[{\"name\":\"Chat\",\"snapshot\":{\"collapsed\":[],\"columns\":[{\"active\":\"pane-1\",\"id\":\"column-1\",\"panes\":[{\"id\":\"pane-1\",\"options\":[],\"pinned\":\"\",\"widget\":\"chat\"}],\"size\":1,\"tabbed\":false}],\"shell\":\"Tiling\",\"version\":4}}],\"remotes\":[{\"name\":\"echo\",\"url\":\"http://127.0.0.1:8096\"}],\"transformers\":[\"attention\"]}" and Setup.from_json(text) == Ok(setup)
}
expect Setup.from_json("{\"remotes\":[]}") == Err(Invalid)

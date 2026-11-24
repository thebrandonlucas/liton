## A setup, the layouts its presets hold and the themes it offers. A preset
## is a named snapshot, the JSON the UI saves of its layout, so loading one is
## loading a snapshot. Keys and options are still to come.
import Grid

Setup := [].{

	## Where a tile sits: in a Workbench's left drawer, main area or right
	## drawer, or anywhere (`Free`) in Tiling, which takes every widget.
	Slot : [Left, Main, Right, Free]

	## How tiles are laid out: freely in Tiling, or in a Workbench's three
	## slots, the left drawer, the main area and the right drawer.
	Shell : [Workbench, Tiling]

	## How a layout's tiles look: `Joined`, one frame under one header,
	## its panes apart by hairlines, or `Tiles`, each a frame of its own with
	## the theme's gap between them.
	Frame : [Joined, Tiles]

	## A pane of a tile: its widget, the context it is pinned to, and its
	## options.
	Pane : Grid.Pane

	## A column of panes, as snapshots before version 8 laid them out side by
	## side. It stacks its panes, or when `tabbed` shows only its `active`
	## one. `size` weighs its width.
	Column : { id : Str, size : U32, tabbed : Bool, active : Str, panes : List(Pane) }

	## A layout as deterministic JSON others can load: its grid of tiles.
	## `collapsed` are the Workbench drawers hidden, and `hidden` the ids of
	## the panes it hides, which their tile's ⋯ menus show again. `theme`
	## names the theme it shows, or is "" for the setup's default; a preset's
	## "" keeps the theme shown. `frame` is how its tiles look.
	Snapshot : { version : U32, shell : Shell, frame : Frame, grid : Grid.Layout, collapsed : List(Slot), hidden : List(Str), theme : Str }

	## A snapshot as it was before snapshots named their frame.
	Unframed : { version : U32, shell : Shell, grid : Grid.Layout, collapsed : List(Slot), hidden : List(Str), theme : Str }

	## A layout to start from, named: a snapshot of the UI's layout.
	Preset : { name : Str, snapshot : Snapshot }

	## The surfaces a browser switches between, in order, each a preset as
	## it was last left: what the UI keeps from snapshot version 9.
	Deck : { version : U32, surfaces : List(Preset) }

	## How the UI looks: a light or dark `scheme`; an `accent`, which the
	## focused tile's edge fades into `accent_to` along; the text colors; how
	## much of the accent, in percent, the tiles' faint `edge` and the focused
	## one's `edge_active` hold; the tiles' `glass`, a tint, its opacity in
	## percent and its blur in pixels (0 for none); what is behind the tiles: a
	## gradient, a color, or an image at a URL dimmed by `dim` percent at its
	## centre and more towards its edges;
	## the gap between them and their corners' radius in pixels; the font
	## stacks of text, of the monospace chrome and of the display face; and
	## whether things move. Colors are CSS colors.
	Theme : {
		name : Str,
		scheme : [Light, Dark],
		accent : Str,
		accent_to : Str,
		text : Str,
		muted : Str,
		edge : U8,
		edge_active : U8,
		glass : { tint : Str, opacity : U8, blur : U8 },
		background : [Gradient({ base : Str, from : Str, to : Str, glow : Str }), Flat(Str), Image({ url : Str, dim : U8 })],
		gap : U8,
		radius : U8,
		fonts : { ui : Str, mono : Str, display : Str },
		motion : [Normal, Reduced],
	}

	## A provider outside the daemon, a server of /liton/v1 (docs/protocol.md).
	Remote : { name : Str, url : Str }

	## What a key may do that holds the role `name`: call and poll the
	## `capabilities` named, such as "rooms.v1", and be offered the `presets`
	## named; `locked`, its UI's layout and settings stay as they are. Which
	## key holds which role is the daemon's to keep. The role `operator`, the
	## owner's and any other key's without one, may do everything.
	Role : { name : Str, capabilities : List(Str), presets : List(Str), locked : Bool }

	## A room of the daemon's relay a box starts with: the daemon creates it
	## at start unless the relay has one of its id, its name's letters and
	## digits, lowercased and joined by hyphens, even one deleted since, so a
	## box rebuilt from its setup has its rooms again. A channel, a forum, a
	## direct conversation or announcements; `open`, a key whose role uses
	## rooms joins it itself, else its admins add its members.
	Room : { name : Str, about : Str, kind : [Channel, Forum, Direct, Announce], private : Bool, open : Bool }

	## The remotes the daemon connects, the transformers it hosts by id, the
	## presets and themes its clients offer and the ones they start with,
	## the presets, by name, a new browser's deck holds after it, its
	## `owner`'s Nostr key, an operator always ("" for none), and the roles
	## its keys may hold, and the rooms its relay starts with.
	Declared : { remotes : List(Remote), transformers : List(Str), presets : List(Preset), default_preset : Str, themes : List(Theme), default_theme : Str, deck : List(Str), owner : Str, roles : List(Role), rooms : List(Room) }

	## What a daemon's manifest offers of its setup.
	Offered : { presets : List(Preset), default_preset : Str, themes : List(Theme), default_theme : Str, deck : List(Str) }

	## The version of the snapshots this layout describes. From version 9 a
	## browser keeps a deck of them.
	snapshot_version : U32
	snapshot_version = 9

	## The frame of a snapshot that names none: a Workbench's joined,
	## Tiling's tiles.
	frame_of : Shell -> Frame
	frame_of = |shell| if (shell == Workbench) Joined else Tiles

	## `snapshot` in the frame `framing` read, else in its shell's.
	framed : Unframed, Try(Frame, _) -> Snapshot
	framed = |{ version, shell, grid, collapsed, hidden, theme }, framing| { version, shell, frame: framing ?? Setup.frame_of(shell), grid, collapsed, hidden, theme }

	## Presets read as before snapshots named their frame, in the `frames`
	## read of them, if any.
	framed_presets : List({ name : Str, snapshot : Unframed }), List(Frame) -> List(Preset)
	framed_presets = |presets, frames| presets.map_with_index(|{ name, snapshot }, index| { name, snapshot: Setup.framed(snapshot, frames.get(index)) })

	## The grid of columns side by side, as snapshots before version 8 laid
	## them out: a tile for each column of tabs and each pane a column stacks,
	## over rows cut where any column's stacked panes meet.
	grid_of : List(Column) -> Grid.Layout
	grid_of = |columns| {
		counts = columns.map(|column| if (column.tabbed or column.panes.len() < 2) 1 else column.panes.len())
		common = counts.fold(1, |product, count| product * count // divisor(product, count))
		lines = List.repeat(0, common + 1).map_with_index(|_, at| at).keep_if(|at| counts.any(|count| (at * count) % common == 0))
		row_of = |at| lines.find_first_index(|line| line == at) ?? 0
		tiles = columns.map_with_index(|column, index| (column, index)).join_map(
			|(column, index)|
				match counts.get(index) ?? 1 {
					1 => [{ id: column.id, left: index, top: 0, right: index + 1, bottom: lines.len() - 1, active: column.active, panes: column.panes }]
					count => column.panes.map_with_index(|pane, at| { id: if (at == 0) column.id else "${column.id}-${pane.id}", left: index, top: row_of(at * common // count), right: index + 1, bottom: row_of((at + 1) * common // count), active: pane.id, panes: [pane] })
				},
		)
		Grid.normalized({ columns: columns.map(|column| column.size.to_u64()), rows: lines.drop_first(1).map_with_index(|line, at| line - (lines.get(at) ?? 0)), tiles })
	}

	## A setup that declares nothing.
	empty : Declared
	empty = { remotes: [], transformers: [], presets: [], default_preset: "", themes: [], default_theme: "", deck: [], owner: "", roles: [], rooms: [] }

	## Adds a remote, in place of one of the same name.
	with_remote : Declared, Remote -> Declared
	with_remote = |setup, remote| { ..setup, remotes: replaced(setup.remotes, remote, |old| old.name == remote.name) }

	## Takes away the remote called `name`.
	without_remote : Declared, Str -> Declared
	without_remote = |setup, name| { ..setup, remotes: setup.remotes.drop_if(|remote| remote.name == name) }

	## Hosts the transformer `id`, once.
	with_transformer : Declared, Str -> Declared
	with_transformer = |setup, id| { ..setup, transformers: replaced(setup.transformers, id, |old| old == id) }

	## No longer hosts the transformer `id`.
	without_transformer : Declared, Str -> Declared
	without_transformer = |setup, id| { ..setup, transformers: setup.transformers.drop_if(|old| old == id) }

	## Adds a preset, in place of one of the same name.
	with_preset : Declared, Preset -> Declared
	with_preset = |setup, preset| { ..setup, presets: replaced(setup.presets, preset, |old| old.name == preset.name) }

	## Takes away the preset called `name`.
	without_preset : Declared, Str -> Declared
	without_preset = |setup, name| { ..setup, presets: setup.presets.drop_if(|preset| preset.name == name) }

	## Makes the preset called `name` the one clients start with.
	with_default_preset : Declared, Str -> Declared
	with_default_preset = |setup, name| { ..setup, default_preset: name }

	## Adds a theme, in place of one of the same name.
	with_theme : Declared, Theme -> Declared
	with_theme = |setup, theme| { ..setup, themes: replaced(setup.themes, theme, |old| old.name == theme.name) }

	## Takes away the theme called `name`.
	without_theme : Declared, Str -> Declared
	without_theme = |setup, name| { ..setup, themes: setup.themes.drop_if(|theme| theme.name == name) }

	## Makes the theme called `name` the one clients start with.
	with_default_theme : Declared, Str -> Declared
	with_default_theme = |setup, name| { ..setup, default_theme: name }

	## Makes the key `pubkey`, 64 lowercase hex digits, the owner's.
	with_owner : Declared, Str -> Declared
	with_owner = |setup, pubkey| { ..setup, owner: pubkey }

	## Declares a role, in place of one of the same name.
	with_role : Declared, Role -> Declared
	with_role = |setup, role| { ..setup, roles: replaced(setup.roles, role, |old| old.name == role.name) }

	## Declares a room the relay starts with, in place of one of the same name.
	with_room : Declared, Room -> Declared
	with_room = |setup, room| { ..setup, rooms: replaced(setup.rooms, room, |old| old.name == room.name) }

	## Sets the presets, by name, a new browser's deck holds.
	with_deck : Declared, List(Str) -> Declared
	with_deck = |setup, names| { ..setup, deck: names }

	## `base` with what `changes` declares added over it: its remotes, presets
	## and themes in place of those of the same name, its transformers, and
	## its default preset and theme, its deck and its owner if it names them,
	## and its roles and rooms in place of those of the same name.
	merge : Declared, Declared -> Declared
	merge = |base, changes| {
		with_all = |setup, items, add| items.fold(setup, add)
		merged = with_all(with_all(with_all(with_all(with_all(base, changes.remotes, Setup.with_remote), changes.transformers, Setup.with_transformer), changes.presets, Setup.with_preset), changes.themes, Setup.with_theme), changes.roles, Setup.with_role)
		roomed = with_all(merged, changes.rooms, Setup.with_room)
		owned = if (changes.owner.is_empty()) roomed else Setup.with_owner(roomed, changes.owner)
		preset_set = if (changes.default_preset.is_empty()) owned else Setup.with_default_preset(owned, changes.default_preset)
		theme_set = if (changes.default_theme.is_empty()) preset_set else Setup.with_default_theme(preset_set, changes.default_theme)
		if (changes.deck.is_empty()) theme_set else Setup.with_deck(theme_set, changes.deck)
	}

	## What a daemon's manifest offers of `setup`: its presets and themes.
	offered : Declared -> Offered
	offered = |{ presets, default_preset, themes, default_theme, deck, .. }| { presets, default_preset, themes, default_theme, deck }

	## A manifest's setup, one from before setups declared a deck with none.
	offered_from_json : Str -> Try(Offered, [Invalid])
	offered_from_json = |text| {
		parsed : Try({ setup : { presets : List({ name : Str, snapshot : Unframed }), default_preset : Str, themes : List(Theme), default_theme : Str } }, _)
		parsed = Json.parse(text)
		decked : Try({ setup : { deck : List(Str) } }, _)
		decked = Json.parse(text)
		framing : Try({ setup : { presets : List({ snapshot : { frame : Frame } }) } }, _)
		framing = Json.parse(text)
		frames = framing.map_ok(|saved| saved.setup.presets.map(|preset| preset.snapshot.frame)) ?? []
		parsed.map_ok(|{ setup }| { presets: Setup.framed_presets(setup.presets, frames), default_preset: setup.default_preset, themes: setup.themes, default_theme: setup.default_theme, deck: decked.map_ok(|saved| saved.setup.deck) ?? [] }).map_err(|_| Invalid)
	}

	## The preset a client starts with: the default, or the first if it names
	## none there is.
	starting : Offered -> Try(Preset, [NoPresets])
	starting = |{ presets, default_preset, .. }|
		match presets.find_first(|preset| preset.name == default_preset) {
			Ok(preset) => Ok(preset)
			Err(NotFound) => presets.first().map_err(|_| NoPresets)
		}

	## A setup as JSON, its fields in order, so the same setup is the same text.
	to_json : Declared -> Str
	to_json = |setup| Json.to_str(setup)

	## Reads a setup. One evaluated before snapshots were grids has its
	## presets' columns laid out as a grid (`grid_of`); one from before they hid
	## panes hides none; one from before setups held themes offers none, and
	## its presets keep the theme shown; one from before setups declared a
	## deck declares none; one from before roles, no owner and no roles; one
	## from before rooms, no rooms; one from before rooms were open, closed
	## rooms.
	from_json : Str -> Try(Declared, [Invalid])
	from_json = |text| Setup.declared_from_json(text).map_ok(
		|setup| {
			owning : Try({ owner : Str, roles : List(Role) }, _)
			owning = Json.parse(text)
			roomed : Try({ rooms : List({ name : Str, about : Str, kind : [Channel, Forum, Direct, Announce], private : Bool, open : Try(Bool, [Missing]) }) }, _)
			roomed = Json.parse(text)
			rooms = roomed.map_ok(|saved| saved.rooms.map(|room| { name: room.name, about: room.about, kind: room.kind, private: room.private, open: room.open ?? Bool.False })) ?? []
			match owning {
				Ok({ owner, roles }) => { ..setup, owner, roles, rooms }
				Err(_) => { ..setup, rooms }
			}
		},
	)

	## A setup from before roles, as `from_json` reads it.
	declared_from_json : Str -> Try(Declared, [Invalid])
	declared_from_json = |text| {
		decked : Try({ deck : List(Str) }, _)
		decked = Json.parse(text)
		deck = decked.map_ok(|saved| saved.deck) ?? []
		parsed : Try({ remotes : List(Remote), transformers : List(Str), presets : List({ name : Str, snapshot : Unframed }), default_preset : Str, themes : List(Theme), default_theme : Str }, _)
		parsed = Json.parse(text)
		framing : Try({ presets : List({ snapshot : { frame : Frame } }) }, _)
		framing = Json.parse(text)
		columns : Try({ remotes : List(Remote), transformers : List(Str), presets : List({ name : Str, snapshot : { version : U32, shell : Shell, columns : List(Column), collapsed : List(Slot) } }), default_preset : Str }, _)
		columns = Json.parse(text)
		hiding : Try({ presets : List({ snapshot : { hidden : List(Str) } }) }, _)
		hiding = Json.parse(text)
		themed : Try({ presets : List({ snapshot : { theme : Str } }), themes : List(Theme), default_theme : Str }, _)
		themed = Json.parse(text)
		match (parsed, columns) {
			(Ok({ remotes, transformers, presets, default_preset, themes, default_theme }), _) => Ok({ ..Setup.empty, remotes, transformers, presets: Setup.framed_presets(presets, framing.map_ok(|saved| saved.presets.map(|preset| preset.snapshot.frame)) ?? []), default_preset, themes, default_theme, deck })
			(_, Ok({ remotes, transformers, presets, default_preset })) => {
				hidden = |index| hiding.map_ok(|saved| saved.presets.get(index).map_ok(|preset| preset.snapshot.hidden) ?? []) ?? []
				theme = |index| themed.map_ok(|saved| saved.presets.get(index).map_ok(|preset| preset.snapshot.theme) ?? "") ?? ""
				laid_out = presets.map_with_index(|{ name, snapshot }, index| { name, snapshot: { version: snapshot.version, shell: snapshot.shell, frame: Setup.frame_of(snapshot.shell), grid: Setup.grid_of(snapshot.columns), collapsed: snapshot.collapsed, hidden: hidden(index), theme: theme(index) } })
				Ok({ ..Setup.empty, remotes, transformers, default_preset, presets: laid_out, themes: themed.map_ok(|saved| saved.themes) ?? [], default_theme: themed.map_ok(|saved| saved.default_theme) ?? "", deck })
			}
			_ => Err(Invalid)
		}
	}
}

## The least common multiple's partner: the greatest common divisor.
divisor : U64, U64 -> U64
divisor = |a, b| if (b == 0) a else divisor(b, a % b)

## `items` with `item` in place of the first that `same` picks, or after them.
replaced : List(a), a, (a -> Bool) -> List(a)
replaced = |items, item, same|
	match items.find_first_index(same) {
		Ok(index) => items.map_with_index(|old, at| if (at == index) item else old)
		Err(NotFound) => items.append(item)
	}

layout : Str -> Setup.Snapshot
layout = |widget| { version: Setup.snapshot_version, shell: Tiling, frame: Tiles, grid: Grid.single({ id: "column-1", left: 0, top: 0, right: 1, bottom: 1, active: "pane-1", panes: [{ id: "pane-1", widget, pinned: "", options: [] }] }), collapsed: [], hidden: [], theme: "" }

chat : Setup.Preset
chat = { name: "Chat", snapshot: layout("chat") }

echo : Setup.Remote
echo = { name: "echo", url: "http://127.0.0.1:8096" }

dusk : Setup.Theme
dusk = {
	name: "Dusk",
	scheme: Dark,
	accent: "#e8c872",
	accent_to: "#e8c872",
	text: "#ece8dc",
	muted: "#a8a08a",
	edge: 22,
	edge_active: 70,
	glass: { tint: "#0c0c0c", opacity: 46, blur: 5 },
	background: Flat("#111111"),
	gap: 10,
	radius: 10,
	fonts: { ui: "system-ui", mono: "monospace", display: "serif" },
	motion: Normal,
}

expect Setup.with_remote(Setup.with_remote(Setup.empty, echo), { ..echo, url: "https://echo.example" }).remotes == [{ ..echo, url: "https://echo.example" }]
expect Setup.without_remote(Setup.with_remote(Setup.empty, echo), "echo").remotes == []
expect Setup.without_transformer(Setup.with_transformer(Setup.with_transformer(Setup.with_transformer(Setup.empty, "attention"), "needs-you"), "attention"), "attention").transformers == ["needs-you"]
expect {
	inbox = { name: "Inbox", snapshot: layout("inbox") }
	presets = Setup.with_preset(Setup.with_preset(Setup.with_preset(Setup.empty, chat), inbox), { ..chat, snapshot: layout("sessions") }).presets
	presets == [{ ..chat, snapshot: layout("sessions") }, inbox] and Setup.without_preset({ ..Setup.empty, presets }, "Chat").presets == [inbox]
}
expect {
	light = { ..dusk, name: "Light", scheme: Light }
	themes = Setup.with_theme(Setup.with_theme(Setup.with_theme(Setup.empty, dusk), light), { ..dusk, radius: 4 }).themes
	themes == [{ ..dusk, radius: 4 }, light] and Setup.without_theme({ ..Setup.empty, themes }, "Dusk").themes == [light]
}
expect {
	base = { ..Setup.empty, remotes: [echo], transformers: ["attention"], presets: [chat], default_preset: "Chat", themes: [dusk], default_theme: "Dusk" }
	team = { ..Setup.empty, remotes: [{ name: "team", url: "https://liton.example" }], transformers: ["needs-you"], presets: [{ name: "Inbox", snapshot: layout("inbox") }], themes: [{ ..dusk, name: "Team" }] }
	merged = Setup.merge(base, team)
	changed = Setup.merge(base, { ..team, default_preset: "Inbox", default_theme: "Team", deck: ["Inbox", "Chat"] })
	merged.deck == [] and changed.deck == ["Inbox", "Chat"] and merged.remotes.map(|remote| remote.name) == ["echo", "team"] and merged.transformers == ["attention", "needs-you"] and merged.presets.map(|preset| preset.name) == ["Chat", "Inbox"] and merged.themes.map(|theme| theme.name) == ["Dusk", "Team"] and merged.default_preset == "Chat" and merged.default_theme == "Dusk" and changed.default_preset == "Inbox" and changed.default_theme == "Team"
}
expect {
	offered = |presets, default_preset| Setup.offered({ ..Setup.empty, presets, default_preset })
	Setup.starting(offered([chat], "Chat")) == Ok(chat) and Setup.starting(offered([chat], "Gone")) == Ok(chat) and Setup.starting(offered([], "Chat")) == Err(NoPresets)
}

# Fields in order, so a setup is always the same text, and it reads back.
expect {
	setup = { remotes: [echo], transformers: ["attention"], presets: [chat], default_preset: "Chat", themes: [dusk], default_theme: "Dusk", deck: ["Chat"], owner: "", roles: [], rooms: [] }
	text = Setup.to_json(setup)
	text == "{\"deck\":[\"Chat\"],\"default_preset\":\"Chat\",\"default_theme\":\"Dusk\",\"owner\":\"\",\"presets\":[{\"name\":\"Chat\",\"snapshot\":{\"collapsed\":[],\"frame\":\"Tiles\",\"grid\":{\"columns\":[1],\"rows\":[1],\"tiles\":[{\"active\":\"pane-1\",\"bottom\":1,\"id\":\"column-1\",\"left\":0,\"panes\":[{\"id\":\"pane-1\",\"options\":[],\"pinned\":\"\",\"widget\":\"chat\"}],\"right\":1,\"top\":0}]},\"hidden\":[],\"shell\":\"Tiling\",\"theme\":\"\",\"version\":9}}],\"remotes\":[{\"name\":\"echo\",\"url\":\"http://127.0.0.1:8096\"}],\"roles\":[],\"rooms\":[],\"themes\":[{\"accent\":\"#e8c872\",\"accent_to\":\"#e8c872\",\"background\":{\"Flat\":\"#111111\"},\"edge\":22,\"edge_active\":70,\"fonts\":{\"display\":\"serif\",\"mono\":\"monospace\",\"ui\":\"system-ui\"},\"gap\":10,\"glass\":{\"blur\":5,\"opacity\":46,\"tint\":\"#0c0c0c\"},\"motion\":\"Normal\",\"muted\":\"#a8a08a\",\"name\":\"Dusk\",\"radius\":10,\"scheme\":\"Dark\",\"text\":\"#ece8dc\"}],\"transformers\":[\"attention\"]}" and Setup.from_json(text) == Ok(setup)
}

# A setup evaluated before snapshots were grids has its columns as a grid,
# and one from before they hid panes hides none.
expect {
	setup = { remotes: [echo], transformers: ["attention"], presets: [{ ..chat, snapshot: { ..chat.snapshot, version: 5 } }], default_preset: "Chat", themes: [dusk], default_theme: "Dusk", deck: [], owner: "", roles: [], rooms: [] }
	text = "{\"default_preset\":\"Chat\",\"default_theme\":\"Dusk\",\"presets\":[{\"name\":\"Chat\",\"snapshot\":{\"collapsed\":[],\"columns\":[{\"active\":\"pane-1\",\"id\":\"column-1\",\"panes\":[{\"id\":\"pane-1\",\"options\":[],\"pinned\":\"\",\"widget\":\"chat\"}],\"size\":1,\"tabbed\":false}],\"shell\":\"Tiling\",\"theme\":\"\",\"version\":5}}],\"remotes\":[{\"name\":\"echo\",\"url\":\"http://127.0.0.1:8096\"}],\"themes\":[{\"accent\":\"#e8c872\",\"accent_to\":\"#e8c872\",\"background\":{\"Flat\":\"#111111\"},\"edge\":22,\"edge_active\":70,\"fonts\":{\"display\":\"serif\",\"mono\":\"monospace\",\"ui\":\"system-ui\"},\"gap\":10,\"glass\":{\"blur\":5,\"opacity\":46,\"tint\":\"#0c0c0c\"},\"motion\":\"Normal\",\"muted\":\"#a8a08a\",\"name\":\"Dusk\",\"radius\":10,\"scheme\":\"Dark\",\"text\":\"#ece8dc\"}],\"transformers\":[\"attention\"]}"
	Setup.from_json(text) == Ok(setup)
}

# A setup evaluated before setups declared a deck declares none, and a
# manifest's setup from then offers none.
expect {
	text = "{\"default_preset\":\"Chat\",\"default_theme\":\"\",\"presets\":[],\"remotes\":[],\"themes\":[],\"transformers\":[]}"
	Setup.from_json(text) == Ok({ ..Setup.empty, default_preset: "Chat" }) and Setup.offered_from_json("{\"setup\":${text}}") == Ok({ ..Setup.offered(Setup.empty), default_preset: "Chat" }) and Setup.offered_from_json("{\"setup\":{\"deck\":[\"Chat\"],${text.drop_prefix("{")}}") == Ok({ ..Setup.offered(Setup.empty), default_preset: "Chat", deck: ["Chat"] })
}

# A setup evaluated before setups held themes offers none.
expect {
	text = "{\"default_preset\":\"Chat\",\"presets\":[{\"name\":\"Chat\",\"snapshot\":{\"collapsed\":[],\"columns\":[{\"active\":\"pane-1\",\"id\":\"column-1\",\"panes\":[{\"id\":\"pane-1\",\"options\":[],\"pinned\":\"\",\"widget\":\"chat\"}],\"size\":1,\"tabbed\":false}],\"shell\":\"Tiling\",\"version\":4}}],\"remotes\":[],\"transformers\":[]}"
	Setup.from_json(text) == Ok({ ..Setup.empty, presets: [{ ..chat, snapshot: { ..chat.snapshot, version: 4 } }], default_preset: "Chat" })
}
expect Setup.from_json("{\"remotes\":[]}") == Err(Invalid)

# Columns side by side are a grid's tiles, a column stacking panes a tile
# for each, over rows cut where any column's panes meet.
expect {
	pane = |id| { id, widget: "chat", pinned: "", options: [] }
	grid = Setup.grid_of([{ id: "c1", size: 1, tabbed: Bool.False, active: "a", panes: [pane("a"), pane("b")] }, { id: "c2", size: 2, tabbed: Bool.True, active: "d", panes: [pane("c"), pane("d")] }, { id: "c3", size: 1, tabbed: Bool.False, active: "e", panes: [pane("e"), pane("f"), pane("g")] }])
	grid.columns == [1, 2, 1] and grid.rows == [2, 1, 1, 2] and grid.tiles.map(|tile| (tile.id, tile.active, tile.left, tile.top, tile.right, tile.bottom)) == [("c1", "a", 0, 0, 1, 2), ("c1-b", "b", 0, 2, 1, 4), ("c2", "d", 1, 0, 2, 4), ("c3", "e", 2, 0, 3, 1), ("c3-f", "f", 2, 1, 3, 3), ("c3-g", "g", 2, 3, 3, 4)]
}

# Roles, rooms and the owner merge, the later in place of the earlier, and read back.
expect {
	staff = { name: "staff", capabilities: ["rooms.v1"], presets: ["Chat"], locked: Bool.True }
	desk = { name: "Front desk", about: "", kind: Forum, private: Bool.True, open: Bool.True }
	owner = Str.repeat("a", 64)
	merged = Setup.merge(Setup.with_room(Setup.with_role(Setup.with_owner(Setup.empty, owner), { ..staff, locked: Bool.False }), { ..desk, kind: Channel }), Setup.with_room(Setup.with_role(Setup.empty, staff), desk))
	merged.owner == owner and merged.roles == [staff] and merged.rooms == [desk] and Setup.from_json(Setup.to_json(merged)) == Ok(merged)
}

# A setup's rooms from before they were open read as closed.
expect Setup.from_json(Setup.to_json(Setup.empty).replace_first("\"rooms\":[]", "\"rooms\":[{\"name\":\"Desk\",\"about\":\"\",\"kind\":\"Channel\",\"private\":false}]")).map_ok(|setup| setup.rooms) == Ok([{ name: "Desk", about: "", kind: Channel, private: Bool.False, open: Bool.False }])

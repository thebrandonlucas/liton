## The UI's state and every change to it, apart from the view so they can be
## tested without a browser.
import cap.Attention
import cap.Capability
import cap.Chat
import cap.Context
import cap.Manifest
import cap.Protocol
import cap.WorkspaceGit
import cap.Workspaces
import setup.Default
import setup.Setup
import Widgets

Model := [].{

	## The layout's parts, as setups' presets hold them (setup/Setup.roc).
	Pane : Setup.Pane

	Column : Setup.Column

	## A pane and column as snapshots before version 4 saved them, without options.
	OldPane : { id : Str, widget : Str, pinned : Str }

	OldColumn : { id : Str, size : U32, tabbed : Bool, active : Str, panes : List(OldPane) }

	Shell : Setup.Shell

	## `collapsed` are the Workbench drawers hidden.
	Layout : { shell : Shell, columns : List(Column), collapsed : List(Slot) }

	Slot : Setup.Slot

	## The part of the model a snapshot saves: deterministic JSON others can load.
	Snapshot : Setup.Snapshot

	Timeline : { session_id : Str, entries : List(Chat.Entry) }

	## A message or permission answer sent, until its session's timeline shows
	## it after the event numbered `after`. `failed` says why the daemon did not
	## take it, or is "" while it waits.
	Sent : { serial : U64, session_id : Str, request : Chat.Request, after : U64, failed : Str }

	State : {
		capabilities : List(Capability.Id),
		providers : List(Manifest.Provider),
		transformers : List(Manifest.Transformer),
		sessions : List(Chat.Session),
		timelines : List(Timeline),

		## What panes that follow the focus show, `Session("")` for nothing.
		focus : Context.Id,

		## The projects and workspaces the daemon lists.
		workspaces : Workspaces.Listed,
		shell : Shell,
		columns : List(Column),
		collapsed : List(Slot),

		## The column a narrow screen shows.
		active_column : Str,

		## The panel a narrow Workbench last scrolled to, by the reference
		## focusing it; `serial` counts each scroll.
		jump : { serial : U64, panel : Str },

		## Counts on the numbers ending pane and column ids, so each is new.
		next_id : U64,
		drafts : List({ pane : Str, text : Str }),

		## How many times each chat pane's composer was cleared by sending its
		## draft, which builds it anew (see `Liton.chat`).
		cleared : List({ pane : Str, count : U64 }),
		outbox : { serial : U64, request : Chat.Request },
		sent : List(Sent),
		attention : List(Attention.Item),

		## A settle or snooze sent, shown until the daemon's items show it, or
		## until the poll numbered `accepted` answers, the first sent after the
		## daemon accepted it (0 while it waits).
		setting_aside : List({ serial : U64, session_id : Str, set_aside : [No, Settled, Snoozed], accepted : U64 }),
		attention_outbox : { serial : U64, request : Attention.Request },

		## The last poll sent, while `polling`, and whether another is to
		## follow it at once; the cursor of each topic polled.
		poll : Poll,
		polling : Bool,
		poll_again : Bool,
		cursors : List({ capability : Str, topic : Str, cursor : Str }),
		notice : Str,
		show_settings : Bool,
		snapshot_text : Str,

		## The presets settings offer: the daemon's setup's, or liton's own until
		## it offers some. `kept_layout` is whether the layout shown is the one
		## the browser kept, which a setup's starting preset doesn't replace.
		presets : List(Setup.Preset),
		kept_layout : Bool,

		## What polls answered of each session's git: its workspace, status and
		## commits, the changes of each scope asked for, and the hunks of each
		## file shown.
		git : List(Git),
		git_changes : List({ context : Context.Id, changes : WorkspaceGit.Changes }),
		git_hunks : List({ context : Context.Id, scope : WorkspaceGit.Scope, path : Str, hunks : List(WorkspaceGit.Hunk) }),

		## What each Changes pane shows.
		git_panes : List(GitPane),

		## The themes settings offer and the one a snapshot naming none shows:
		## the daemon's setup's, or liton's own until it offers some. `theme`
		## is the one picked, or "" for the default. `glass` is whether tiles
		## blur what is behind them, which this browser keeps apart from the
		## snapshot.
		themes : List(Setup.Theme),
		default_theme : Str,
		theme : Str,
		glass : Bool,

		## The pane last clicked or focused in, which the bright edge marks.
		focused_pane : Str,

		## The pane whose ⋯ menu is open, or "".
		menu : Str,

		## The code block last copied, by its key, and the copy asked of the
		## clipboard; `copied` is "" again if the clipboard refused it.
		copied : Str,
		clipboard : { serial : U64, key : Str, text : Str },

		## How many times each chat pane jumped to its latest entry.
		jumps : List({ pane : Str, count : U64 }),

		## The form a Workspaces pane opened, to start an agent or create a
		## workspace, and what is typed in it.
		form : Form,

		## Agents started and workspaces created, shown starting until a listing
		## has them, and the call asking for the last, its capability as `key`
		## and its JSON as `text`: the shape of `clipboard`, which spares the
		## module another instance of the effect that sends it; the kinds of
		## agent each provider starts.
		creating : List(Creating),
		create_outbox : { serial : U64, key : Str, text : Str },
		agents : List(Chat.Agent),
	}

	## A Workspaces pane's form: an agent to start in the workspace `place`,
	## or a workspace to create of the project `place`. `failed` says why the
	## daemon didn't, "" until it refuses.
	Form : { pane : Str, kind : [Closed, Agent, Workspace], place : Str, agent : Str, model : Str, prompt : Str, worktree : Bool, branch : Str, failed : Str }

	## An agent started or a workspace created, from `form`, until a listing
	## has it; `id` is "" until the daemon answers with it.
	Creating : { serial : U64, form : Form, title : Str, id : Str }

	closed_form : Form
	closed_form = { pane: "", kind: Closed, place: "", agent: "", model: "", prompt: "", worktree: Bool.True, branch: "", failed: "" }

	## A poll of `subjects`, numbered by `serial`, as `topics` after the
	## cursors the UI had.
	Poll : { serial : U64, subjects : List(Protocol.Subject), topics : List(Protocol.Wanted) }

	Git : { context : Context.Id, workspace : [Known(WorkspaceGit.Workspace), Unknown], status : [Status(WorkspaceGit.Status), NoStatus], commits : List(WorkspaceGit.Commit) }

	GitPane : { pane : Str, scope : WorkspaceGit.Scope, file : [Selected(Str), NoFile] }

	## The layout of a preset or snapshot.
	layout_of : Snapshot -> Layout
	layout_of = |{ shell, columns, collapsed, .. }| { shell, columns, collapsed }

	## liton's own presets (setup/Default.roc): Developer, the default,
	## Inbox and Tiling.
	developer : Layout
	developer = Model.layout_of(Default.developer.snapshot)

	inbox : Layout
	inbox = Model.layout_of(Default.inbox.snapshot)

	tiling : Layout
	tiling = Model.layout_of(Default.tiling.snapshot)

	initial : Str -> State
	initial = |saved| {
		restored = Model.restore(saved)
		Model.layout(
			{
				capabilities: [],
				providers: [],
				transformers: [],
				sessions: [],
				timelines: [],
				focus: Session(""),
				workspaces: { projects: [], workspaces: [] },
				shell: Tiling,
				columns: [],
				collapsed: [],
				active_column: "",
				jump: { serial: 0, panel: "" },
				next_id: 1,
				drafts: [],
				cleared: [],
				outbox: { serial: 0, request: ListSessions },
				sent: [],
				attention: [],
				setting_aside: [],
				attention_outbox: { serial: 0, request: ListItems },
				poll: { serial: 0, subjects: [], topics: [] },
				polling: Bool.False,
				poll_again: Bool.False,
				cursors: [],
				notice: "",
				show_settings: Bool.False,
				snapshot_text: "",
				presets: Default.setup.presets,
				kept_layout: restored.is_ok(),
				git: [],
				git_changes: [],
				git_hunks: [],
				git_panes: [],
				themes: Default.setup.themes,
				default_theme: Default.setup.default_theme,
				theme: restored.map_ok(|snapshot| snapshot.theme) ?? "",
				glass: Bool.True,
				focused_pane: "",
				menu: "",
				copied: "",
				clipboard: { serial: 0, key: "", text: "" },
				jumps: [],
				form: Model.closed_form,
				creating: [],
				create_outbox: { serial: 0, key: "", text: "" },
				agents: [],
			},
			restored.map_ok(Model.layout_of) ?? Model.developer,
		)
	}

	## Shows a layout, counting ids on from the numbers ending theirs. A
	## Workbench shows its main area first.
	layout : State, Layout -> State
	layout = |state, { shell, columns, collapsed }| {
		ids = columns.join_map(|column| column.panes.map(|pane| pane.id).append(column.id))
		next_id = ids.fold(1, |next, id| U64.max(next, (U64.from_str(id.split_last("-").map_ok(|parts| parts.after) ?? "") ?? 0) + 1))
		shown = if (shell == Workbench) columns.get(1) else columns.first()
		jump = { serial: state.jump.serial + 1, panel: if (shell == Workbench) Model.panel_ref(Main) else "" }
		{ ..state, shell, columns, next_id, collapsed, jump, active_column: shown.map_ok(|column| column.id) ?? "" }
	}

	snapshot : State -> Snapshot
	snapshot = |state| { version: Setup.snapshot_version, shell: state.shell, columns: state.columns, collapsed: state.collapsed, theme: state.theme }

	## A layout as a snapshot showing the setup's default theme.
	snapshot_of : Layout -> Snapshot
	snapshot_of = |{ shell, columns, collapsed }| { version: Setup.snapshot_version, shell, columns, collapsed, theme: "" }

	## The snapshot settings show, of the layout as it is now.
	with_snapshot_text : State -> State
	with_snapshot_text = |state| { ..state, snapshot_text: Json.to_str(Model.snapshot(state)) }

	## Reads a snapshot. Before version 5, it shows the setup's default theme;
	## before version 4, panes have their options' defaults and the drawers
	## show. A version 1 or 2 one loads in Tiling, a version 1 one with a
	## column for each pane, unless it holds just the old default's widgets:
	## then it loads the Developer preset.
	restore : Str -> Try(Snapshot, [Invalid])
	restore = |text| {
		# Since version 4 a snapshot is laid out alike; version 5 names its theme.
		laid : Try({ version : U32, shell : Shell, columns : List(Column), collapsed : List(Slot) }, _)
		laid = Json.parse(text)
		themed : Try({ theme : Str }, _)
		themed = Json.parse(text)
		third : Try({ version : U32, shell : Shell, columns : List(OldColumn) }, _)
		third = Json.parse(text)
		second : Try({ version : U32, columns : List(OldColumn) }, _)
		second = Json.parse(text)
		first : Try({ version : U32, panes : List(OldPane) }, _)
		first = Json.parse(text)
		laid_out = |shell, columns| shell == Tiling or columns.len() == 3
		match (laid, third, second, first) {
			(Ok({ version, shell, columns, collapsed }), _, _, _) if (version == 4 or version == 5) and laid_out(shell, columns) => Ok({ ..Model.snapshot_of({ shell, columns, collapsed }), theme: if (version == 5) themed.map_ok(|saved| saved.theme) ?? "" else "" })
			(_, Ok({ version: 3, shell, columns }), _, _) if laid_out(shell, columns) => Ok(Model.snapshot_of({ shell, columns: Model.with_options(columns), collapsed: [] }))
			(_, _, Ok({ version: 2, columns }), _) => Ok(Model.snapshot_of(Model.migrated(Model.with_options(columns))))
			(_, _, _, Ok({ version: 1, panes })) => Ok(Model.snapshot_of(Model.migrated(Model.with_options(panes.map_with_index(|pane, index| { id: "column-${(index + 1).to_str()}", size: 1, tabbed: Bool.False, active: pane.id, panes: [pane] })))))
			_ => Err(Invalid)
		}
	}

	with_options : List(OldColumn) -> List(Column)
	with_options = |columns| columns.map(|{ id, size, tabbed, active, panes }| { id, size, tabbed, active, panes: panes.map(|pane| { id: pane.id, widget: pane.widget, pinned: pane.pinned, options: [] }) })

	migrated : List(Column) -> Layout
	migrated = |columns|
		if (columns.map(|column| column.panes.map(|pane| pane.widget)) == [["sessions"], ["chat"], ["capabilities"]]) Model.developer else { shell: Tiling, columns, collapsed: [] }

	load_snapshot : State -> State
	load_snapshot = |state|
		match Model.restore(state.snapshot_text) {
			Ok(loaded) => { ..Model.layout(state, Model.layout_of(loaded)), theme: loaded.theme, notice: "Loaded a layout of ${loaded.columns.len().to_str()} columns." }
			Err(Invalid) => { ..state, notice: "That is not a liton snapshot." }
		}

	advertise : State, Manifest.Offered -> State
	advertise = |state, offered| { ..state, providers: offered.providers, transformers: offered.transformers, capabilities: Manifest.offered(offered) }

	## Offers the presets and themes the daemon's setup offers, if any, and
	## shows the preset it starts with, unless the layout is the one the
	## browser kept.
	set_up : State, Setup.Offered -> State
	set_up = |state0, offered| {
		state = if (offered.themes.is_empty()) state0 else { ..state0, themes: offered.themes, default_theme: offered.default_theme }
		match Setup.starting(offered) {
			Err(NoPresets) => state
			Ok(_) if state.kept_layout => { ..state, presets: offered.presets }
			Ok(starting) => { ..Model.use_preset({ ..state, presets: offered.presets }, starting.name), kept_layout: Bool.True }
		}
	}

	## Shows a preset's layout, and its theme if it names one.
	use_preset : State, Str -> State
	use_preset = |state, name|
		match state.presets.find_first(|preset| preset.name == name) {
			Ok(preset) => { ..Model.layout(state, Model.layout_of(preset.snapshot)), theme: if (preset.snapshot.theme.is_empty()) state.theme else preset.snapshot.theme }
			Err(NotFound) => state
		}

	## The theme shown: the one picked, else the setup's default, else the
	## first offered.
	theme_shown : State -> Setup.Theme
	theme_shown = |state| {
		named = |name| state.themes.find_first(|theme| theme.name == name)
		match (named(state.theme), named(state.default_theme)) {
			(Ok(picked), _) => picked
			(_, Ok(default)) => default
			_ => state.themes.first() ?? Default.pastoral
		}
	}

	use_theme : State, Str -> State
	use_theme = |state, name| { ..state, theme: name }

	## The preset the layout is a workspace of: the first whose shell holds
	## the same widgets in the same columns, however they are sized, set or
	## folded.
	workspace_shown : State -> Str
	workspace_shown = |state| {
		shape = |shell, columns| (shell, columns.map(|column| column.panes.map(|pane| pane.widget)))
		state.presets.find_first(|preset| shape(preset.snapshot.shell, preset.snapshot.columns) == shape(state.shell, state.columns)).map_ok(|preset| preset.name) ?? ""
	}

	## A key pressed outside a text field: 1 to 9, with or without Alt (or
	## Option, which types ¡ to ª on a Mac), shows that workspace; Escape
	## closes settings.
	pressed : State, Str -> State
	pressed = |state, key| {
		numbered = ["1", "2", "3", "4", "5", "6", "7", "8", "9"].find_first_index(|digit| digit == key)
		option = ["¡", "™", "£", "¢", "∞", "§", "¶", "•", "ª"].find_first_index(|glyph| glyph == key)
		match (numbered, option, state.presets.get(numbered ?? (option ?? 9))) {
			(_, _, Ok(preset)) => Model.with_snapshot_text(Model.use_preset(state, preset.name))
			_ if key == "Escape" => { ..state, show_settings: Bool.False, menu: "" }
			_ => state
		}
	}

	## Marks the pane clicked or focused in, and shows its column on a narrow
	## screen. Another pane's menu closes.
	focus_pane : State, { pane : Str, column : Str } -> State
	focus_pane = |state, { pane, column }| { ..state, focused_pane: pane, active_column: column, menu: if (state.menu == pane) pane else "" }

	toggle_menu : State, Str -> State
	toggle_menu = |state, pane_id| { ..state, menu: if (state.menu == pane_id) "" else pane_id }

	## Copies a code block, shown as copied at once.
	copy : State, { key : Str, text : Str } -> State
	copy = |state, { key, text }| { ..state, copied: key, clipboard: { serial: state.clipboard.serial + 1, key, text } }

	## Takes the clipboard's answer: refused, the block isn't copied after all.
	copy_answered : State, U64, Bool -> State
	copy_answered = |state, serial, copied| if (copied or serial != state.clipboard.serial) state else { ..state, copied: "", notice: "The browser didn't let liton copy that." }

	jumps_of : State, Str -> U64
	jumps_of = |state, pane_id| state.jumps.find_first(|jumped| jumped.pane == pane_id).map_ok(|jumped| jumped.count) ?? 0

	## Scrolls a chat pane's timeline to its latest entry.
	jump_to_latest : State, Str -> State
	jump_to_latest = |state, pane_id| { ..state, jumps: state.jumps.drop_if(|jumped| jumped.pane == pane_id).append({ pane: pane_id, count: Model.jumps_of(state, pane_id) + 1 }) }

	## How many sessions are running.
	running : State -> U64
	running = |state| state.sessions.keep_if(|session| session.status == Running).len()

	## Whether the layout is the preset's, as it was loaded.
	preset_shown : State, Str -> Bool
	preset_shown = |state, name| state.presets.any(|preset| preset.name == name and Model.layout_of(preset.snapshot) == { shell: state.shell, columns: state.columns, collapsed: state.collapsed })

	## Every pane, column by column.
	panes : State -> List(Pane)
	panes = |state| state.columns.join_map(|column| column.panes)

	## A new pane of `widget`: a tab in a Workbench's main area, or a column of
	## its own at the end in Tiling.
	add_pane : State, Str -> State
	add_pane = |state, widget| {
		pane = { id: "pane-${state.next_id.to_str()}", widget, pinned: "", options: [] }
		column = { id: "column-${(state.next_id + 1).to_str()}", size: 1, tabbed: Bool.False, active: pane.id, panes: [pane] }
		if (state.shell == Workbench)
			{ ..state, columns: state.columns.map_with_index(|main, index| if (index == 1) { ..main, active: pane.id, panes: main.panes.append(pane) } else main), next_id: state.next_id + 1 }
		else
			{ ..state, columns: state.columns.append(column), active_column: column.id, next_id: state.next_id + 2 }
	}

	slot_of : State, Str -> Slot
	slot_of = |state, column_id|
		match (state.shell, state.columns.find_first_index(|column| column.id == column_id)) {
			(Workbench, Ok(0)) => Left
			(Workbench, Ok(1)) => Main
			(Workbench, Ok(2)) => Right
			_ => Free
		}

	slot_name : Slot -> Str
	slot_name = |slot|
		match slot {
			Left => "left"
			Main => "main"
			Right => "right"
			Free => "free"
		}

	slot_named : Str -> Slot
	slot_named = |name| [Left, Main, Right].find_first(|slot| Model.slot_name(slot) == name) ?? Free

	## Moves a pane to the end of a Workbench slot, as its active tab, and
	## shows the slot's drawer.
	move_to_slot : State, Str, Slot -> State
	move_to_slot = |state, id, slot| {
		moved = Model.pane(state, id)
		to = state.columns.get([Left, Main, Right].find_first_index(|candidate| candidate == slot) ?? 3).map_ok(|column| column.id) ?? ""
		left_behind = state.columns.map(|column| { ..column, panes: column.panes.drop_if(|pane| pane.id == id) })
		columns = left_behind.map(|column| if (column.id == to) { ..column, active: id, panes: column.panes.append(moved) } else column)
		if (to.is_empty()) state else Model.drop_empty_columns({ ..state, columns, collapsed: state.collapsed.drop_if(|hidden| hidden == slot) })
	}

	## The value of a pane's option `key`, or its widget's default.
	option : Pane, Str -> Str
	option = |shown, key| Widgets.value(Widgets.find(shown.widget), shown.options, key)

	set_option : State, Str, Str, Str -> State
	set_option = |state, id, key, value| {
		set = |pane| if (pane.id == id) { ..pane, options: pane.options.drop_if(|old| old.key == key).append({ key, value }) } else pane
		{ ..state, columns: state.columns.map(|column| { ..column, panes: column.panes.map(set) }) }
	}

	## The focus reference of a Workbench slot's panel, which focusing scrolls
	## into view.
	panel_ref : Slot -> Str
	panel_ref = |slot| if (slot == Free) "" else "panel-${Model.slot_name(slot)}"

	## Shows a column on a narrow screen, scrolling a Workbench to its panel.
	show_column : State, Str -> State
	show_column = |state, column_id| {
		panel = Model.panel_ref(Model.slot_of(state, column_id))
		{ ..state, active_column: column_id, jump: if (panel.is_empty()) state.jump else { serial: state.jump.serial + 1, panel } }
	}

	toggle_drawer : State, Slot -> State
	toggle_drawer = |state, drawer| { ..state, collapsed: if (state.collapsed.contains(drawer)) state.collapsed.drop_if(|slot| slot == drawer) else state.collapsed.append(drawer) }

	close_pane : State, Str -> State
	close_pane = |state, id| Model.drop_empty_columns({ ..state, columns: state.columns.map(|column| { ..column, panes: column.panes.drop_if(|pane| pane.id == id) }) })

	## Drops columns left without panes, apart from a Workbench's slots, and
	## points a tab group or the narrow screen that showed what is gone at what
	## is left.
	drop_empty_columns : State -> State
	drop_empty_columns = |state| {
		columns =
			state.columns
				.drop_if(|column| column.panes.is_empty() and state.shell == Tiling)
				.map(|column| if (column.panes.any(|pane| pane.id == column.active)) column else { ..column, active: column.panes.first().map_ok(|pane| pane.id) ?? "" })
		active_column = if (columns.any(|column| column.id == state.active_column)) state.active_column else columns.first().map_ok(|column| column.id) ?? ""
		{ ..state, columns, active_column }
	}

	## Moves a pane into the next column over. Past the edge it gets a column of
	## its own, unless it is already alone there.
	move_pane : State, Str, [Left, Right] -> State
	move_pane = |state, id, direction|
		match state.columns.find_first_index(|column| column.panes.any(|pane| pane.id == id)) {
			Err(NotFound) => state
			Ok(from) => {
				moved = Model.pane(state, id)
				left_behind = state.columns.map(|column| { ..column, panes: column.panes.drop_if(|pane| pane.id == id) })
				at_edge = if (direction == Left) from == 0 else from + 1 == state.columns.len()
				alone = (state.columns.get(from).map_ok(|column| column.panes.len()) ?? 0) == 1
				if (at_edge and alone)
					state
				else if at_edge {
					column = { id: "column-${state.next_id.to_str()}", size: 1, tabbed: Bool.False, active: id, panes: [moved] }
					columns = if (direction == Left) left_behind.prepend(column) else left_behind.append(column)
					Model.drop_empty_columns({ ..state, columns, active_column: column.id, next_id: state.next_id + 1 })
				} else {
					to = if (direction == Left) from - 1 else from + 1
					columns = left_behind.map_with_index(|column, index| if (index == to) { ..column, active: id, panes: column.panes.append(moved) } else column)
					Model.drop_empty_columns({ ..state, columns, active_column: columns.get(to).map_ok(|column| column.id) ?? state.active_column })
				}
			}
		}

	change_column : State, Str, (Column -> Column) -> State
	change_column = |state, column_id, change| { ..state, columns: state.columns.map(|column| if (column.id == column_id) change(column) else column) }

	toggle_tabs : State, Str -> State
	toggle_tabs = |state, column_id| Model.change_column(state, column_id, |column| { ..column, tabbed: !column.tabbed })

	resize : State, Str, [Narrower, Wider] -> State
	resize = |state, column_id, change| Model.change_column(state, column_id, |column| { ..column, size: if (change == Wider) column.size + 1 else if (column.size > 1) column.size - 1 else 1 })

	## Shows a pane in its tab group.
	activate_tab : State, Str -> State
	activate_tab = |state, id| { ..state, columns: state.columns.map(|column| if (column.panes.any(|pane| pane.id == id)) { ..column, active: id } else column) }

	## Pins a following pane to the focused context, or lets a pinned one follow.
	toggle_pin : State, Str -> State
	toggle_pin = |state, id| {
		pin = |pane| if (pane.id != id) pane else if (pane.pinned.is_empty()) { ..pane, pinned: Context.to_str(state.focus) } else { ..pane, pinned: "" }
		{ ..state, columns: state.columns.map(|column| { ..column, panes: column.panes.map(pin) }) }
	}

	pane : State, Str -> Pane
	pane = |state, id| Model.panes(state).find_first(|candidate| candidate.id == id) ?? { id, widget: "", pinned: "", options: [] }

	## The context a pane shows: the one it is pinned to, as `Context.to_str`
	## names it, or else the focus.
	context_of : State, Pane -> Context.Id
	context_of = |state, shown| if (shown.pinned.is_empty()) state.focus else Context.from_str(shown.pinned) ?? state.focus

	## The session a pane shows: its context's, or its workspace's that needs
	## you most (see `Attention.ranks`), "" for none.
	session_of : State, Pane -> Str
	session_of = |state, shown|
		match Model.context_of(state, shown) {
			Session(session_id) => session_id
			Workspace(workspace_id) => {
				placed = Model.workspace_sessions(state, workspace_id).map(|session| (session.id, Attention.item(session, []).state))
				Attention.ranks.keep_oks(|rank| placed.find_first(|(_, state_of)| state_of == rank)).first().map_ok(|(session_id, _)| session_id) ?? ""
			}
		}

	## The sessions that work in a workspace, as they say or its listing does.
	workspace_sessions : State, Str -> List(Chat.Session)
	workspace_sessions = |state, workspace_id| {
		listed = state.workspaces.workspaces.find_first(|shown| shown.id == workspace_id).map_ok(|shown| shown.session_ids) ?? []
		state.sessions.keep_if(|session| listed.contains(session.id) or (session.workspace.map_ok(|placed| placed.id == Ok(workspace_id)) ?? Bool.False))
	}

	## What a pane's context is called: its session's title, or its
	## workspace's name.
	context_title : State, Pane -> Str
	context_title = |state, shown|
		match Model.context_of(state, shown) {
			Session(session_id) => Model.session(state, session_id).title
			Workspace(workspace_id) => state.workspaces.workspaces.find_first(|listed| listed.id == workspace_id).map_ok(|listed| listed.name) ?? workspace_id
		}

	entries : State, Str -> List(Chat.Entry)
	entries = |state, session_id|
		state.timelines.find_first(|timeline| timeline.session_id == session_id).map_ok(|timeline| timeline.entries) ?? []

	## A known session, one starting, or one named by its id until the daemon
	## lists it.
	session : State, Str -> Chat.Session
	session = |state, session_id| {
		known = state.sessions.find_first(|listed| listed.id == session_id)
		placeholder = state.creating.find_first(|creating| Model.created_id(creating) == session_id).map_ok(|creating| Chat.session({ id: session_id, provider: "", agent: creating.form.agent, title: creating.title, status: Idle }))
		known ?? (placeholder ?? Chat.session({ id: session_id, provider: "", agent: "", title: session_id, status: Idle }))
	}

	## A tool call and the result with its `call_id`, once one arrives. Output
	## past its first 4 lines is `folded`.
	ToolCard : { tool : Str, input : Str, state : [Running, Done, Failed], output : Str, folded : Str }

	Shown : { sequence : U64, event : Chat.Event, card : Try(ToolCard, [NotTool]) }

	## A timeline as a chat pane shows it: each tool call as a card holding its
	## result, which shows no entry of its own.
	with_tool_cards : List(Chat.Entry) -> List(Shown)
	with_tool_cards = |timeline| {
		results = timeline.keep_oks(
			|entry|
				match entry.event {
					ToolResult(result) => Ok(result)
					_ => Err(NotResult)
				},
		)
		timeline.keep_oks(
			|{ sequence, event }|
				match event {
					ToolResult(_) => Err(InCard)
					ToolCall({ call_id, tool, input }) => {
						(state, lines) = match results.find_first(|result| result.call_id == call_id) {
							Ok(result) => (if (result.failed) Failed else Done, result.output.split_on("\n"))
							Err(NotFound) => (Running, [])
						}
						Ok({ sequence, event, card: Ok({ tool, input, state, output: Str.join_with(lines.take_first(4), "\n"), folded: Str.join_with(lines.drop_first(4), "\n") }) })
					}
					_ => Ok({ sequence, event, card: Err(NotTool) })
				},
		)
	}

	## A chat pane's entries, as its options show them: tool output in full,
	## folded or hidden, and status lines or not.
	chat_entries : State, Pane -> List(Shown)
	chat_entries = |state, shown| {
		status = |entry|
			match entry.event {
				StatusChanged(_) => Bool.True
				_ => Bool.False
			}
		card = |tool|
			match Model.option(shown, "tool_output") {
				"Full" => { ..tool, output: if (tool.folded.is_empty()) tool.output else "${tool.output}\n${tool.folded}", folded: "" }
				"Hidden" => { ..tool, output: "", folded: "" }
				_ => tool
			}
		Model.with_tool_cards(Model.entries(state, Model.session_of(state, shown)))
			.drop_if(|entry| Model.option(shown, "show_status") == "false" and status(entry))
			.map(|entry| { ..entry, card: entry.card.map_ok(card) })
	}

	last_sequence : State, Str -> U64
	last_sequence = |state, session_id| Model.entries(state, session_id).last().map_ok(|entry| entry.sequence) ?? 0

	## The topics the panes follow: the sessions; the timeline of each session
	## a chat pane shows; the attention items, which the title counts; of
	## each Changes pane on screen, its scope's changes and the hunks of the
	## file it shows; and the workspaces, while a pane lists them. Until the
	## manifest arrives, every capability counts as offered.
	subjects : State -> List(Protocol.Subject)
	subjects = |state| {
		offered = |id| state.providers.is_empty() or state.capabilities.contains(id)
		laid_out = Model.panes(state)
		timelines = laid_out.keep_if(|shown| shown.widget == "chat").map(|shown| Model.session_of(state, shown)).drop_if(|session_id| session_id.is_empty() or session_id.starts_with("starting:")).map(|session_id| Timeline(session_id))
		items = if (offered(Capability.attention_v1)) [Items] else []
		git = |shown| {
			context = Model.context_of(state, shown)
			{ scope, file, .. } = Model.git_pane(state, shown.id)
			match file {
				Selected(path) => [Changes({ context, scope }), File({ context, scope, path })]
				NoFile => [Changes({ context, scope })]
			}
		}
		changes = if (offered(Capability.workspace_git_v1)) laid_out.keep_if(|shown| shown.widget == "changes" and Model.pane_visible(state, shown.id) and Model.context_of(state, shown) != Session("") and !Context.to_str(Model.context_of(state, shown)).starts_with("starting:")).join_map(git) else []
		listing = if (offered(Capability.workspaces_v1) and laid_out.any(|shown| shown.widget == "workspaces")) [WorkspaceList, Agents] else []
		all = (if (offered(Capability.chat_v1)) [Sessions] else []).concat(timelines).concat(items).concat(changes).concat(listing)
		all.fold([], |found, subject| if (found.contains(subject)) found else found.append(subject))
	}

	## Sends a poll of what the panes follow, each topic after the cursor the
	## UI has, unless a poll is on its way: then another follows it.
	poll : State -> State
	poll = |state| {
		followed = Model.subjects(state)
		topics = followed.map(
			|subject| {
				{ capability, topic } = Protocol.named(subject)
				{ capability, topic, after: state.cursors.find_first(|known| known.capability == capability and known.topic == topic).map_ok(|known| known.cursor) ?? "" }
			},
		)
		if (state.polling)
			{ ..state, poll_again: Bool.True }
		else if (followed.is_empty())
			state
		else
			{ ..state, poll: { serial: state.poll.serial + 1, subjects: followed, topics }, polling: Bool.True, poll_again: Bool.False }
	}

	## Polls each second, unless a poll is still on its way.
	tick : State -> State
	tick = |state| if (state.polling) state else Model.poll(state)

	## Polls at once when the topics the panes follow change, or once the
	## poll on its way answers.
	follow : State -> State
	follow = |state| if (state.polling and state.poll.subjects == Model.subjects(state)) state else Model.poll(state)

	## Takes a poll's answer, each topic's in the order asked: its events and
	## cursor. Then sends the poll asked for meanwhile, if any.
	polled : State, Poll, List(Protocol.Update) -> State
	polled = |state, sent, updates| {
		applied = updates.map_with_index(|update, index| (sent.subjects.get(index), update)).fold(
			state,
			|so_far, (subject, update)|
				match subject {
					Ok(followed) if Protocol.named(followed).topic == update.topic and update.error.is_err() => Model.updated(so_far, sent.serial, followed, update)
					_ => so_far
				},
		)
		focus = if (applied.focus == Session("")) Session(applied.sessions.first().map_ok(|first| first.id) ?? "") else applied.focus
		settled = { ..applied, focus, polling: Bool.False, poll_again: Bool.False }
		answered = { ..settled, sent: settled.sent.drop_if(|sent_request| Model.confirmed(settled, sent_request)), creating: settled.creating.drop_if(|creating| Model.made_listed(settled, creating)) }
		if (state.poll_again) Model.poll(answered) else answered
	}

	## A poll that failed asks again with the next.
	poll_failed : State -> State
	poll_failed = |state| if (state.poll_again) Model.poll({ ..state, polling: Bool.False }) else { ..state, polling: Bool.False }

	## Takes a topic's update from the poll numbered `serial`.
	updated : State, U64, Protocol.Subject, Protocol.Update -> State
	updated = |state, serial, subject, { capability, topic, cursor, events, .. }| {
		cursors = state.cursors.drop_if(|known| known.capability == capability and known.topic == topic).append({ capability, topic, cursor })
		received = events.fold({ ..state, cursors }, |so_far, event| Model.received(so_far, subject, event))
		match subject {
			Timeline(session_id) if !received.timelines.any(|timeline| timeline.session_id == session_id) => { ..received, timelines: received.timelines.append({ session_id, entries: [] }) }
			# Unchanged items still settle what was set aside.
			Items => Model.attention_fetched(received, serial, received.attention)
			_ => received
		}
	}

	## Takes a topic's event: a timeline's entries after those the UI has, or
	## a snapshot's value.
	received : State, Protocol.Subject, Protocol.Event -> State
	received = |state, subject, event|
		match (subject, event) {
			(_, Sessions(sessions)) => { ..state, sessions }
			(Timeline(session_id), Entry(entry)) =>
				if (entry.sequence <= Model.last_sequence(state, session_id))
					state
				else if (state.timelines.any(|timeline| timeline.session_id == session_id))
					{ ..state, timelines: state.timelines.map(|timeline| if (timeline.session_id == session_id) { ..timeline, entries: timeline.entries.append(entry) } else timeline) }
				else
					{ ..state, timelines: state.timelines.append({ session_id, entries: [entry] }) }
			(_, Items(items)) => { ..state, attention: items }
			(_, Listed(listed)) => { ..state, workspaces: listed }
			(_, Agents(listed)) => { ..state, agents: listed }
			(Changes({ context, .. }), Changes({ workspace, status, changes, commits })) =>
				{
					..state,
					git: state.git.drop_if(|known| known.context == context).append({ context, workspace, status, commits }),
					git_changes: state.git_changes.drop_if(|known| known.context == context and known.changes.scope == changes.scope).append({ context, changes }),
				}
			(File({ context, scope, .. }), File({ path, hunks })) =>
				{ ..state, git_hunks: state.git_hunks.drop_if(|known| known.context == context and known.scope == scope and known.path == path).append({ context, scope, path, hunks }) }
			_ => state
		}

	## Whether a listing has what a creation made: a workspace the
	## workspaces list, or an agent its workspace lists, or that the sessions
	## list when the workspaces don't list its workspace.
	made_listed : State, Creating -> Bool
	made_listed = |state, creating| {
		id = creating.id
		workspaces = state.workspaces.workspaces
		match creating.form.kind {
			_ if id.is_empty() => Bool.False
			Workspace => workspaces.any(|workspace| workspace.id == id)
			_ => workspaces.any(|workspace| workspace.session_ids.contains(id)) or (state.sessions.any(|listed_session| listed_session.id == id) and !workspaces.any(|workspace| workspace.id == creating.form.place))
		}
	}

	## Whether a sent request's session's timeline shows it.
	confirmed : State, Sent -> Bool
	confirmed = |state, sent| {
		timeline = Model.entries(state, sent.session_id)
		match sent.request {
			SendMessage({ text, .. }) => timeline.any(|entry| entry.sequence > sent.after and entry.event == UserMessage({ text: text }))
			AnswerPermission({ request_id, .. }) => !Chat.pending_permissions(timeline).contains(request_id) and !state.attention.any(|item| item.permissions.any(|asked| asked.request_id == request_id))
			Cancel({ session_id }) => !Model.busy(Model.session(state, session_id).status)
			_ => Bool.True
		}
	}

	## Sends a request, and shows a message or permission answer as sent until
	## its session's timeline shows it.
	send : State, Chat.Request -> State
	send = |state, request| {
		serial = state.outbox.serial + 1
		session_id = match request {
			SendMessage(message) => message.session_id
			AnswerPermission(answered) => answered.session_id
			Cancel(stopped) => stopped.session_id
			_ => ""
		}
		sent = { serial, session_id, request, after: Model.last_sequence(state, session_id), failed: "" }
		{ ..state, outbox: { serial, request }, sent: state.sent.append(sent), notice: "" }
	}

	## Whether a session's agent is in a turn, which Stop ends.
	busy : Chat.Status -> Bool
	busy = |status| status == Running or status == AwaitingPermission

	## Whether a request stops a session.
	stops : Chat.Request, Str -> Bool
	stops = |request, session_id|
		match request {
			Cancel(stopped) => stopped.session_id == session_id
			_ => Bool.False
		}

	## Stops the agent of the session a pane shows, shown as stopping at once
	## until its status changes. A stop refused before is asked again.
	stop : State, Str -> State
	stop = |state, pane_id| {
		session_id = Model.session_of(state, Model.pane(state, pane_id))
		{ ..Model.send({ ..state, sent: state.sent.drop_if(|sent| Model.stops(sent.request, session_id)) }, Cancel({ session_id: session_id })), menu: "" }
	}

	## Whether a session is being stopped, or why it wasn't.
	stopping : State, Str -> [NotStopping, Stopping, NotStopped(Str)]
	stopping = |state, session_id|
		match state.sent.find_last(|sent| Model.stops(sent.request, session_id)) {
			Ok({ failed, .. }) if failed.is_empty() => Stopping
			Ok({ failed, .. }) => NotStopped(failed)
			Err(NotFound) => NotStopping
		}

	## Takes the daemon's refusal of a request: a message or stop stays,
	## failed with `reason`, and a permission request's prompt comes back.
	refused : State, U64, Str -> State
	refused = |state, serial, reason| {
		answer = |sent|
			match sent.request {
				AnswerPermission(_) => sent.serial == serial
				_ => Bool.False
			}
		sent = state.sent.drop_if(answer).map(|kept| if (kept.serial == serial) { ..kept, failed: reason } else kept)
		{ ..state, sent, notice: reason }
	}

	## Takes the daemon's answer to a chat request: accepted, it polls for what
	## the request changed.
	called : State, U64, Protocol.Answer(Chat.Response) -> State
	called = |state, serial, answered|
		match answered {
			Ok(Rejected(reason)) => Model.refused(state, serial, reason)
			Ok(_) => Model.poll(state)
			Err({ message, .. }) => Model.refused(state, serial, message)
		}

	## Sends a failed message again.
	retry : State, Str -> State
	retry = |state, serial|
		match state.sent.find_first(|sent| sent.serial.to_str() == serial) {
			Ok(failed) => Model.send({ ..state, sent: state.sent.drop_if(|sent| sent.serial == failed.serial) }, failed.request)
			Err(NotFound) => state
		}

	## The messages and answers sent to a session that its timeline does not
	## show yet.
	unconfirmed : State, Str -> List(Sent)
	unconfirmed = |state, session_id| state.sent.keep_if(|sent| sent.session_id == session_id and !Model.stops(sent.request, session_id))

	## Whether a chat pane shows a session whose timeline has not arrived yet.
	loading : State, Str -> Bool
	loading = |state, session_id| !session_id.is_empty() and !state.timelines.any(|timeline| timeline.session_id == session_id)

	draft : State, Str -> Str
	draft = |state, pane_id| state.drafts.find_first(|candidate| candidate.pane == pane_id).map_ok(|found| found.text) ?? ""

	set_draft : State, Str, Str -> State
	set_draft = |state, pane_id, text| { ..state, drafts: state.drafts.drop_if(|found| found.pane == pane_id).append({ pane: pane_id, text }) }

	## Sends a pane's draft to the session the pane shows, and clears its
	## composer.
	submit : State, Str -> State
	submit = |state, pane_id| {
		text = Model.draft(state, pane_id).trim()
		session_id = Model.session_of(state, Model.pane(state, pane_id))
		count = (state.cleared.find_first(|composer| composer.pane == pane_id).map_ok(|composer| composer.count) ?? 0) + 1
		if (text.is_empty() or session_id.is_empty())
			state
		else
			Model.send({ ..Model.set_draft(state, pane_id, ""), cleared: state.cleared.drop_if(|composer| composer.pane == pane_id).append({ pane: pane_id, count }) }, SendMessage({ session_id, text }))
	}

	## The latest permission request in the session a pane shows that no answer
	## follows, in the timeline or on its way.
	pending : State, Str -> Try({ session_id : Str, request_id : Str, tool : Str, description : Str }, [NoneWaiting])
	pending = |state, pane_id| {
		session_id = Model.session_of(state, Model.pane(state, pane_id))
		timeline = Model.entries(state, session_id)
		answering = state.sent.keep_oks(
			|sent|
				match sent.request {
					AnswerPermission(answered) => Ok(answered.request_id)
					_ => Err(NotAnswer)
				},
		)
		request_id = Chat.pending_permissions(timeline).drop_if(|id| answering.contains(id)).last() ? |_| NoneWaiting
		asked = timeline.find_first(
			|entry|
				match entry.event {
					PermissionRequested(question) => question.request_id == request_id
					_ => Bool.False
				},
		)
		match asked {
			Ok({ event: PermissionRequested({ tool, description, .. }), .. }) => Ok({ session_id: session_id, request_id: request_id, tool: tool, description: description })
			_ => Err(NoneWaiting)
		}
	}

	answer : State, Str, Bool -> State
	answer = |state, pane_id, allowed|
		match Model.pending(state, pane_id) {
			Ok({ session_id, request_id, .. }) => Model.send(state, AnswerPermission({ session_id, request_id, allowed }))
			Err(NoneWaiting) => state
		}

	## The attention items as the inbox shows them: set aside, or back, as soon
	## as asked.
	inbox_items : State -> List(Attention.Item)
	inbox_items = |state|
		state.attention.map(|item| state.setting_aside.find_last(|asked| asked.session_id == item.session_id).map_ok(|asked| { ..item, set_aside: asked.set_aside }) ?? item)

	## The items in `attention_state` not set aside.
	waiting : State, Attention.State -> List(Attention.Item)
	waiting = |state, attention_state| Model.inbox_items(state).keep_if(|item| item.state == attention_state and item.set_aside == No)

	later : State -> List(Attention.Item)
	later = |state| Model.inbox_items(state).keep_if(|item| item.set_aside != No)

	## How many items need you, as the document title and the inbox's tab
	## show.
	needs_you : State -> U64
	needs_you = |state| Model.waiting(state, NeedsYou).len()

	## Takes the items the poll numbered `asked` answered.
	attention_fetched : State, U64, List(Attention.Item) -> State
	attention_fetched = |state, asked, items| {
		shown = |aside| (aside.accepted > 0 and aside.accepted <= asked) or items.any(|item| item.session_id == aside.session_id and item.set_aside == aside.set_aside)
		fetched = { ..state, attention: items, setting_aside: state.setting_aside.drop_if(shown) }
		{ ..fetched, sent: fetched.sent.drop_if(|sent| Model.confirmed(fetched, sent)) }
	}

	## Settles an item, snoozes it for some minutes, or brings it back (`No`).
	set_aside : State, Str, [No, Settled, Snoozed(U32)] -> State
	set_aside = |state, session_id, asked|
		match state.attention.find_first(|item| item.session_id == session_id) {
			Err(NotFound) => state
			Ok({ signature, .. }) => {
				serial = state.attention_outbox.serial + 1
				(request, set_aside) =
					match asked {
						Settled => (Settle({ session_id, signature }), Settled)
						Snoozed(minutes) => (Snooze({ session_id, signature, minutes }), Snoozed)
						No => (Unsettle({ session_id: session_id }), No)
					}
				{ ..state, attention_outbox: { serial, request }, setting_aside: state.setting_aside.append({ serial, session_id, set_aside, accepted: 0 }), notice: "" }
			}
		}

	## How long an inbox pane's Snooze sets an item aside, in minutes.
	snooze_minutes : Pane -> U32
	snooze_minutes = |shown|
		match Model.option(shown, "snooze_length") {
			"1 day" => 24 * 60
			"1 week" => 7 * 24 * 60
			_ => 60
		}

	## Takes the daemon's answer to a settle or snooze: accepted, it holds until
	## the poll it asks for shows it; refused, the item comes back, with why.
	set_aside_answered : State, U64, Protocol.Answer(Attention.Response) -> State
	set_aside_answered = |state, serial, answered|
		match answered {
			Ok(Rejected(reason)) | Err({ message: reason, .. }) => { ..state, setting_aside: state.setting_aside.drop_if(|aside| aside.serial == serial), notice: reason }
			Ok(_) => Model.poll({ ..state, setting_aside: state.setting_aside.map(|aside| if (aside.serial == serial) { ..aside, accepted: state.poll.serial + 1 } else aside) })
		}

	## The latest permission request of an item that no answer on its way
	## follows.
	item_permission : State, Str -> Try(Attention.Permission, [NoneWaiting])
	item_permission = |state, session_id| {
		answering = state.sent.keep_oks(
			|sent|
				match sent.request {
					AnswerPermission(answered) => Ok(answered.request_id)
					_ => Err(NotAnswer)
				},
		)
		permissions = state.attention.find_first(|item| item.session_id == session_id).map_ok(|item| item.permissions) ?? []
		permissions.drop_if(|asked| answering.contains(asked.request_id)).last().map_err(|_| NoneWaiting)
	}

	answer_item : State, Str, Bool -> State
	answer_item = |state, session_id, allowed|
		match Model.item_permission(state, session_id) {
			Ok({ request_id, .. }) => Model.send(state, AnswerPermission({ session_id, request_id, allowed }))
			Err(NoneWaiting) => state
		}

	## Focuses a context, so panes that follow the focus show it, and shows
	## the first chat's column, which on a narrow screen is a jump to it.
	open : State, Context.Id -> State
	open = |state, context| {
		focused = { ..state, focus: context }
		match state.columns.find_first(|column| column.panes.any(|shown| shown.widget == "chat")) {
			Ok(column) => Model.show_column(focused, column.id)
			Err(NotFound) => focused
		}
	}

	## Whether a pane is on screen: not a tab behind another, nor in a
	## collapsed drawer.
	pane_visible : State, Str -> Bool
	pane_visible = |state, pane_id|
		match state.columns.find_first(|column| column.panes.any(|shown| shown.id == pane_id)) {
			Ok(column) => (!column.tabbed or column.active == pane_id) and !state.collapsed.contains(Model.slot_of(state, column.id))
			Err(NotFound) => Bool.False
		}

	## A Changes pane shows uncommitted changes and no file until picked.
	git_pane : State, Str -> GitPane
	git_pane = |state, pane_id| state.git_panes.find_first(|shown| shown.pane == pane_id) ?? { pane: pane_id, scope: Uncommitted, file: NoFile }

	set_git_pane : State, GitPane -> State
	set_git_pane = |state, shown| { ..state, git_panes: state.git_panes.drop_if(|old| old.pane == shown.pane).append(shown) }

	## Shows a scope, or a file of it, in a Changes pane at once; the poll it
	## sends at once brings what the UI doesn't have yet.
	show_git : State, Str, WorkspaceGit.Scope, [Selected(Str), NoFile] -> State
	show_git = |state, pane_id, scope, file| Model.set_git_pane(state, { ..Model.git_pane(state, pane_id), scope, file })

	git_changes_of : State, Context.Id, WorkspaceGit.Scope -> Try(WorkspaceGit.Changes, [NotFound])
	git_changes_of = |state, context, scope| state.git_changes.find_first(|known| known.context == context and known.changes.scope == scope).map_ok(|known| known.changes)

	## What polls answered of the context a pane shows.
	git_of : State, Pane -> Git
	git_of = |state, shown| {
		context = Model.context_of(state, shown)
		state.git.find_first(|known| known.context == context) ?? { context, workspace: Unknown, status: NoStatus, commits: [] }
	}

	## What a Changes pane shows: its context's git, or why it can't yet.
	git_shown : State, Pane -> [NoSession, Loading, Unreadable, NotGit, Shown]
	git_shown = |state, shown|
		if (Model.context_of(state, shown) == Session(""))
			NoSession
		else if (!state.git.any(|known| known.context == Model.context_of(state, shown)))
			Loading
		else
			match Model.git_of(state, shown).workspace {
				Unknown => Unreadable
				Known({ kind: NotGit, .. }) => NotGit
				Known(_) => Shown
			}

	## The files of the scope a Changes pane shows, until its poll answers.
	git_files : State, Pane -> [Files(List(WorkspaceGit.File)), Loading]
	git_files = |state, shown| Model.git_changes_of(state, Model.context_of(state, shown), Model.git_pane(state, shown.id).scope).map_ok(|changes| Files(changes.files)) ?? Loading

	## The hunks of the file a Changes pane shows, until its poll answers, if
	## its scope has that file.
	git_hunks_of : State, Pane -> [Hunks(List(WorkspaceGit.Hunk)), Loading, NoFile]
	git_hunks_of = |state, shown| {
		context = Model.context_of(state, shown)
		{ scope, file, .. } = Model.git_pane(state, shown.id)
		match (file, Model.git_files(state, shown)) {
			(Selected(_), Loading) => Loading
			(Selected(path), Files(listed)) if listed.any(|listed_file| listed_file.path == path) => state.git_hunks.find_first(|known| known.context == context and known.scope == scope and known.path == path).map_ok(|known| Hunks(known.hunks)) ?? Loading
			_ => NoFile
		}
	}

	DiffCell : { key : Str, class : Str, text : Str }

	## A hunk's lines as rows of cells: unified, each line under its old and new
	## numbers, or split, old beside new with a removed line beside the added
	## line replacing it.
	diff_rows : Str, List(WorkspaceGit.Line) -> List({ key : Str, cells : List(DiffCell) })
	diff_rows = |diff_layout, lines| {
		number = |line_number| if (line_number == 0) "" else line_number.to_str()
		kind = |line|
			match line.kind {
				Added => "added"
				Removed => "removed"
				Context => "context"
			}
		old = |line| [{ class: "number", text: number(line.old_line) }, { class: kind(line), text: line.text }]
		new = |line| [{ class: "number", text: number(line.new_line) }, { class: kind(line), text: line.text }]
		blank = [{ class: "number", text: "" }, { class: "empty", text: "" }]
		rows =
			if diff_layout == "Split" {
				paired = lines.fold(
					{ rows: [], open: 0 },
					|so_far, line|
						match line.kind {
							Context => { rows: so_far.rows.append({ left: old(line), right: new(line) }), open: so_far.rows.len() + 1 }
							Removed => { ..so_far, rows: so_far.rows.append({ left: old(line), right: blank }) }
							Added =>
								if (so_far.open < so_far.rows.len())
									{ rows: so_far.rows.map_with_index(|row, index| if (index == so_far.open) { ..row, right: new(line) } else row), open: so_far.open + 1 }
								else
									{ rows: so_far.rows.append({ left: blank, right: new(line) }), open: so_far.rows.len() + 1 }
						},
				)
				paired.rows.map(|row| row.left.concat(row.right))
			} else {
				sign = |line|
					match line.kind {
						Added => "+"
						Removed => "-"
						Context => " "
					}
				lines.map(|line| [{ class: "number", text: number(line.old_line) }, { class: "number", text: number(line.new_line) }, { class: kind(line), text: "${sign(line)} ${line.text}" }])
			}
		rows.map_with_index(|cells, index| { key: index.to_str(), cells: cells.map_with_index(|cell, column| { key: column.to_str(), class: cell.class, text: cell.text }) })
	}

	## A row of a Workspaces pane: a group of workspaces, by project or by
	## what they need from you, folded or not; a workspace in it; or a
	## session in that. `key` is the context a workspace or session row
	## focuses (`Context.to_str`), or `group:` and the group's. A row is
	## `creatable` when + on it starts an agent there, or creates a workspace
	## of its project.
	Row : { key : Str, kind : [Group, Workspace, Session], title : Str, detail : Str, counts : Str, dot : Str, status : Str, focused : Bool, folded : Bool, creatable : Bool }

	## A Workspaces pane's rows, as its options group and filter them, each
	## workspace marked as urgent as its most urgent session.
	workspace_rows : State, Pane -> List(Row)
	workspace_rows = |state, shown| {
		folded = Model.option(shown, "folded").split_on("\n")
		# Those still starting show where they will be, idle and without git.
		placeholders = state.creating.keep_if(|creating| creating.form.kind == Workspace).map(|creating| { id: Model.created_id(creating), provider: "", project_id: creating.form.place, name: creating.title, directory: "", kind: Checkout, branch: NotGit, state: Idle, dirty: Bool.False, changes: Uncounted, pinned: Bool.False, labels: [], session_ids: [] })
		listed = state.workspaces.workspaces.concat(placeholders).drop_if(|workspace| Model.option(shown, "show_idle") == "false" and workspace.state == Idle and !Model.starting(state, workspace.id))
		groups =
			if Model.option(shown, "group_by") == "Status" {
				Attention.ranks.map(|rank| { key: "group:${attention_word(rank)}", title: attention_word(rank), members: listed.keep_if(|workspace| workspace.state == rank), creatable: Bool.False }).drop_if(|group| group.members.is_empty())
			} else {
				state.workspaces.projects.map(|project| { key: "group:${project.id}", title: project.name, members: listed.keep_if(|workspace| workspace.project_id == project.id), creatable: Bool.True })
			}
		blank = { key: "", kind: Group, title: "", detail: "", counts: "", dot: "", status: "", focused: Bool.False, folded: Bool.False, creatable: Bool.False }
		mark = |row| if (Model.starting(state, row.key) or Model.starting(state, row.key.drop_prefix("workspace:"))) { ..row, dot: "starting", status: "starting…", creatable: Bool.False } else row
		workspace_row = |workspace| {
			branch = match workspace.branch {
				Branch(name) if name != workspace.name => name
				Detached => "detached"
				_ => ""
			}
			mark({ ..blank, key: Context.to_str(Workspace(workspace.id)), kind: Workspace, title: workspace.name, detail: branch, counts: Model.change_counts(state, workspace), dot: attention_dot(workspace.state), focused: state.focus == Workspace(workspace.id), creatable: Bool.True })
		}
		sessions_in = |workspace| {
			agents = state.creating.keep_if(|creating| creating.form.kind == Agent and creating.form.place == workspace.id).map(|creating| Model.session(state, Model.created_id(creating)))
			state.sessions.keep_if(|listed_session| workspace.session_ids.contains(listed_session.id)).concat(agents.drop_if(|agent| workspace.session_ids.contains(agent.id)))
		}
		groups.join_map(
			|group| {
				header = { ..blank, key: group.key, title: group.title, counts: group.members.len().to_str(), folded: folded.contains(group.key), creatable: group.creatable }
				members = group.members.join_map(|workspace| [workspace_row(workspace)].concat(sessions_in(workspace).map(|listed_session| mark(Model.session_row(state, listed_session)))))
				if (header.folded) [header] else members.prepend(header)
			},
		)
	}

	## A session's row, in a Workspaces or a Sessions pane.
	session_row : State, Chat.Session -> Row
	session_row = |state, listed_session| {
		rank = Attention.item(listed_session, []).state
		{ key: listed_session.id, kind: Session, title: listed_session.title, detail: "", counts: "", dot: attention_dot(rank), status: attention_word(rank), focused: state.focus == Session(listed_session.id), folded: Bool.False, creatable: Bool.False }
	}

	## A Sessions pane's rows: every session, with its agent if it shows that.
	session_rows : State, Pane -> List(Row)
	session_rows = |state, shown| state.sessions.map(|listed_session| { ..Model.session_row(state, listed_session), detail: if (Model.option(shown, "show_agent") == "true") listed_session.agent else "" })

	## A workspace's uncommitted changes as "+3 −1": as its provider counts
	## them, else as a Changes pane last saw them; "changed" when they are
	## there but uncounted, and nothing when they are none or unknown.
	change_counts : State, Workspaces.Workspace -> Str
	change_counts = |state, workspace| {
		seen = workspace.session_ids.map(|session_id| Session(session_id)).prepend(Workspace(workspace.id)).keep_oks(|context| Model.git_changes_of(state, context, Uncommitted)).first()
		counted =
			match (workspace.changes, seen) {
				(Counted(counts), _) if counts.additions + counts.deletions > 0 => Ok(counts)
				(_, Ok({ files, .. })) => Ok(files.fold({ additions: 0, deletions: 0 }, |sum, file| { additions: sum.additions + file.additions, deletions: sum.deletions + file.deletions }))
				_ => Err(Unknown)
			}
		match counted {
			Ok({ additions, deletions }) if additions + deletions > 0 => "+${additions.to_str()} −${deletions.to_str()}"
			_ if workspace.dirty => "changed"
			_ => ""
		}
	}

	## Folds or unfolds a group of a Workspaces pane, which the snapshot
	## keeps, or focuses a workspace or a session.
	pick_row : State, { pane_id : Str, key : Str } -> State
	pick_row = |state, { pane_id, key }|
		if key.starts_with("group:") {
			folded = Model.option(Model.pane(state, pane_id), "folded").split_on("\n").drop_if(Str.is_empty)
			Model.set_option(state, pane_id, "folded", Str.join_with(if (folded.contains(key)) folded.drop_if(|group| group == key) else folded.append(key), "\n"))
		} else {
			if (key.starts_with("starting:") or key.starts_with("workspace:starting:")) state else Context.from_str(key).map_ok(|context| Model.open(state, context)) ?? state
		}

	## Opens a Workspaces pane's form: from a workspace's row, to start an
	## agent there of the first kind its provider starts; from a project's,
	## to create a workspace of it, and from the pane's header (`key` ""), of
	## the first project. Other rows open none.
	open_form : State, { pane_id : Str, key : Str } -> State
	open_form = |state, { pane_id, key }| {
		project = if (key.is_empty()) state.workspaces.projects.first() else state.workspaces.projects.find_first(|listed| "group:${listed.id}" == key)
		match (Context.from_str(key), project) {
			(Ok(Workspace(workspace_id)), _) => { ..state, form: { ..Model.closed_form, pane: pane_id, kind: Agent, place: workspace_id, agent: Model.agent_kinds(state, workspace_id).first() ?? "" } }
			(_, Ok(picked)) => { ..state, form: { ..Model.closed_form, pane: pane_id, kind: Workspace, place: picked.id } }
			_ => state
		}
	}

	## The kinds of agent the provider of a workspace starts.
	agent_kinds : State, Str -> List(Str)
	agent_kinds = |state, workspace_id| {
		provider = state.workspaces.workspaces.find_first(|listed| listed.id == workspace_id).map_ok(|listed| listed.provider) ?? ""
		state.agents.keep_if(|kind| kind.provider == provider).map(|kind| kind.agent)
	}

	## Starts the agent or creates the workspace the form describes, shown
	## at once as starting, and closes the form. An agent is focused, so the
	## chat shows it starting.
	submit_form : State -> State
	submit_form = |state| {
		form = { ..state.form, failed: "" }
		serial = state.create_outbox.serial + 1
		optional = |text| if (text.trim().is_empty()) Err(Missing) else Ok(text.trim())
		prompt = form.prompt.trim()
		if form.kind == Agent {
			call : { capability : Str, request : Chat.Request }
			call = { capability: "chat.v1", request: Create({ place: Workspace(form.place), agent: form.agent, model: optional(form.model), prompt }) }
			title = if (prompt.is_empty()) "New ${form.agent} agent" else prompt.split_on("\n").first() ?? prompt
			started = { ..state, form: Model.closed_form, creating: state.creating.append({ serial, form, title, id: "" }), create_outbox: { serial, key: call.capability, text: Json.to_str(call) }, notice: "" }
			if (form.agent.is_empty()) { ..state, form: { ..form, failed: "Pick a kind of agent." } } else Model.open(started, Session(Model.starting_key(serial)))
		} else {
			call : { capability : Str, request : Workspaces.Request }
			call = { capability: "workspaces.v1", request: Create({ project_id: form.place, kind: if (form.worktree) Worktree else Checkout, branch: optional(form.branch) }) }
			title = optional(form.branch) ?? "New workspace"
			{ ..state, form: Model.closed_form, creating: state.creating.append({ serial, form, title, id: "" }), create_outbox: { serial, key: call.capability, text: Json.to_str(call) }, notice: "" }
		}
	}

	## What a creation is named by until the daemon answers with its id.
	starting_key : U64 -> Str
	starting_key = |serial| "starting:${serial.to_str()}"

	created_id : Creating -> Str
	created_id = |creating| if (creating.id.is_empty()) Model.starting_key(creating.serial) else creating.id

	## Whether `id` names a session or workspace started that no listing has
	## yet.
	starting : State, Str -> Bool
	starting = |state, id| state.creating.any(|creating| Model.created_id(creating) == id) and !state.sessions.any(|listed_session| listed_session.id == id) and !state.workspaces.workspaces.any(|workspace| workspace.id == id)

	## Takes the daemon's answer to a creation: its id, which a focus on it
	## follows, until a listing has it; refused, it is gone, with why, and
	## its form back as it was.
	created : State, U64, Str -> State
	created = |state, serial, text| {
		answered : Try(Protocol.Answer([Started({ session_id : Str }), Created({ workspace_id : Str }), Rejected(Str)]), _)
		answered = Json.parse(text)
		made = match answered {
			Ok(Ok(Started({ session_id }))) => Ok(session_id)
			Ok(Ok(Created({ workspace_id }))) => Ok(workspace_id)
			Ok(Ok(Rejected(reason))) => Err(reason)
			Ok(Err({ message, .. })) => Err(message)
			Err(_) => Err("The daemon did not answer.")
		}
		was = Session(Model.starting_key(serial))
		match (made, state.creating.find_first(|creating| creating.serial == serial)) {
			(Ok(id), _) => Model.poll({ ..state, creating: state.creating.map(|creating| if (creating.serial == serial) { ..creating, id } else creating), focus: if (state.focus == was) Session(id) else state.focus })
			(Err(reason), Ok(undone)) => { ..state, creating: state.creating.drop_if(|creating| creating.serial == serial), form: { ..undone.form, failed: reason }, notice: reason, focus: if (state.focus == was) Workspace(undone.form.place) else state.focus }
			(Err(_), Err(_)) => state
		}
	}

	## What a pane's body shows: its widget, a wait for the daemon's manifest,
	## or a placeholder naming what is missing.
	Body : [Sessions, Workspaces, Chat, Inbox, Changes, Capabilities, Connecting, Missing]

	## The capabilities a pane's widget needs that no provider supplies, as
	## `ci.v1, ...`.
	missing : State, Pane -> Str
	missing = |state, shown| Str.join_with(Widgets.missing(Widgets.find(shown.widget), state.capabilities).map(Capability.to_str), ", ")

	body : State, Pane -> Body
	body = |state, shown| {
		if (state.providers.is_empty() and shown.widget != "capabilities")
			Connecting
		else if (!Model.missing(state, shown).is_empty())
			Missing
		else
			match shown.widget {
				"sessions" => Sessions
				"workspaces" => Workspaces
				"chat" => Chat
				"inbox" => Inbox
				"changes" => Changes
				_ => Capabilities
			}
	}
}

# A Changes pane's git is followed only while it is on screen.
expect {
	state = { ..Model.initial(""), focus: Session("a") }
	Model.subjects(state) == [Sessions, Timeline("a"), Items, Changes({ context: Session("a"), scope: Uncommitted }), WorkspaceList, Agents] and Model.subjects(Model.toggle_drawer(state, Right)) == [Sessions, Timeline("a"), Items, WorkspaceList, Agents]
}

# A poll follows each topic after its cursor, and takes an entry it has once.
expect {
	sent = Model.poll({ ..Model.initial(""), focus: Session("a") })
	entry = Entry({ sequence: 1, event: StatusChanged(Running) })
	answer = [{ capability: "chat.v1", topic: "sessions", cursor: "s", events: [], error: Err(Missing) }, { capability: "chat.v1", topic: "timeline/a", cursor: "1", events: [entry, entry], error: Err(Missing) }]
	answered = Model.polled(sent, sent.poll, answer)
	again = Model.poll(answered)
	Model.entries(answered, "a").len() == 1 and again.poll.topics.take_first(2) == [{ capability: "chat.v1", topic: "sessions", after: "s" }, { capability: "chat.v1", topic: "timeline/a", after: "1" }]
}

# One poll at a time: what is asked meanwhile is sent once it answers.
expect {
	sent = Model.poll({ ..Model.initial(""), focus: Session("a") })
	meanwhile = Model.follow({ ..sent, focus: Session("b") })
	answered = Model.polled(meanwhile, sent.poll, [])
	Model.tick(sent).poll.serial == 1 and Model.follow(sent).poll_again == Bool.False and meanwhile.poll.serial == 1 and answered.polling and answered.poll.subjects.contains(Timeline("b"))
}

expect {
	state = { ..Model.initial(""), focus: Session("a") }
	pinned = Model.toggle_pin(state, "pane-2")
	Model.session_of({ ..pinned, focus: Session("b") }, Model.pane(pinned, "pane-2")) == "a"
}

expect {
	saved = Json.to_str(Model.snapshot(Model.toggle_tabs(Model.initial(""), "column-2")))
	Json.to_str(Model.snapshot(Model.initial(saved))) == saved
}

expect {
	saved = Json.to_str(Model.snapshot(Model.layout(Model.initial(""), Model.tiling)))
	Json.to_str(Model.snapshot(Model.initial(saved))) == saved
}

# A setup's presets replace liton's own, and its starting one shows unless
# the browser kept a layout; a preset is shown until the layout changes.
expect {
	review = { name: "Review", snapshot: { ..Default.tiling.snapshot, columns: Default.tiling.snapshot.columns.drop_first(1) } }
	fresh = Model.set_up(Model.initial(""), { ..Setup.offered(Setup.empty), presets: [Default.developer, review], default_preset: "Review" })
	kept = Model.set_up(Model.initial(Json.to_str(Model.snapshot(Model.initial("")))), { ..Setup.offered(Setup.empty), presets: [review], default_preset: "Review" })
	fresh.presets.map(|preset| preset.name) == ["Developer", "Review"] and Model.preset_shown(fresh, "Review") and !Model.preset_shown(Model.use_preset(fresh, "Developer"), "Review") and kept.shell == Workbench and kept.presets == [review] and !Model.preset_shown(Model.close_pane(fresh, "pane-2"), "Review")
}

expect Model.set_up(Model.initial(""), Setup.offered(Setup.empty)).presets == Default.setup.presets

expect {
	saved = "{\"version\":1,\"panes\":[{\"id\":\"pane-7\",\"widget\":\"chat\",\"pinned\":\"\"}]}"
	chat = { id: "pane-7", widget: "chat", pinned: "", options: [] }
	Model.restore(saved).map_ok(Model.layout_of) == Ok({ shell: Tiling, columns: [{ id: "column-1", size: 1, tabbed: Bool.False, active: "pane-7", panes: [chat] }], collapsed: [] }) and Model.initial(saved).next_id == 8
}

expect {
	version_2 : List(Model.OldColumn) -> Str
	version_2 = |columns| {
		old : { version : U32, columns : List(Model.OldColumn) }
		old = { version: 2, columns }
		Json.to_str(old)
	}
	old_columns_of = |layout| layout.columns.map(|{ id, size, tabbed, active, panes }| { id, size, tabbed, active, panes: panes.map(|pane| { id: pane.id, widget: pane.widget, pinned: pane.pinned }) })
	old_columns = old_columns_of(Model.tiling)
	Model.restore(version_2(old_columns.map(|column| { ..column, size: 3 }))).map_ok(Model.layout_of) == Ok(Model.developer) and Model.restore(version_2(old_columns.drop_first(1))).map_ok(|layout| layout.shell) == Ok(Tiling)
}

expect {
	old_columns_of = |layout| layout.columns.map(|{ id, size, tabbed, active, panes }| { id, size, tabbed, active, panes: panes.map(|pane| { id: pane.id, widget: pane.widget, pinned: pane.pinned }) })
	version_3 : { version : U32, shell : Model.Shell, columns : List(Model.OldColumn) }
	version_3 = { version: 3, shell: Workbench, columns: old_columns_of(Model.developer) }
	Model.restore(Json.to_str(version_3)) == Ok(Model.snapshot_of(Model.developer))
}

expect {
	state = Model.toggle_drawer(Model.set_option(Model.initial(""), "pane-2", "show_status", "false"), Left)
	restored = Model.initial(Json.to_str(Model.snapshot(state)))
	chat = Model.pane(restored, "pane-2")
	restored.collapsed == [Left] and Model.option(chat, "show_status") == "false" and Model.option(chat, "tool_output") == "Folded"
}

expect {
	moved = Model.move_to_slot(Model.toggle_drawer(Model.initial(""), Left), "pane-3", Left)
	moved.columns.map(|column| column.panes.map(|pane| pane.id)) == [["pane-1", "pane-3"], ["pane-2"], []] and moved.columns.map(|column| column.active) == ["pane-3", "pane-2", ""] and moved.collapsed == []
}

expect {
	state = Model.layout(Model.initial(""), Model.tiling)
	split = Model.move_pane(Model.move_pane(state, "pane-2", Left), "pane-2", Left)
	Model.move_pane(state, "pane-1", Left).columns == state.columns and split.columns.map(|column| column.panes.map(|pane| pane.id)) == [["pane-2"], ["pane-1"], ["pane-3"]]
}

expect {
	closed = Model.close_pane({ ..Model.layout(Model.initial(""), Model.tiling), active_column: "column-2" }, "pane-2")
	closed.columns.map(|column| column.id) == ["column-1", "column-3"] and closed.active_column == "column-1"
}

expect {
	state = Model.add_pane(Model.close_pane(Model.initial(""), "pane-1"), "ci")
	state.columns.map(|column| column.panes.map(|pane| pane.widget)) == [[], ["chat", "ci"], ["changes"]] and state.active_column == "column-2"
}

expect {
	call = { sequence: 1, event: ToolCall({ call_id: "c", tool: "bash", input: "ls" }) }
	result = { sequence: 2, event: ToolResult({ call_id: "c", output: "1\n2\n3\n4\n5", failed: Bool.False }) }
	Model.with_tool_cards([call, result]).map(|shown| shown.card) == [Ok({ tool: "bash", input: "ls", state: Done, output: "1\n2\n3\n4", folded: "5" })]
}

expect {
	call = { sequence: 1, event: ToolCall({ call_id: "c", tool: "bash", input: "ls" }) }
	Model.with_tool_cards([call]).map(|shown| shown.card) == [Ok({ tool: "bash", input: "ls", state: Running, output: "", folded: "" })]
}

# A theme picked is saved with the layout; one never picked follows the
# setup's default, and a preset naming none keeps the one shown.
expect {
	picked = Model.use_preset(Model.use_theme(Model.initial(""), "Plain"), "Tiling")
	offered = Model.set_up(Model.initial(""), { ..Setup.offered(Setup.empty), themes: [Default.plain, Default.hypr], default_theme: "Hypr" })
	Model.theme_shown(Model.initial("")).name == "Pastoral" and Model.theme_shown(Model.initial(Json.to_str(Model.snapshot(picked)))).name == "Plain" and Model.theme_shown(offered).name == "Hypr" and Model.theme_shown(Model.use_theme(offered, "Pastoral")).name == "Hypr"
}

# 1 to 9 show the workspaces in order, however the one shown is changed.
expect {
	state = Model.pressed(Model.toggle_drawer(Model.initial(""), Right), "3")
	Model.workspace_shown(state) == "Tiling" and Model.workspace_shown(Model.pressed(Model.toggle_tabs(state, "column-2"), "¡")) == "Developer" and Model.pressed(state, "7") == state
}

# Focused on a workspace, Changes follows its git, and the chat its session
# that needs you most; a pane pinned then stays on the workspace.
expect {
	placed = |id, status| { ..Chat.session({ id, provider: "mock", agent: "claude", title: id, status }), workspace: Ok({ id: Ok("w1"), directory: "/w" }) }
	state = { ..Model.initial(""), focus: Workspace("w1"), sessions: [placed("a", Idle), placed("b", AwaitingPermission)] }
	pinned = Model.toggle_pin(state, "pane-3")
	Model.subjects(state) == [Sessions, Timeline("b"), Items, Changes({ context: Workspace("w1"), scope: Uncommitted }), WorkspaceList, Agents] and Model.pane(pinned, "pane-3").pinned == "workspace:w1" and Model.context_of({ ..pinned, focus: Session("a") }, Model.pane(pinned, "pane-3")) == Workspace("w1")
}

## What a workspace or a session in `rank` is doing, as a row of the
## Workspaces pane, or a group of them, says it.
attention_word : Attention.State -> Str
attention_word = |rank|
	match rank {
		NeedsYou => "waiting for you"
		Failed => "failed"
		Working => "running"
		Done => "done"
		Idle => "idle"
	}

## The class of a status dot (ui/style.css) showing `rank`.
attention_dot : Attention.State -> Str
attention_dot = |rank|
	match rank {
		NeedsYou => "waiting"
		Failed => "failed"
		Working => "running"
		Done => "done"
		Idle => "idle"
	}

# Workspaces list under their project, each with its sessions. Folding a
# project hides them, and grouping by status lists what needs you first.
expect {
	project = { id: "p1", provider: "mock", name: "app", directory: "/app" }
	workspace = |id, rank, session_ids| { id, provider: "mock", project_id: "p1", name: id, directory: "/app", kind: Checkout, branch: Branch("main"), state: rank, dirty: Bool.False, changes: Counted({ additions: 2, deletions: 1 }), pinned: Bool.False, labels: [], session_ids }
	listed = { projects: [project], workspaces: [workspace("w1", Idle, ["s1"]), workspace("w2", NeedsYou, [])] }
	state = Model.add_pane({ ..Model.initial(""), workspaces: listed, sessions: [Chat.session({ id: "s1", provider: "mock", agent: "claude", title: "Fix", status: Idle })] }, "workspaces")
	keys = |shown| Model.workspace_rows(shown, Model.pane(shown, "pane-4")).map(|row| row.key)
	folded = Model.pick_row(state, { pane_id: "pane-4", key: "group:p1" })
	by_status = Model.set_option(state, "pane-4", "group_by", "Status")
	keys(state) == ["group:p1", "workspace:w1", "s1", "workspace:w2"]
		and keys(folded) == ["group:p1"]
		and keys(Model.pick_row(folded, { pane_id: "pane-4", key: "group:p1" })) == keys(state)
		and keys(by_status) == ["group:waiting for you", "workspace:w2", "group:idle", "workspace:w1", "s1"]
		and keys(Model.set_option(state, "pane-4", "show_idle", "false")) == ["group:p1", "workspace:w2"]
		and Model.pick_row(state, { pane_id: "pane-4", key: "workspace:w1" }).focus == Workspace("w1")
		and Model.workspace_rows(state, Model.pane(state, "pane-4")).map(|row| row.counts) == ["2", "+2 −1", "", "+2 −1"]
		and Model.subjects(state).contains(WorkspaceList)
}

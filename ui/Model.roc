## The UI's state and every change to it, apart from the view so they can be
## tested without a browser.
import cap.Attention
import cap.Capability
import cap.Chat
import cap.Context
import cap.Files
import cap.Manifest
import cap.Protocol
import cap.Review
import cap.Rooms
import cap.Tickets
import cap.WorkspaceGit
import cap.Workspaces
import setup.Default
import setup.Setup
import Highlight
import Speech
import TicketDesk
import Widgets

Model := [].{

	## The layout's parts, as setups' presets hold them (setup/Setup.roc).
	Pane : Setup.Pane

	Column : Setup.Column

	## A pane and column as snapshots before version 4 saved them, without options.
	OldPane : { id : Str, widget : Str, pinned : Str }

	OldColumn : { id : Str, size : U32, tabbed : Bool, active : Str, panes : List(OldPane) }

	Shell : Setup.Shell

	## `collapsed` are the Workbench drawers hidden, `hidden` its panes hidden.
	Layout : { shell : Shell, columns : List(Column), collapsed : List(Slot), hidden : List(Str) }

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

		## The sessions, and below the projects and workspaces, as the daemon
		## last listed them (`listed`) with the renames, pins and archives on
		## their way applied (`Model.relisted`). An edit is shown until the
		## daemon refuses it, or until the poll numbered `accepted` answers,
		## the first sent after it accepted it (0 while it waits).
		sessions : List(Chat.Session),
		listed : { sessions : List(Chat.Session), workspaces : Workspaces.Listed },
		editing : List({ serial : U64, edit : Edit, accepted : U64 }),
		timelines : List(Timeline),

		## What panes that follow the focus show, `Session("")` for nothing.
		focus : Context.Id,

		workspaces : Workspaces.Listed,
		shell : Shell,
		columns : List(Column),
		collapsed : List(Slot),
		hidden : List(Str),

		## The column a narrow screen shows.
		active_column : Str,

		## The panel a narrow Workbench last scrolled to, by the reference
		## focusing it, and the URL hashes it replaced and pushed for the
		## browser's back to return to, "" for none (`Model.jump_to`);
		## `serial` counts each scroll. `url_hash` is the hash the URL shows.
		jump : { serial : U64, panel : Str, replace : Str, push : Str },
		url_hash : Str,

		## Counts on the numbers ending pane and column ids, so each is new.
		next_id : U64,
		drafts : List({ pane : Str, text : Str }),

		## How many times a draft changed other than by typing, sent or
		## How many times a draft changed other than by typing, sent, dictated or
		## mentioned, and the draft's key (`drafts`' `pane`) of the latest, so
		## `Liton.effects` writes it into the box `composer-<key>` though focused.
		drafts_rewritten : { pane : Str, count : U64 },

		## Whether the pointer is coarse, a touch screen's, whose keyboard has
		## no Shift+Enter: Enter in a composer then starts a new line.
		coarse_pointer : Bool,
		outbox : { serial : U64, request : Chat.Request },
		sent : List(Sent),
		attention : List(Attention.Item),

		## A settle, snooze or mark of what was seen sent, shown until the
		## daemon's items show it, or until the poll numbered `accepted`
		## answers, the first sent after the daemon accepted it (0 while it
		## waits).
		attending : List({ serial : U64, request : Attention.Request, accepted : U64 }),
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

		## What polls answered of each context's files: directories' entries,
		## and files' contents with their lines highlighted; and what each
		## Files pane shows.
		trees : List({ context : Context.Id, tree : Files.Tree }),
		texts : List({ context : Context.Id, contents : Files.Contents, lines : List(List(Highlight.Token)) }),
		file_panes : List(FilePane),

		## What polls answered of each context's review, the review.v1
		## requests on their way (sent as `call_outbox`), and the comment being
		## written. A request is applied to the review shown (`review_of`)
		## until the daemon refuses it, or until the poll numbered `accepted`
		## answers, the first sent after it accepted it (0 while it waits).
		reviews : List({ context : Context.Id, review : Review.Snapshot }),
		reviewing : List({ serial : U64, request : Review.Request, accepted : U64 }),
		composer : Composer,

		## What polls answered of rooms.v1: the rooms, each room's members, and
		## the entries of each room's messages (`root` "") and of each thread
		## (`root` its top-level message); what each Rooms pane shows; and the
		## requests on their way (sent as `call_outbox`). A request is shown at
		## once (`rooms_listed`, `sending_lines`) until the daemon refuses it,
		## or until the poll numbered `accepted` answers, the first sent after
		## it accepted it (0 while it waits); a message sent until a log posts
		## it, its id `message_id` once the daemon answers, or with why it
		## `failed` if the daemon refused it.
		rooms : List(Rooms.Room),
		room_members : List({ room_id : Str, members : List(Rooms.Member) }),
		room_logs : List({ room_id : Str, root : Str, entries : List(Rooms.Entry) }),
		room_panes : List(RoomPane),
		room_asks : List({ serial : U64, request : Rooms.Request, accepted : U64, message_id : Str, failed : Str }),

		## The themes settings offer and the one a snapshot naming none shows:
		## the daemon's setup's, or liton's own until it offers some. `theme`
		## is the one picked, or "" for the default. `glass` is whether tiles
		## blur what is behind them, which this browser keeps apart from the
		## snapshot.
		themes : List(Setup.Theme),
		default_theme : Str,
		theme : Str,
		glass : Bool,

		## The background this browser shows over the theme's (`Wallpaper`):
		## an image's URL, or "" for the theme's, and its dim in percent.
		wallpaper : { url : Str, dim : [ThemeDim, Dim(U8)] },

		## The pane last clicked or focused in, which the bright edge marks.
		focused_pane : Str,

		## The pane whose ⋯ menu is open, or a row's ⋮ menu as
		## `Model.row_menu_key` names it, or "".
		menu : Str,

		## The row of a pane being renamed, by its key ("" for none), and the
		## name typed.
		renaming : { pane : Str, key : Str, text : Str },

		## The keys of a sequence typed so far outside a text field
		## (ui/Keymap.roc), and how many sequences began, so that a pause ends
		## only the one it timed.
		keys_typed : { keys : List(Str), serial : U64 },

		## The time, in milliseconds since 1970, as of the last minute that
		## began, or second while a chat on screen shows a turn running: what
		## rows count the time since their last activity from, and the chat
		## how long its agent has worked.
		now : I64,

		## The code block last copied, by its key, and the copy asked of the
		## clipboard; `copied` is "" again if the clipboard refused it.
		copied : Str,
		clipboard : { serial : U64, key : Str, text : Str },

		## How many times each chat pane jumped to its latest entry.
		jumps : List({ pane : Str, count : U64 }),

		## How many of its session's latest entries each chat pane shows,
		## for the panes shown more than `Model.window` (`Model.show_earlier`).
		windows : List({ pane : Str, session_id : Str, count : U64 }),

		## The folds each chat pane has opened, by their keys (`Model.Fold`).
		opened_folds : List({ pane : Str, key : Str }),

		## What voice in the composers is doing (ui/Microphone.roc).
		voice : Speech.State,

		## The form a Workspaces pane opened, to start an agent or create a
		## workspace, and what is typed in it.
		form : Form,

		## Agents started and workspaces created, shown starting until a listing
		## has them; the last call whose answer may take a provider a while, to
		## create one, or a review.v1 or tickets.v1 request, its capability as `key` and its
		## JSON as `text`: the shape of `clipboard`, which spares the module
		## another instance of the effect that sends it; the kinds of agent each
		## provider starts.
		creating : List(Creating),
		call_outbox : { serial : U64, key : Str, text : Str },
		agents : List(Chat.Agent),

		## What Tickets panes show (`TicketDesk`), and the tickets.v1
		## requests on their way (sent as `call_outbox`).
		tickets : TicketDesk.State,
	}

	## A rename, pin or archive of chat.v1's or of workspaces.v1's.
	Edit : [Chat(Chat.Request), Workspaces(Workspaces.Request)]

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

	GitPane : { pane : Str, scope : WorkspaceGit.Scope, file : [Selected(Str), NoFile], folded : List(Str), in_main : Bool }

	## A row of a Changes pane's tree: a changed file, or a folder of them
	## with the lines they add and remove as its `file`'s.
	ChangedRow : { path : Str, folder : Bool, folded : Bool, depth : U64, file : WorkspaceGit.File }

	## What a Rooms pane shows: the room opened, "" for the list of rooms,
	## and the thread opened in it by its root, "" for none.
	RoomPane : { pane : Str, room_id : Str, root : Str }

	## A message as a Rooms pane shows it: its author's name, and whether an
	## agent; how long ago it was posted (`Model.ago`), and when; its text,
	## unless deleted; its reactions, each with how many reacted, whether
	## you did and whether your reaction is on its way; and, in the room, its thread's replies, who replied, and how
	## long ago last (`threaded`). A message sent and not yet posted says
	## so (`status`), or why the daemon refused it (`failed`), by the
	## `serial` of its request.
	RoomLine : { id : Str, author : Str, agent : Bool, ago : Str, time : Str, text : Str, edited : Bool, deleted : Bool, reactions : List({ emoji : Str, count : U64, mine : Bool, pending : Bool }), threaded : Bool, replies : U32, repliers : Str, last_reply : Str, status : Str, failed : Bool, serial : U64 }

	## A Files pane's directories open, and the file it shows, "" for none.
	FilePane : { pane : Str, folders : List(Str), file : Str }

	## The composer of a comment: on the lines `start` to `end` of a side of
	## the file or diff a pane shows, as a new thread; or a reply to a thread;
	## or a draft edited. Closed, its pane is "".
	Composer : { pane : Str, path : Str, scope : Review.Scope, side : Review.Side, start : U32, end : U32, thread : Str, editing : Str, text : Str }

	## The layout of a preset or snapshot.
	layout_of : Snapshot -> Layout
	layout_of = |{ shell, columns, collapsed, hidden, .. }| { shell, columns, collapsed, hidden }

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
				listed: { sessions: [], workspaces: { projects: [], workspaces: [] } },
				editing: [],
				timelines: [],
				focus: Session(""),
				workspaces: { projects: [], workspaces: [] },
				shell: Tiling,
				columns: [],
				collapsed: [],
				hidden: [],
				active_column: "",
				jump: { serial: 0, panel: "", replace: "", push: "" },
				url_hash: "",
				next_id: 1,
				drafts: [],
				drafts_rewritten: { pane: "", count: 0 },
				coarse_pointer: Bool.False,
				outbox: { serial: 0, request: ListSessions },
				sent: [],
				attention: [],
				attending: [],
				attention_outbox: { serial: 0, request: ListItems },
				poll: { serial: 0, subjects: [], topics: [] },
				polling: Bool.False,
				poll_again: Bool.False,
				cursors: [],
				notice: "",
				show_settings: Bool.False,
				keys_typed: { keys: [], serial: 0 },
				snapshot_text: "",
				presets: Default.setup.presets,
				kept_layout: restored.is_ok(),
				git: [],
				git_changes: [],
				git_hunks: [],
				git_panes: [],
				trees: [],
				texts: [],
				file_panes: [],
				reviews: [],
				reviewing: [],
				composer: Model.closed_composer,
				rooms: [],
				room_members: [],
				room_logs: [],
				room_panes: [],
				room_asks: [],
				themes: Default.setup.themes,
				default_theme: Default.setup.default_theme,
				theme: restored.map_ok(|loaded| loaded.theme) ?? "",
				glass: Bool.True,
				wallpaper: { url: "", dim: ThemeDim },
				focused_pane: "",
				menu: "",
				renaming: Model.not_renaming,
				now: 0,
				copied: "",
				clipboard: { serial: 0, key: "", text: "" },
				jumps: [],
				windows: [],
				opened_folds: [],
				voice: Speech.initial,
				form: Model.closed_form,
				creating: [],
				call_outbox: { serial: 0, key: "", text: "" },
				agents: [],
				tickets: TicketDesk.initial,
			},
			restored.map_ok(Model.layout_of) ?? Model.developer,
		)
	}

	## Shows a layout, counting ids on from the numbers ending theirs. A
	## Workbench shows the panel the URL names first, or its main area.
	layout : State, Layout -> State
	layout = |state, { shell, columns, collapsed, hidden }| {
		ids = columns.join_map(|column| column.panes.map(|listed_pane| listed_pane.id).append(column.id))
		next_id = ids.fold(1, |next, id| U64.max(next, (U64.from_str(id.split_last("-").map_ok(|parts| parts.after) ?? "") ?? 0) + 1))
		slot = if (shell == Workbench) Model.slot_hashed(state.url_hash) else Free
		shown = columns.get([Left, Main, Right].find_first_index(|candidate| candidate == slot) ?? 0)
		jump = { serial: state.jump.serial + 1, panel: Model.panel_ref(slot), replace: "", push: "" }
		{ ..state, shell, columns, next_id, collapsed, hidden, jump, active_column: shown.map_ok(|column| column.id) ?? "" }
	}

	snapshot : State -> Snapshot
	snapshot = |state| { version: Setup.snapshot_version, shell: state.shell, columns: state.columns, collapsed: state.collapsed, hidden: state.hidden, theme: state.theme }

	## A layout as a snapshot showing the setup's default theme.
	snapshot_of : Layout -> Snapshot
	snapshot_of = |{ shell, columns, collapsed, hidden }| { version: Setup.snapshot_version, shell, columns, collapsed, hidden, theme: "" }

	## The snapshot settings show, of the layout as it is now.
	with_snapshot_text : State -> State
	with_snapshot_text = |state| { ..state, snapshot_text: Json.to_str(Model.snapshot(state)) }

	## Reads a snapshot. Before version 6, it hides no panes; before version
	## 5, it shows the setup's default theme; before version 4, panes have
	## their options' defaults and the drawers show. A version 1 or 2 one loads in Tiling, a version 1 one with a
	## column for each pane, unless it holds just the old default's widgets:
	## then it loads the Developer preset.
	restore : Str -> Try(Snapshot, [Invalid])
	restore = |text| {
		# Since version 4 a snapshot is laid out alike; version 5 names its
		# theme, and version 6 the panes it hides.
		laid : Try({ version : U32, shell : Shell, columns : List(Column), collapsed : List(Slot) }, _)
		laid = Json.parse(text)
		themed : Try({ theme : Str }, _)
		themed = Json.parse(text)
		hiding : Try({ hidden : List(Str) }, _)
		hiding = Json.parse(text)
		third : Try({ version : U32, shell : Shell, columns : List(OldColumn) }, _)
		third = Json.parse(text)
		second : Try({ version : U32, columns : List(OldColumn) }, _)
		second = Json.parse(text)
		first : Try({ version : U32, panes : List(OldPane) }, _)
		first = Json.parse(text)
		laid_out = |shell, columns| shell == Tiling or columns.len() == 3
		match (laid, third, second, first) {
			(Ok({ version, shell, columns, collapsed }), _, _, _) if version >= 4 and version <= 6 and laid_out(shell, columns) => Ok({ ..Model.snapshot_of({ shell, columns, collapsed, hidden: if (version == 6) hiding.map_ok(|saved| saved.hidden) ?? [] else [] }), theme: if (version >= 5) themed.map_ok(|saved| saved.theme) ?? "" else "" })
			(_, Ok({ version: 3, shell, columns }), _, _) if laid_out(shell, columns) => Ok(Model.snapshot_of({ shell, columns: Model.with_options(columns), collapsed: [], hidden: [] }))
			(_, _, Ok({ version: 2, columns }), _) => Ok(Model.snapshot_of(Model.migrated(Model.with_options(columns))))
			(_, _, _, Ok({ version: 1, panes: listed_panes })) => Ok(Model.snapshot_of(Model.migrated(Model.with_options(listed_panes.map_with_index(|listed_pane, index| { id: "column-${(index + 1).to_str()}", size: 1, tabbed: Bool.False, active: listed_pane.id, panes: [listed_pane] })))))
			_ => Err(Invalid)
		}
	}

	with_options : List(OldColumn) -> List(Column)
	with_options = |columns| columns.map(|{ id, size, tabbed, active, panes: column_panes }| { id, size, tabbed, active, panes: column_panes.map(|listed_pane| { id: listed_pane.id, widget: listed_pane.widget, pinned: listed_pane.pinned, options: [] }) })

	migrated : List(Column) -> Layout
	migrated = |columns|
		if (columns.map(|column| column.panes.map(|listed_pane| listed_pane.widget)) == [["sessions"], ["chat"], ["capabilities"]]) Model.developer else { shell: Tiling, columns, collapsed: [], hidden: [] }

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
			Ok(preset) => { ..Model.use_preset({ ..state, presets: offered.presets }, preset.name), kept_layout: Bool.True }
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

	## Marks the pane clicked or focused in, and shows its column on a narrow
	## screen. Another pane's menu, or one of its rows', closes.
	focus_pane : State, { pane : Str, column : Str } -> State
	focus_pane = |state, { pane: pane_id, column }| { ..state, focused_pane: pane_id, active_column: column, menu: if (state.menu == pane_id or state.menu.starts_with("${pane_id} ")) state.menu else "" }

	toggle_menu : State, Str -> State
	toggle_menu = |state, pane_id| { ..state, menu: if (state.menu == pane_id) "" else pane_id }

	## What names a row's ⋮ menu in `menu`.
	row_menu_key : { pane_id : Str, key : Str } -> Str
	row_menu_key = |{ pane_id, key }| "${pane_id} ${key}"

	## What a row's ⋮ menu offers: on a project, a new workspace of it and
	## renaming it; on a workspace, a new agent there, and renaming, pinning
	## or unpinning and archiving it; on a session, a new agent beside it,
	## stopping it while it works, marking it read or unread unless it works,
	## renaming it, pinning or unpinning its workspace, copying its id and
	## archiving it. Each edit is offered where its capability is.
	RowAction : [NewWorkspace, NewAgent, Stop, MarkRead, MarkUnread, Rename, Pin, CopyId, Archive]

	row_menu : State, Str -> List({ label : Str, action : RowAction })
	row_menu = |state, key| {
		offered = |capability, items| if (state.capabilities.contains(capability)) items else []
		pin = Model.row_workspace(state, key).map_ok(|workspace| offered(Capability.workspaces_v1, [{ label: if (workspace.pinned) "Unpin" else "Pin", action: Pin }])) ?? []
		rename = |capability| offered(capability, [{ label: "Rename", action: Rename }])
		match Context.from_str(key) {
			_ if key.starts_with("group:") => if (state.workspaces.projects.any(|project| "group:${project.id}" == key)) [{ label: "New workspace", action: NewWorkspace }].concat(rename(Capability.workspaces_v1)) else []
			Ok(Workspace(_)) => [{ label: "New agent", action: NewAgent }].concat(rename(Capability.workspaces_v1)).concat(pin).concat(offered(Capability.workspaces_v1, [{ label: "Archive", action: Archive }]))
			Ok(Session(session_id)) if !Model.starting(state, session_id) => {
				listed_session = Model.session(state, session_id)
				read = state.attention.find_first(|item| item.session_id == session_id and item.state != Working).map_ok(|_| if (Model.unread(state, session_id)) [{ label: "Mark read", action: MarkRead }] else [{ label: "Mark unread", action: MarkUnread }]) ?? []
				(if (Model.row_workspace(state, key).is_ok()) [{ label: "New agent beside it", action: NewAgent }] else [])
					.concat(if (Model.busy(listed_session.status)) [{ label: "Stop agent", action: Stop }] else [])
					.concat(read)
					.concat(rename(Capability.chat_v1))
					.concat(pin)
					.append({ label: "Copy id", action: CopyId })
					.concat(offered(Capability.chat_v1, [{ label: "Archive", action: Archive }]))
			}
			_ => []
		}
	}

	## The workspace a row names, or the one its session works in.
	row_workspace : State, Str -> Try(Workspaces.Workspace, [NotFound])
	row_workspace = |state, key| state.workspaces.workspaces.find_first(|workspace| Context.to_str(Workspace(workspace.id)) == key or workspace.session_ids.contains(key))

	## Does what a row's ⋮ menu offers, and closes it.
	row_act : State, { pane_id : Str, key : Str, action : RowAction } -> State
	row_act = |state0, { pane_id, key, action }| {
		state = { ..state0, menu: "" }
		match action {
			NewWorkspace | NewAgent => Model.open_form(state, { pane_id, key })
			Stop => Model.stop_session(state, key)
			MarkRead => Model.mark_seen(state, [key], Bool.True)
			MarkUnread => Model.mark_seen(state, [key], Bool.False)
			CopyId => Model.copy(state, { key: "id:${key}", text: key })
			Rename => { ..state, renaming: { pane: pane_id, key, text: Model.row_name(state, key) }, jump: { serial: state.jump.serial + 1, panel: "rename", replace: "", push: "" } }
			Pin => Model.row_workspace(state, key).map_ok(|workspace| Model.edit(state, Workspaces(Pin({ workspace_id: workspace.id, pinned: !workspace.pinned })))) ?? state
			Archive =>
				match Context.from_str(key) {
					Ok(Workspace(workspace_id)) => Model.edit(state, Workspaces(Archive({ workspace_id: workspace_id })))
					Ok(Session(session_id)) => Model.edit(state, Chat(Archive({ session_id: session_id })))
					Err(_) => state
				}
		}
	}

	not_renaming : { pane : Str, key : Str, text : Str }
	not_renaming = { pane: "", key: "", text: "" }

	## The name of the project, workspace or session a row names, as its
	## provider has it.
	row_name : State, Str -> Str
	row_name = |state, key|
		match Context.from_str(key) {
			_ if key.starts_with("group:") => state.workspaces.projects.find_first(|project| "group:${project.id}" == key).map_ok(|project| project.name) ?? ""
			Ok(Workspace(workspace_id)) => state.workspaces.workspaces.find_first(|workspace| workspace.id == workspace_id).map_ok(|workspace| workspace.name) ?? ""
			Ok(Session(session_id)) => Model.session(state, session_id).title
			Err(_) => ""
		}

	## Renames the row being renamed to the name typed, shown at once, unless
	## it is empty or the same.
	rename_row : State -> State
	rename_row = |state0| {
		{ key, text, .. } = state0.renaming
		state = { ..state0, renaming: Model.not_renaming }
		name = text.trim()
		match Context.from_str(key) {
			_ if name.is_empty() or name == Model.row_name(state, key) => state
			_ if key.starts_with("group:") => Model.edit(state, Workspaces(RenameProject({ project_id: key.drop_prefix("group:"), name })))
			Ok(Workspace(workspace_id)) => Model.edit(state, Workspaces(Rename({ workspace_id, name })))
			Ok(Session(session_id)) => Model.edit(state, Chat(Rename({ session_id, title: name })))
			Err(_) => state
		}
	}

	## Sends a rename, pin or archive, shown at once.
	edit : State, Edit -> State
	edit = |state, change| {
		serial = state.call_outbox.serial + 1
		text = match change {
			Chat(request) => Json.to_str({ capability: "chat.v1", request })
			Workspaces(request) => Json.to_str({ capability: "workspaces.v1", request })
		}
		Model.relisted({ ..state, editing: state.editing.append({ serial, edit: change, accepted: 0 }), call_outbox: { serial, key: "edit", text }, notice: "" })
	}

	## Takes the daemon's answer to an edit: accepted, it holds until the
	## poll it asks for shows it; refused, it is undone, with why.
	edit_answered : State, U64, Str -> State
	edit_answered = |state, serial, text| {
		answered : Try(Protocol.Answer([Accepted, Rejected(Str)]), _)
		answered = Json.parse(text)
		undone = |reason| Model.relisted({ ..state, editing: state.editing.drop_if(|asked| asked.serial == serial), notice: reason })
		match answered {
			Ok(Ok(Accepted)) => Model.poll({ ..state, editing: state.editing.map(|asked| if (asked.serial == serial) { ..asked, accepted: state.poll.serial + 1 } else asked) })
			Ok(Ok(Rejected(reason))) => undone(reason)
			Ok(Err({ message, .. })) => undone(message)
			Err(_) => undone("The daemon did not answer.")
		}
	}

	## The sessions and workspaces as the daemon last listed them, with the
	## edits on their way applied.
	relisted : State -> State
	relisted = |state| state.editing.fold({ ..state, sessions: state.listed.sessions, workspaces: state.listed.workspaces }, |shown, asked| Model.edited(shown, asked.edit))

	## The listings as an edit leaves them: renamed, pinned, or without what
	## it archived.
	edited : State, Edit -> State
	edited = |state, change| {
		listed = state.workspaces
		each_workspace = |change_one| { ..state, workspaces: { ..listed, workspaces: listed.workspaces.map(change_one) } }
		match change {
			Chat(Rename({ session_id, title })) => { ..state, sessions: state.sessions.map(|listed_session| if (listed_session.id == session_id) { ..listed_session, title } else listed_session) }
			Workspaces(Rename({ workspace_id, name })) => each_workspace(|workspace| if (workspace.id == workspace_id) { ..workspace, name } else workspace)
			Workspaces(RenameProject({ project_id, name })) => { ..state, workspaces: { ..listed, projects: listed.projects.map(|project| if (project.id == project_id) { ..project, name } else project) } }
			Chat(Archive({ session_id })) => { ..each_workspace(|workspace| { ..workspace, session_ids: workspace.session_ids.drop_if(|id| id == session_id) }), sessions: state.sessions.drop_if(|listed_session| listed_session.id == session_id) }
			Workspaces(Pin({ workspace_id, pinned })) => each_workspace(|workspace| if (workspace.id == workspace_id) { ..workspace, pinned } else workspace)
			Workspaces(Archive({ workspace_id })) => { ..state, workspaces: { ..listed, workspaces: listed.workspaces.drop_if(|workspace| workspace.id == workspace_id) } }
			_ => state
		}
	}

	## Copies a code block, shown as copied at once.
	copy : State, { key : Str, text : Str } -> State
	copy = |state, { key, text }| { ..state, copied: key, clipboard: { serial: state.clipboard.serial + 1, key, text } }

	## Takes the clipboard's answer: refused, the block isn't copied after all.
	copy_answered : State, U64, Bool -> State
	copy_answered = |state, serial, copied| if (copied or serial != state.clipboard.serial) state else { ..state, copied: "", notice: "The browser didn't let liton copy that." }

	jumps_of : State, Str -> U64
	jumps_of = |state, pane_id| state.jumps.find_first(|jumped| jumped.pane == pane_id).map_ok(|jumped| jumped.count) ?? 0

	## Scrolls a chat pane's timeline to its latest entry, and shows only
	## the latest of it again.
	jump_to_latest : State, Str -> State
	jump_to_latest = |state, pane_id| { ..state, jumps: state.jumps.drop_if(|jumped| jumped.pane == pane_id).append({ pane: pane_id, count: Model.jumps_of(state, pane_id) + 1 }), windows: state.windows.drop_if(|shown| shown.pane == pane_id) }

	## How many of a timeline's latest entries a chat pane shows at first;
	## `Model.show_earlier` adds half as many, few enough to draw while
	## scrolling. Each change of the state refreshes what a pane shows, so a
	## whole long timeline would make every click slow.
	window : U64
	window = 50

	## How many of its session's latest entries a chat pane shows.
	window_of : State, Pane -> U64
	window_of = |state, shown| {
		session_id = Model.session_of(state, shown)
		state.windows.find_first(|kept| kept.pane == shown.id and kept.session_id == session_id).map_ok(|kept| kept.count) ?? Model.window
	}

	## Whether a chat pane leaves out earlier entries of its timeline.
	has_earlier : State, Pane -> Bool
	has_earlier = |state, shown| Model.entries(state, Model.session_of(state, shown)).len() > Model.window_of(state, shown)

	## Shows half of `Model.window` more of a chat pane's earlier entries.
	show_earlier : State, Str -> State
	show_earlier = |state, pane_id| {
		shown = Model.pane(state, pane_id)
		{ ..state, windows: state.windows.drop_if(|kept| kept.pane == pane_id).append({ pane: pane_id, session_id: Model.session_of(state, shown), count: Model.window_of(state, shown) + Model.window // 2 }) }
	}

	## How many sessions are running.
	running : State -> U64
	running = |state| state.sessions.keep_if(|listed_session| listed_session.status == Running).len()

	## Whether the layout is the preset's, as it was loaded.
	preset_shown : State, Str -> Bool
	preset_shown = |state, name| state.presets.any(|preset| preset.name == name and Model.layout_of(preset.snapshot) == { shell: state.shell, columns: state.columns, collapsed: state.collapsed, hidden: state.hidden })

	## Every pane, column by column.
	panes : State -> List(Pane)
	panes = |state| state.columns.join_map(|column| column.panes)

	## A new pane of `widget`, focused, its column shown on a narrow screen: a
	## tab in a Workbench's main area, or a column of its own at the end in
	## Tiling. A Changes diff the main area showed goes back to its pane, so
	## the new tab shows its widget.
	add_pane : State, Str -> State
	add_pane = |state, widget| {
		added = { id: "added-${state.next_id.to_str()}", widget, pinned: "", options: [] }
		column = { id: "column-${(state.next_id + 1).to_str()}", size: 1, tabbed: Bool.False, active: added.id, panes: [added] }
		(columns, next_id, shown) =
			if (state.shell == Workbench)
				(state.columns.map_with_index(|main, index| if (index == 1) { ..main, active: added.id, panes: main.panes.append(added) } else main), state.next_id + 1, state.columns.get(1).map_ok(|main| main.id) ?? "")
			else
				(state.columns.append(column), state.next_id + 2, column.id)
		Model.show_column({ ..state, columns, next_id, focused_pane: added.id, git_panes: state.git_panes.map(|followed| { ..followed, in_main: Bool.False }) }, shown)
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
	## shows it and the slot's drawer.
	move_to_slot : State, Str, Slot -> State
	move_to_slot = |state, id, slot| Model.place(state, id, { column: state.columns.get([Left, Main, Right].find_first_index(|candidate| candidate == slot) ?? 3).map_ok(|column| column.id) ?? "", at: End })

	## Where a pane goes: into column `column` at its end or beside one of its
	## panes, or into a new column on either side of it. "" is nowhere.
	Place : { column : Str, at : [End, Before(Str), After(Str), NewLeft, NewRight] }

	nowhere : Place
	nowhere = { column: "", at: End }

	## Moves a pane to `place` as its column's active tab, showing it and its
	## slot's drawer. In Tiling, the narrow screen shows its column.
	place : State, Str, Place -> State
	place = |state, id, { column: to, at }| {
		moved = Model.pane(state, id)
		left_behind = state.columns.map(|column| { ..column, panes: column.panes.drop_if(|listed_pane| listed_pane.id == id) })
		added = { id: "column-${state.next_id.to_str()}", size: 1, tabbed: Bool.False, active: id, panes: [moved] }
		inserted = |listed_panes, beside, after| {
			index = (listed_panes.find_first_index(|listed_pane| listed_pane.id == beside) ?? listed_panes.len()) + (if (after) 1 else 0)
			listed_panes.take_first(index).append(moved).concat(listed_panes.drop_first(index))
		}
		columns = left_behind.join_map(
			|column|
				match at {
					_ if column.id != to => [column]
					NewLeft => [added, column]
					NewRight => [column, added]
					Before(beside) => [{ ..column, active: id, panes: inserted(column.panes, beside, Bool.False) }]
					After(beside) => [{ ..column, active: id, panes: inserted(column.panes, beside, Bool.True) }]
					End => [{ ..column, active: id, panes: column.panes.append(moved) }]
				},
		)
		new_column = at == NewLeft or at == NewRight
		shown = if (new_column) added.id else to
		slot = Model.slot_of(state, to)
		if (!state.columns.any(|column| column.id == to))
			state
		else
			Model.drop_empty_columns({ ..state, columns, next_id: if (new_column) state.next_id + 1 else state.next_id, active_column: if (state.shell == Tiling) shown else state.active_column, collapsed: state.collapsed.drop_if(|hidden| hidden == slot), hidden: state.hidden.drop_if(|hidden_id| hidden_id == id) })
	}

	## Where dropping pane `id` places it, nowhere unless it moves it: a
	## Workbench's slot must fit its widget, and Tiling's new column must not
	## hold it alone already.
	drop_place : State, Str, Place -> Place
	drop_place = |state, id, wanted| {
		from = state.columns.find_first(|column| column.panes.any(|listed_pane| listed_pane.id == id)).map_ok(|column| column.id) ?? ""
		alone = state.columns.any(|column| column.id == from and column.panes.len() == 1)
		fits = Widgets.fits(Widgets.find(Model.pane(state, id).widget), Model.slot_of(state, wanted.column))
		allowed =
			match wanted.at {
				_ if from.is_empty() or !fits or !state.columns.any(|column| column.id == wanted.column) => Bool.False
				Before(beside) | After(beside) => beside != id
				End => wanted.column != from
				NewLeft | NewRight => state.shell == Tiling and !(alone and wanted.column == from)
			}
		if (allowed) wanted else Model.nowhere
	}

	## The value of a pane's option `key`, or its widget's default.
	option : Pane, Str -> Str
	option = |shown, key| Widgets.value(Widgets.find(shown.widget), shown.options, key)

	set_option : State, Str, Str, Str -> State
	set_option = |state, id, key, value| {
		set = |listed_pane| if (listed_pane.id == id) { ..listed_pane, options: listed_pane.options.drop_if(|old| old.key == key).append({ key, value }) } else listed_pane
		{ ..state, columns: state.columns.map(|column| { ..column, panes: column.panes.map(set) }) }
	}

	## The focus reference of a Workbench slot's panel, which focusing scrolls
	## into view.
	panel_ref : Slot -> Str
	panel_ref = |slot| if (slot == Free) "" else "panel-${Model.slot_name(slot)}"

	## Shows a column on a narrow screen, scrolling a Workbench to its panel,
	## whose hash then replaces the URL's.
	show_column : State, Str -> State
	show_column = |state, column_id| Model.jump_to(state, column_id, Replace)

	## Shows a column as `show_column` does. `Push` leaves the panel the user
	## is in as an entry of the browser's history, so back returns to it,
	## unless the URL names the panel shown already.
	jump_to : State, Str, [Replace, Push] -> State
	jump_to = |state, column_id, how| {
		(from, to) = (Model.slot_hash(Model.slot_of(state, state.active_column)), Model.slot_hash(Model.slot_of(state, column_id)))
		(replace, push) = match how {
			Replace if to != state.url_hash => (to, "")
			Push if to != state.url_hash and from != to => (from, to)
			_ => ("", "")
		}
		jump = { serial: state.jump.serial + 1, panel: Model.panel_ref(Model.slot_of(state, column_id)), replace, push }
		if (to.is_empty()) { ..state, active_column: column_id } else { ..state, active_column: column_id, jump, url_hash: to }
	}

	## The URL hash naming a Workbench slot's panel, and the slot a hash
	## names: the main area for none.
	slot_hash : Slot -> Str
	slot_hash = |slot| if (slot == Free) "" else "#${Model.slot_name(slot)}"

	slot_hashed : Str -> Slot
	slot_hashed = |hash| [Left, Right].find_first(|slot| Model.slot_hash(slot) == hash) ?? Main

	## Follows the browser to `url`, by its back or forward or on loading the
	## page: a Workbench shows the panel its hash names.
	went : State, Str -> State
	went = |state0, url| {
		state = { ..state0, url_hash: url.split_last("#").map_ok(|parts| "#${parts.after}") ?? "" }
		if (state.shell == Workbench) Model.layout(state, { shell: Workbench, columns: state.columns, collapsed: state.collapsed, hidden: state.hidden }) else state
	}

	toggle_drawer : State, Slot -> State
	toggle_drawer = |state, drawer| { ..state, collapsed: if (state.collapsed.contains(drawer)) state.collapsed.drop_if(|slot| slot == drawer) else state.collapsed.append(drawer) }

	close_pane : State, Str -> State
	close_pane = |state, id| Model.drop_empty_columns({ ..state, columns: state.columns.map(|column| { ..column, panes: column.panes.drop_if(|listed_pane| listed_pane.id == id) }), hidden: state.hidden.drop_if(|hidden_id| hidden_id == id) })

	## A tab's ×: in a Workbench it hides the pane, in Tiling it closes it.
	close_tab : State, Str -> State
	close_tab = |state, id| if (state.shell == Workbench) Model.hide_pane(state, id) else Model.close_pane(state, id)

	## A column's panes a Workbench doesn't hide.
	shown_panes : State, Column -> List(Pane)
	shown_panes = |state, column| column.panes.drop_if(|listed_pane| state.hidden.contains(listed_pane.id))

	## The panes hidden in the column of pane `id`, which its ⋯ menu shows again.
	hidden_beside : State, Str -> List(Pane)
	hidden_beside = |state, id| state.columns.find_first(|column| column.panes.any(|listed_pane| listed_pane.id == id)).map_ok(|column| column.panes.keep_if(|listed_pane| state.hidden.contains(listed_pane.id))) ?? []

	## What hiding a Workbench pane hides, as its ⋯ menu names it: the pane,
	## while its column shows another, else its drawer. The main area's last
	## pane, and Tiling's, don't hide: "".
	hide_label : State, Str -> Str
	hide_label = |state, id|
		match state.columns.find_first(|column| column.panes.any(|listed_pane| listed_pane.id == id)) {
			Ok(column) if state.shell == Workbench => {
				slot = Model.slot_of(state, column.id)
				if (Model.shown_panes(state, column).len() > 1) "Hide ${Widgets.find(Model.pane(state, id).widget).title}" else if (slot == Left or slot == Right) "Hide ${Model.slot_name(slot)} drawer" else ""
			}
			_ => ""
		}

	## Hides a Workbench pane as `hide_label` names it, its column showing,
	## and focusing in its place, the next it shows.
	hide_pane : State, Str -> State
	hide_pane = |state, id|
		match state.columns.find_first(|column| column.panes.any(|listed_pane| listed_pane.id == id)) {
			Ok(column) if state.shell == Workbench => {
				slot = Model.slot_of(state, column.id)
				match Model.shown_panes(state, column).find_first(|listed_pane| listed_pane.id != id) {
					Ok(next) => Model.change_column({ ..state, hidden: state.hidden.append(id), focused_pane: if (state.focused_pane == id) next.id else state.focused_pane }, column.id, |holding| if (holding.active == id) { ..holding, active: next.id } else holding)
					Err(NotFound) if slot == Left or slot == Right => { ..state, collapsed: state.collapsed.append(slot) }
					Err(NotFound) => state
				}
			}
			_ => state
		}

	## Shows a hidden pane again, as its column's active tab, focused.
	show_pane : State, Str -> State
	show_pane = |state, id| Model.activate_tab({ ..state, hidden: state.hidden.drop_if(|hidden_id| hidden_id == id), focused_pane: id }, id)

	## Drops columns left without panes, apart from a Workbench's slots, and
	## points a tab group or the narrow screen that showed what is gone at what
	## is left and shown.
	drop_empty_columns : State -> State
	drop_empty_columns = |state| {
		columns =
			state.columns
				.drop_if(|column| column.panes.is_empty() and state.shell == Tiling)
				.map(|column| if (column.panes.any(|listed_pane| listed_pane.id == column.active)) column else { ..column, active: Model.shown_panes(state, column).first().map_ok(|listed_pane| listed_pane.id) ?? "" })
		active_column = if (columns.any(|column| column.id == state.active_column)) state.active_column else columns.first().map_ok(|column| column.id) ?? ""
		{ ..state, columns, active_column }
	}

	## Moves a pane into the next column over. Past the edge it gets a column of
	## its own, unless it is already alone there.
	move_pane : State, Str, [Left, Right] -> State
	move_pane = |state, id, direction|
		match state.columns.find_first_index(|column| column.panes.any(|listed_pane| listed_pane.id == id)) {
			Err(NotFound) => state
			Ok(from) => {
				at_edge = if (direction == Left) from == 0 else from + 1 == state.columns.len()
				alone = (state.columns.get(from).map_ok(|column| column.panes.len()) ?? 0) == 1
				beside = state.columns.get(if (at_edge) from else if (direction == Left) from - 1 else from + 1).map_ok(|column| column.id) ?? ""
				if (at_edge and alone) state else Model.place(state, id, { column: beside, at: if (!at_edge) End else if (direction == Left) NewLeft else NewRight })
			}
		}

	## Where a pane's ⋯ menu moves it, each named: in a Workbench, the other
	## slots its widget fits; in Tiling, into the column beside it each way,
	## or past the edge into a new one unless it is alone there.
	moves : State, Str -> List({ label : Str, move : [ToSlot(Slot), Beside([Left, Right])] })
	moves = |state, id|
		match state.columns.find_first_index(|column| column.panes.any(|listed_pane| listed_pane.id == id)) {
			Ok(from) if state.shell == Workbench => {
				at = state.columns.get(from).map_ok(|column| Model.slot_of(state, column.id)) ?? Free
				[Left, Main, Right].keep_if(|to| to != at and Widgets.fits(Widgets.find(Model.pane(state, id).widget), to)).map(|to| { label: "Move to ${if (to == Main) "main area" else "${Model.slot_name(to)} drawer"}", move: ToSlot(to) })
			}
			Ok(from) => {
				alone = (state.columns.get(from).map_ok(|column| column.panes.len()) ?? 0) == 1
				[(Left, "left", from == 0), (Right, "right", from + 1 == state.columns.len())]
					.drop_if(|(_, _, at_edge)| at_edge and alone)
					.map(|(side, name, at_edge)| { label: if (at_edge) "Move to a new column on the ${name}" else "Move to the column on the ${name}", move: Beside(side) })
			}
			Err(NotFound) => []
		}

	## Moves a pane where its ⋯ menu's move `label` names.
	move : State, { pane_id : Str, label : Str } -> State
	move = |state, { pane_id, label }|
		match Model.moves(state, pane_id).find_first(|offered| offered.label == label) {
			Ok({ move: ToSlot(slot), .. }) => Model.move_to_slot(state, pane_id, slot)
			Ok({ move: Beside(side), .. }) => Model.move_pane(state, pane_id, side)
			Err(NotFound) => state
		}

	change_column : State, Str, (Column -> Column) -> State
	change_column = |state, column_id, change| { ..state, columns: state.columns.map(|column| if (column.id == column_id) change(column) else column) }

	## Switches the column of pane `id` between a stack and tabs.
	toggle_tabs : State, Str -> State
	toggle_tabs = |state, id| { ..state, columns: state.columns.map(|column| if (column.panes.any(|listed_pane| listed_pane.id == id)) { ..column, tabbed: !column.tabbed } else column) }

	resize : State, Str, [Narrower, Wider] -> State
	resize = |state, column_id, change| Model.change_column(state, column_id, |column| { ..column, size: if (change == Wider) column.size + 1 else if (column.size > 1) column.size - 1 else 1 })

	## Shows a pane in its tab group.
	activate_tab : State, Str -> State
	activate_tab = |state, id| { ..state, columns: state.columns.map(|column| if (column.panes.any(|listed_pane| listed_pane.id == id)) { ..column, active: id } else column) }

	## Pins a following pane to the focused context, or lets a pinned one follow.
	toggle_pin : State, Str -> State
	toggle_pin = |state, id| {
		pin = |listed_pane| if (listed_pane.id != id) listed_pane else if (listed_pane.pinned.is_empty()) { ..listed_pane, pinned: Context.to_str(state.focus) } else { ..listed_pane, pinned: "" }
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
				placed = Model.workspace_sessions(state, workspace_id).map(|listed_session| (listed_session.id, Attention.item(listed_session, []).state))
				Attention.ranks.keep_oks(|rank| placed.find_first(|(_, state_of)| state_of == rank)).first().map_ok(|(session_id, _)| session_id) ?? ""
			}
		}

	## The sessions that work in a workspace, as they say or its listing does.
	workspace_sessions : State, Str -> List(Chat.Session)
	workspace_sessions = |state, workspace_id| {
		listed = state.workspaces.workspaces.find_first(|shown| shown.id == workspace_id).map_ok(|shown| shown.session_ids) ?? []
		state.sessions.keep_if(|listed_session| listed.contains(listed_session.id) or (listed_session.workspace.map_ok(|placed| placed.id == Ok(workspace_id)) ?? Bool.False))
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

	Shown : { sequence : U64, event : Chat.Event, card : Try(ToolCard, [NotTool]), fold : Try(Fold, [NotFold]) }

	## One line standing for entries folded under it, which opening it shows
	## after it: what they did, and whether a tool call among them runs or
	## failed. Its key names its session and its first entry.
	Fold : { key : Str, summary : Str, state : [Running, Done, Failed], open : Bool }

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
						Ok({ sequence, event, card: Ok({ tool, input, state, output: Str.join_with(lines.take_first(4), "\n"), folded: Str.join_with(lines.drop_first(4), "\n") }), fold: Err(NotFold) })
					}
					_ => Ok({ sequence, event, card: Err(NotTool), fold: Err(NotFold) })
				},
		)
	}

	## A chat pane's entries, the latest its window holds, as its options
	## show them: tool output in full, folded or hidden; status lines or not;
	## and folded as Collapse says: nothing, tool calls in a row, or those
	## and finished turns. A result before the window is its call's, before
	## it too. A turn's end shows how long it worked, if its provider tells.
	chat_entries : State, Pane -> List(Shown)
	chat_entries = |state, shown| {
		status = |entry|
			match entry.event {
				StatusChanged(_) => Bool.True
				_ => Bool.False
			}
		untimed = |entry|
			match entry.event {
				TurnEnded({ started: Err(Missing), .. }) => Bool.True
				_ => Bool.False
			}
		card = |tool|
			match Model.option(shown, "tool_output") {
				"Full" => { ..tool, output: if (tool.folded.is_empty()) tool.output else "${tool.output}\n${tool.folded}", folded: "" }
				"Hidden" => { ..tool, output: "", folded: "" }
				_ => tool
			}
		session_id = Model.session_of(state, shown)
		timeline = Model.entries(state, session_id)
		count = Model.window_of(state, shown)
		opened = state.opened_folds.keep_if(|fold| fold.pane == shown.id).map(|fold| fold.key)
		listed = Model.with_tool_cards(if (timeline.len() > count) timeline.drop_first(timeline.len() - count) else timeline)
			.drop_if(|entry| Model.option(shown, "show_status") == "false" and status(entry))
			.map(|entry| { ..entry, card: entry.card.map_ok(card) })
		session_running = [Running, AwaitingPermission].contains(Model.session(state, session_id).status)
		folded = match Model.option(shown, "collapse") {
			"Full" => listed
			"Turns" => Model.tools_folded(Model.turns_folded(listed, session_id, opened, session_running), session_id, opened)
			_ => Model.tools_folded(listed, session_id, opened)
		}
		folded.drop_if(untimed)
	}

	## "Worked for 2m 14s", from when a turn started to when it ended, or ""
	## if either isn't a time.
	worked : Str, Str -> Str
	worked = |started, ended|
		match (epoch_ms(started), epoch_ms(ended)) {
			(Ok(from), Ok(to)) if to >= from => "Worked for ${Model.duration_text(to - from)}"
			_ => ""
		}

	## Each finished turn's work under one fold, between its message and the
	## agent's last reply, shown only once it is `opened`. A turn starts with
	## a message of the user's and ends at its `TurnEnded`, or, where its
	## provider marks none, once another message follows, the last once
	## `session_running` is false; entries before the first message are a
	## turn begun earlier.
	turns_folded : List(Shown), Str, List(Str), Bool -> List(Shown)
	turns_folded = |listed, session_id, opened, session_running| {
		is_user = |entry|
			match entry.event {
				UserMessage(_) => Bool.True
				_ => Bool.False
			}
		is_reply = |entry|
			match entry.event {
				AgentMessage(_) => Bool.True
				_ => Bool.False
			}
		is_end = |entry|
			match entry.event {
				TurnEnded(_) => Bool.True
				_ => Bool.False
			}
		under_fold = |rows, whole_turn, finished| {
			(turn, ending) = match whole_turn {
				[.. as rest, last] if is_end(last) => (rest, [last])
				_ => (whole_turn, [])
			}
			(asked, after_message) = match turn {
				[first, .. as rest] if is_user(first) => ([first], rest)
				_ => ([], turn)
			}
			reply = after_message.find_last(is_reply).map_ok(|entry| [entry]) ?? []
			work = after_message.drop_if(|entry| reply.contains(entry))
			cards = work.keep_oks(|entry| entry.card)
			messages = work.keep_if(is_reply).len()
			match work {
				[first, ..] if finished and (!cards.is_empty() or messages > 0) => {
					key = "${session_id}/turn/${first.sequence.to_str()}"
					summary = Str.join_with([Model.how_many(cards.len(), "tool call"), Model.how_many(messages, "message")].drop_if(Str.is_empty), ", ")
					state = if (cards.any(|tool| tool.state == Failed)) Failed else Done
					fold = { key, summary, state, open: opened.contains(key) }
					rows.concat(asked).append({ ..first, card: Err(NotTool), fold: Ok(fold) }).concat(if (fold.open) work else []).concat(reply).concat(ending)
				}
				_ => rows.concat(whole_turn)
			}
		}
		walked = listed.fold(
			{ rows: [], turn: [] },
			|so_far, entry|
				if is_user(entry) {
					{ rows: under_fold(so_far.rows, so_far.turn, Bool.True), turn: [entry] }
				} else if is_end(entry) {
					{ rows: under_fold(so_far.rows, so_far.turn.append(entry), Bool.True), turn: [] }
				} else {
					{ ..so_far, turn: so_far.turn.append(entry) }
				},
		)
		under_fold(walked.rows, walked.turn, !session_running)
	}

	## "3 tool calls", "1 message", or "" for none.
	how_many : U64, Str -> Str
	how_many = |count, thing| if (count == 0) "" else if (count == 1) "1 ${thing}" else "${count.to_str()} ${thing}s"

	## Runs of two or more tool calls, each under one fold, shown only once
	## it is `opened`.
	tools_folded : List(Shown), Str, List(Str) -> List(Shown)
	tools_folded = |listed, session_id, opened| {
		under_fold = |rows, run|
			match run {
				[first, _, ..] => {
					cards = run.keep_oks(|entry| entry.card)
					key = "${session_id}/tools/${first.sequence.to_str()}"
					names = cards.map(|tool| tool.tool).fold([], |found, name| if (found.contains(name)) found else found.append(name))
					state = if (cards.any(|tool| tool.state == Running)) Running else if (cards.any(|tool| tool.state == Failed)) Failed else Done
					fold = { key, summary: "${run.len().to_str()} tool calls: ${Str.join_with(names, ", ")}", state, open: opened.contains(key) }
					rows.append({ ..first, card: Err(NotTool), fold: Ok(fold) }).concat(if (fold.open) run else [])
				}
				_ => rows.concat(run)
			}
		walked = listed.fold({ rows: [], run: [] }, |so_far, entry| if (entry.card.is_ok()) { ..so_far, run: so_far.run.append(entry) } else { rows: under_fold(so_far.rows, so_far.run).append(entry), run: [] })
		under_fold(walked.rows, walked.run)
	}

	## Opens a chat pane's fold, or closes it again.
	toggle_fold : State, { pane_id : Str, key : Str } -> State
	toggle_fold = |state, { pane_id, key }| {
		opened = { pane: pane_id, key }
		{ ..state, opened_folds: if (state.opened_folds.contains(opened)) state.opened_folds.drop_if(|fold| fold == opened) else state.opened_folds.append(opened) }
	}

	last_sequence : State, Str -> U64
	last_sequence = |state, session_id| Model.entries(state, session_id).last().map_ok(|entry| entry.sequence) ?? 0

	## The topics the panes follow: the sessions; the timeline of each session
	## a chat pane shows; the attention items, which the title counts; of
	## each Changes pane on screen, its scope's changes and the hunks of the
	## file it shows; of each Files pane on screen, its root, the directories
	## open and the file it shows; the workspaces, while a pane lists them;
	## the review of the context of each, Files or Changes, on screen; and
	## of Tickets panes on screen, the tickets, the links and the ticket each
	## shows. Until the manifest arrives, every capability counts as offered.
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
		# The panes of a widget on screen that show a context.
		showing = |widget| laid_out.keep_if(|shown| shown.widget == widget and (Model.pane_visible(state, shown.id) or Model.main_diff(state) == shown.id) and Model.context_of(state, shown) != Session("") and !Context.to_str(Model.context_of(state, shown)).starts_with("starting:"))
		changes = if (offered(Capability.workspace_git_v1)) showing("changes").join_map(git) else []
		files = |shown| {
			context = Model.context_of(state, shown)
			{ folders, file, .. } = Model.file_pane(state, shown.id)
			folders.prepend(".").map(|path| Tree({ context, path })).concat(if (file.is_empty()) [] else [Contents({ context, path: file })])
		}
		explored = if (offered(Capability.files_v1)) showing("files").join_map(files) else []
		# A ticket list's, its sessions' links, and the ticket each shows.
		ticket_views = laid_out.keep_if(|shown| shown.widget == "tickets" and Model.pane_visible(state, shown.id)).map(|shown| TicketDesk.view(state.tickets, shown.id))
		tickets = if (offered(Capability.tickets_v1) and !ticket_views.is_empty()) [TicketList, TicketLinks].concat(ticket_views.map(|view| view.ticket).drop_if(Str.is_empty).map(|ticket_id| TicketDetail(ticket_id))) else []
		threads = if (offered(Capability.review_v1)) showing("files").concat(showing("changes")).map(|shown| Threads(Model.context_of(state, shown))) else []
		listing = if (offered(Capability.workspaces_v1) and laid_out.any(|shown| shown.widget == "workspaces")) [WorkspaceList, Agents] else []
		# The speech engine's, for the mic in chat panes' composers, once offered.
		voice = if (state.capabilities.contains(Capability.voice_v1) and laid_out.any(|shown| shown.widget == "chat")) [VoiceStatus] else []
		# The rooms, and the messages and members of the room each Rooms pane
		# opened, and of the thread opened in it.
		room_topics = |shown| {
			{ room_id, root, .. } = Model.room_pane(state, shown.id)
			(if (room_id.is_empty()) [] else [RoomMessages(room_id), RoomMembers(room_id)]).concat(if (root.is_empty()) [] else [RoomThread({ room_id, root })])
		}
		rooms_shown = laid_out.keep_if(|shown| shown.widget == "rooms" and Model.pane_visible(state, shown.id))
		rooms = if (offered(Capability.rooms_v1) and !rooms_shown.is_empty()) rooms_shown.join_map(room_topics).prepend(RoomList) else []
		all = (if (offered(Capability.chat_v1)) [Sessions] else []).concat(timelines).concat(items).concat(changes).concat(explored).concat(listing).concat(voice).concat(threads).concat(tickets).concat(rooms)
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

	## Polls each second, unless a poll is still on its way, and takes the
	## time `at` once a new minute begins, or each second while a chat on
	## screen shows a turn running.
	tick : State, I64 -> State
	tick = |state0, at| {
		timing = Model.panes(state0).any(|shown| shown.widget == "chat" and Model.pane_visible(state0, shown.id) and Model.working(state0, shown).is_ok())
		state = if (at // 60_000 == state0.now // 60_000 and !timing) state0 else { ..state0, now: at }
		if (state.polling) state else Model.poll(state)
	}

	## Polls at once when the topics the panes follow change, or once the
	## poll on its way answers.
	follow : State -> State
	follow = |state| if (state.polling and state.poll.subjects == Model.subjects(state)) state else Model.poll(state)

	## Takes a poll's answer, each topic's in the order asked: its events and
	## cursor, the focus on the latest session until there is one. Then sends
	## the poll asked for meanwhile, if any.
	polled : State, Poll, List(Protocol.Update) -> State
	polled = |state, sent, updates| {
		answered_topics = updates.map_with_index(|update, index| (sent.subjects.get(index), update)).fold(
			state,
			|so_far, (subject, update)|
				match subject {
					Ok(followed) if Protocol.named(followed).topic == update.topic and update.error.is_err() => Model.updated(so_far, sent.serial, followed, update)
					_ => so_far
				},
		)
		edits_left = answered_topics.editing.drop_if(|asked| asked.accepted > 0 and asked.accepted <= sent.serial)
		applied = if (edits_left.len() == answered_topics.editing.len()) answered_topics else Model.relisted({ ..answered_topics, editing: edits_left })
		focus = if (applied.focus == Session("")) Session(Model.ordered(applied.sessions, "Latest", |listed_session| Model.changed(applied, listed_session), |listed_session| listed_session.title).first().map_ok(|most_recent| most_recent.id) ?? "") else applied.focus
		settled = { ..applied, focus, polling: Bool.False, poll_again: Bool.False, tickets: TicketDesk.settled(applied.tickets, sent.serial) }
		answered = { ..settled, sent: settled.sent.drop_if(|sent_request| Model.confirmed(settled, sent_request)), creating: settled.creating.drop_if(|creating| Model.made_listed(settled, creating)), room_asks: Model.posted_sent(settled).room_asks.drop_if(|asked| asked.message_id.is_empty() and asked.accepted > 0 and asked.accepted <= sent.serial) }
		if (state.poll_again) Model.poll(answered) else answered
	}

	## A poll that failed asks again with the next.
	poll_failed : State -> State
	poll_failed = |state| if (state.poll_again) Model.poll({ ..state, polling: Bool.False }) else { ..state, polling: Bool.False }

	## Takes a topic's update from the poll numbered `serial`.
	updated : State, U64, Protocol.Subject, Protocol.Update -> State
	updated = |state, serial, subject, { capability, topic, cursor, events, .. }| {
		cursors = state.cursors.drop_if(|known| known.capability == capability and known.topic == topic).append({ capability, topic, cursor })
		with_events = events.fold({ ..state, cursors }, |so_far, event| Model.received(so_far, subject, event))
		match subject {
			Timeline(session_id) if !with_events.timelines.any(|timeline| timeline.session_id == session_id) => { ..with_events, timelines: with_events.timelines.append({ session_id, entries: [] }) }
			RoomMessages(room_id) => Model.logged(with_events, room_id, "", [])
			RoomThread({ room_id, root }) => Model.logged(with_events, room_id, root, [])
			# Unchanged items still settle what was set aside.
			Items => Model.attention_fetched(with_events, serial, with_events.attention)
			# The requests its review has held since the poll they waited for.
			Threads(context) => { ..with_events, reviewing: with_events.reviewing.drop_if(|asked| asked.accepted > 0 and asked.accepted <= serial and Review.context(asked.request) == Context.to_str(context)) }
			_ => with_events
		}
	}

	## Takes a topic's event: a timeline's entries after those the UI has, or
	## a snapshot's value.
	received : State, Protocol.Subject, Protocol.Event -> State
	received = |state, subject, event|
		match (subject, event) {
			(_, Sessions(sessions)) => Model.relisted({ ..state, listed: { ..state.listed, sessions } })
			(Timeline(session_id), Entry(entry)) =>
				if (entry.sequence <= Model.last_sequence(state, session_id))
					state
				else if (state.timelines.any(|timeline| timeline.session_id == session_id))
					{ ..state, timelines: state.timelines.map(|timeline| if (timeline.session_id == session_id) { ..timeline, entries: timeline.entries.append(entry) } else timeline) }
				else
					{ ..state, timelines: state.timelines.append({ session_id, entries: [entry] }) }
			(_, Items(items)) => { ..state, attention: items }
			(_, Rooms(listed)) => { ..state, rooms: listed }
			(RoomMembers(room_id), Members(members)) => { ..state, room_members: state.room_members.drop_if(|known| known.room_id == room_id).append({ room_id, members }) }
			(RoomMessages(room_id), RoomEntry(entry)) => Model.logged(state, room_id, "", [entry])
			(RoomThread({ room_id, root }), RoomEntry(entry)) => Model.logged(state, room_id, root, [entry])
			(_, Listed(workspaces)) => Model.relisted({ ..state, listed: { ..state.listed, workspaces } })
			(_, Agents(listed)) => { ..state, agents: listed }
			(_, Tickets(listing)) => { ..state, tickets: TicketDesk.received(state.tickets, Listing(listing)) }
			(_, Ticket(ticket)) => { ..state, tickets: TicketDesk.received(state.tickets, Opened(ticket)) }
			(_, Links(links)) => { ..state, tickets: TicketDesk.received(state.tickets, Links(links)) }
			(_, Status({ stt })) => { ..state, voice: { ..state.voice, engine: stt } }
			(Changes({ context, .. }), Changes({ workspace, status, changes, commits })) =>
				{
					..state,
					git: state.git.drop_if(|known| known.context == context).append({ context, workspace, status, commits }),
					git_changes: state.git_changes.drop_if(|known| known.context == context and known.changes.scope == changes.scope).append({ context, changes }),
				}
			(File({ context, scope, .. }), File({ path, hunks })) =>
				{ ..state, git_hunks: state.git_hunks.drop_if(|known| known.context == context and known.scope == scope and known.path == path).append({ context, scope, path, hunks }) }
			(Threads(context), Threads(review)) => { ..state, reviews: state.reviews.drop_if(|known| known.context == context).append({ context, review }) }
			(Tree({ context, .. }), Tree(tree)) => { ..state, trees: state.trees.drop_if(|known| known.context == context and known.tree.path == tree.path).append({ context, tree }) }
			(Contents({ context, .. }), Contents(contents)) => {
				lines =
					match contents.read {
						Text({ text, .. }) => Highlight.lines(contents.path.split_last(".").map_ok(|parts| parts.after) ?? "", text.drop_suffix("\n").split_on("\n").take_first(Model.lines_shown))
						_ => []
					}
				{ ..state, texts: state.texts.drop_if(|known| known.context == context and known.contents.path == contents.path).append({ context, contents, lines }) }
			}
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

	## How long the agent of the session a chat pane shows has worked on its
	## turn, waiting for you too, as `Model.duration_text` says it, or "" if
	## its provider doesn't tell; none while it is in no turn.
	working : State, Pane -> Try(Str, [NotWorking])
	working = |state, shown| {
		shown_session = Model.session(state, Model.session_of(state, shown))
		match epoch_ms(shown_session.running_since ?? "") {
			_ if !Model.busy(shown_session.status) or Model.starting(state, shown_session.id) => Err(NotWorking)
			Ok(since) if state.now >= since => Ok(Model.duration_text(state.now - since))
			_ => Ok("")
		}
	}

	## Milliseconds as "9s", "3m 46s" or "1h 2m".
	duration_text : I64 -> Str
	duration_text = |milliseconds| {
		seconds = milliseconds // 1000
		if (seconds < 60) "${seconds.to_str()}s" else if (seconds < 3600) "${(seconds // 60).to_str()}m ${(seconds % 60).to_str()}s" else "${(seconds // 3600).to_str()}h ${(seconds % 3600 // 60).to_str()}m"
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
	stop = |state, pane_id| Model.stop_session(state, Model.session_of(state, Model.pane(state, pane_id)))

	stop_session : State, Str -> State
	stop_session = |state, session_id| { ..Model.send({ ..state, sent: state.sent.drop_if(|sent| Model.stops(sent.request, session_id)) }, Cancel({ session_id: session_id })), menu: "" }

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
		answers_permission = |sent|
			match sent.request {
				AnswerPermission(_) => sent.serial == serial
				_ => Bool.False
			}
		sent = state.sent.drop_if(answers_permission).map(|kept| if (kept.serial == serial) { ..kept, failed: reason } else kept)
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
		if (text.is_empty() or session_id.is_empty())
			state
		else
			Model.send({ ..Model.set_draft(state, pane_id, ""), drafts_rewritten: { pane: pane_id, count: state.drafts_rewritten.count + 1 } }, SendMessage({ session_id, text }))
	}

	## The latest permission request in the session a pane shows that no answer
	## follows, in the timeline or on its way.
	pending : State, Str -> Try({ session_id : Str, asked : Chat.Permission }, [NoneWaiting])
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
			Ok({ event: PermissionRequested(question), .. }) => Ok({ session_id, asked: question })
			_ => Err(NoneWaiting)
		}
	}

	## A permission request's choices: the provider's own, or else Allow and
	## Deny, whose ids are "".
	choices : Chat.Permission -> List(Chat.Choice)
	choices = |asked| asked.choices ?? [{ id: "", label: "Allow", allows: Bool.True, style: Primary }, { id: "", label: "Deny", allows: Bool.False, style: Danger }]

	## Answers a session's permission request with one of its choices, the
	## request hidden at once until the timeline shows the answer.
	answer : State, { session_id : Str, request_id : Str, choice : Chat.Choice } -> State
	answer = |state, { session_id, request_id, choice }| Model.send(state, AnswerPermission({ session_id, request_id, allowed: choice.allows, choice: if (choice.id.is_empty()) Err(Missing) else Ok(choice.id) }))

	## The attention items as the inbox shows them: set aside, back, read or
	## unread as soon as asked.
	inbox_items : State -> List(Attention.Item)
	inbox_items = |state| state.attention.map(|item| state.attending.fold(item, |shown, asked| Model.attended(shown, asked.request)))

	## An item as a request sent of it leaves it.
	attended : Attention.Item, Attention.Request -> Attention.Item
	attended = |item, request|
		match request {
			Settle({ session_id, .. }) if session_id == item.session_id => { ..item, set_aside: Settled }
			Snooze({ session_id, .. }) if session_id == item.session_id => { ..item, set_aside: Snoozed }
			Unsettle({ session_id }) if session_id == item.session_id => { ..item, set_aside: No }
			Seen(marks) => marks.find_first(|mark| mark.session_id == item.session_id).map_ok(|mark| { ..item, unread: item.state != Working and mark.through != item.updated }) ?? item
			_ => item
		}

	## The items in `attention_state` not set aside.
	waiting : State, Attention.State -> List(Attention.Item)
	waiting = |state, attention_state| Model.inbox_items(state).keep_if(|item| item.state == attention_state and item.set_aside == No)

	## The items an inbox pane lists under what needs you, the latest first:
	## those not set aside, idle ones if it shows them.
	latest : State, Pane -> List(Attention.Item)
	latest = |state, shown| Model.inbox_items(state).keep_if(|item| item.set_aside == No and item.state != NeedsYou and (item.state != Idle or Model.option(shown, "show_idle") == "true"))

	later : State -> List(Attention.Item)
	later = |state| Model.inbox_items(state).keep_if(|item| item.set_aside != No)

	## How many items need you, as the document title and the inbox's tab
	## show.
	needs_you : State -> U64
	needs_you = |state| Model.waiting(state, NeedsYou).len()

	## Takes the items the poll numbered `asked` answered, and marks the
	## sessions a chat pane shows seen.
	attention_fetched : State, U64, List(Attention.Item) -> State
	attention_fetched = |state, asked, items| {
		answered = |attending| (attending.accepted > 0 and attending.accepted <= asked) or items.all(|item| Model.attended(item, attending.request) == item)
		fetched = { ..state, attention: items, attending: state.attending.drop_if(answered) }
		on_screen = Model.panes(fetched).keep_if(|shown| shown.widget == "chat" and Model.pane_visible(fetched, shown.id)).map(|shown| Model.session_of(fetched, shown))
		Model.mark_seen({ ..fetched, sent: fetched.sent.drop_if(|sent| Model.confirmed(fetched, sent)) }, on_screen, Bool.True)
	}

	## Sends a request of attention.v1, its change shown at once.
	attend : State, Attention.Request -> State
	attend = |state, request| {
		serial = state.attention_outbox.serial + 1
		{ ..state, attention_outbox: { serial, request }, attending: state.attending.append({ serial, request, accepted: 0 }), notice: "" }
	}

	## Settles an item, snoozes it for some minutes, or brings it back (`No`).
	set_aside : State, Str, [No, Settled, Snoozed(U32)] -> State
	set_aside = |state, session_id, asked|
		match state.attention.find_first(|item| item.session_id == session_id) {
			Err(NotFound) => state
			Ok({ signature, .. }) =>
				Model.attend(
					state,
					match asked {
						Settled => Settle({ session_id, signature })
						Snoozed(minutes) => Snooze({ session_id, signature, minutes })
						No => Unsettle({ session_id: session_id })
					},
				)
		}

	## Marks the items of sessions read as they are now (`seen`), or unread,
	## those not so already.
	mark_seen : State, List(Str), Bool -> State
	mark_seen = |state, session_ids, seen| {
		marks = Model.inbox_items(state).keep_if(|item| session_ids.contains(item.session_id) and item.unread == seen).map(|item| { session_id: item.session_id, through: if (seen) item.updated else "" })
		if (marks.is_empty()) state else Model.attend(state, Seen(marks))
	}

	## Whether a session's item is unread, as the inbox shows it.
	unread : State, Str -> Bool
	unread = |state, session_id| state.attention.find_first(|item| item.session_id == session_id).map_ok(|item| state.attending.fold(item, |shown, asked| Model.attended(shown, asked.request)).unread) ?? Bool.False

	## How long an inbox pane's Snooze sets an item aside, in minutes.
	snooze_minutes : Pane -> U32
	snooze_minutes = |shown|
		match Model.option(shown, "snooze_length") {
			"1 day" => 24 * 60
			"1 week" => 7 * 24 * 60
			_ => 60
		}

	## Takes the daemon's answer to a request of attention.v1: accepted, it
	## holds until the poll it asks for shows it; refused, the item is as it
	## was, with why.
	attention_answered : State, U64, Protocol.Answer(Attention.Response) -> State
	attention_answered = |state, serial, answered|
		match answered {
			Ok(Rejected(reason)) | Err({ message: reason, .. }) => { ..state, attending: state.attending.drop_if(|asked| asked.serial == serial), notice: reason }
			Ok(_) => Model.poll({ ..state, attending: state.attending.map(|asked| if (asked.serial == serial) { ..asked, accepted: state.poll.serial + 1 } else asked) })
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

	## Focuses a context, so panes that follow the focus show it, and shows
	## the first chat's column, which on a narrow screen is a jump to it. A
	## session opened is seen.
	open : State, Context.Id -> State
	open = |state, context| {
		focused = Model.mark_seen({ ..state, focus: context }, [Context.to_str(context)], Bool.True)
		match state.columns.find_first(|column| column.panes.any(|shown| shown.widget == "chat")) {
			Ok(column) => Model.jump_to(focused, column.id, Push)
			Err(NotFound) => focused
		}
	}

	## Whether a pane is on screen: not hidden, a tab behind another, nor in a
	## collapsed drawer.
	pane_visible : State, Str -> Bool
	pane_visible = |state, pane_id|
		match state.columns.find_first(|column| column.panes.any(|shown| shown.id == pane_id)) {
			Ok(column) => (!column.tabbed or column.active == pane_id) and !state.collapsed.contains(Model.slot_of(state, column.id)) and !state.hidden.contains(pane_id)
			Err(NotFound) => Bool.False
		}

	## A Changes pane shows uncommitted changes, every folder open, and no
	## file until picked, in the pane itself.
	git_pane : State, Str -> GitPane
	git_pane = |state, pane_id| state.git_panes.find_first(|shown| shown.pane == pane_id) ?? { pane: pane_id, scope: Uncommitted, file: NoFile, folded: [], in_main: Bool.False }

	set_git_pane : State, GitPane -> State
	set_git_pane = |state, shown| { ..state, git_panes: state.git_panes.drop_if(|old| old.pane == shown.pane).append(shown) }

	## Shows a scope, or a file of it, in a Changes pane at once; the poll it
	## sends at once brings what the UI doesn't have yet.
	show_git : State, Str, WorkspaceGit.Scope, [Selected(Str), NoFile] -> State
	show_git = |state, pane_id, scope, file| Model.set_git_pane(state, { ..Model.git_pane(state, pane_id), scope, file })

	## Shows a file of a Changes pane's tree, or folds or unfolds a folder, at
	## once.
	pick_changed : State, { pane_id : Str, path : Str, folder : Bool } -> State
	pick_changed = |state, { pane_id, path, folder }| {
		shown = Model.git_pane(state, pane_id)
		if (folder) Model.set_git_pane(state, { ..shown, folded: if (shown.folded.contains(path)) shown.folded.drop_if(|folded| folded == path) else shown.folded.append(path) }) else Model.show_git(state, pane_id, shown.scope, Selected(path))
	}

	## The pane a Workbench's main area shows, which a diff opened there
	## takes the place of; "" in another shell.
	main_area_pane : State -> Str
	main_area_pane = |state|
		match (state.shell, state.columns.get(1)) {
			(Workbench, Ok(column)) => if (column.tabbed) column.active else column.panes.first().map_ok(|shown| shown.id) ?? ""
			_ => ""
		}

	## The Changes pane whose file's diff the main area shows, "" for none.
	main_diff : State -> Str
	main_diff = |state| {
		main = Model.main_area_pane(state)
		state.git_panes.find_first(|shown| shown.in_main and shown.file != NoFile and shown.pane != main and !main.is_empty() and Model.pane(state, shown.pane).widget == "changes").map_ok(|shown| shown.pane) ?? ""
	}

	## Shows a Changes pane's diffs in the main area, its panel on a phone, or
	## in the pane again, at once.
	show_in_main : State, Str, Bool -> State
	show_in_main = |state, pane_id, in_main| {
		shown = Model.set_git_pane(state, { ..Model.git_pane(state, pane_id), in_main })
		if (in_main) Model.show_column(shown, state.columns.get(1).map_ok(|column| column.id) ?? "") else shown
	}

	## The files of the scope a Changes pane shows, as its tree's rows.
	changed_tree : State, Pane -> List(ChangedRow)
	changed_tree = |state, shown|
		match Model.git_files(state, shown) {
			Files(files) => changed_rows(files, Model.git_pane(state, shown.id).folded, "", 0)
			Loading => []
		}

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

	## A file's hunks as rows of the code view, each under its header:
	## unified, each line under its old and new numbers, or split, old beside
	## new with a removed line beside the added line replacing it.
	diff_code : Str, Str, List(WorkspaceGit.Hunk) -> List(CodeRow)
	diff_code = |diff_layout, path, hunks| {
		number = |line_number| if (line_number == 0) "" else line_number.to_str()
		kind = |line|
			match line.kind {
				Added => "added"
				Removed => "removed"
				Context => "context"
			}
		tokens = |line| Highlight.lines(path.split_last(".").map_ok(|parts| parts.after) ?? "", [line.text]).first() ?? []
		# Comments go on the new side's lines, or the old side's for removed ones.
		pick = |line| if (line.kind == Removed) { side: Old, line: line.old_line } else { side: New, line: line.new_line }
		blank = { ..Model.code_row, left_class: "empty", right_class: "empty" }
		old = |row, line| { ..row, old: number(line.old_line), old_pick: pick(line), left: tokens(line), left_class: kind(line) }
		new = |row, line| { ..row, new: number(line.new_line), new_pick: pick(line), right: tokens(line), right_class: kind(line) }
		rows_of = |lines|
			if diff_layout == "Split" {
				paired = lines.fold(
					{ rows: [], open: 0 },
					|so_far, line|
						match line.kind {
							Context => { rows: so_far.rows.append(new(old(blank, line), line)), open: so_far.rows.len() + 1 }
							Removed => { ..so_far, rows: so_far.rows.append(old(blank, line)) }
							Added =>
								if (so_far.open < so_far.rows.len())
									{ rows: so_far.rows.map_with_index(|row, index| if (index == so_far.open) new(row, line) else row), open: so_far.open + 1 }
								else
									{ rows: so_far.rows.append(new(blank, line)), open: so_far.rows.len() + 1 }
						},
				)
				paired.rows
			} else {
				sign = |line|
					match line.kind {
						Added => "+ "
						Removed => "- "
						Context => "  "
					}
				lines.map(|line| { ..new(blank, line), old: number(line.old_line), old_pick: pick(line), right: tokens(line).prepend({ class: "sign", text: sign(line) }) })
			}
		header = |hunk| "@@ -${hunk.old_start.to_str()},${hunk.old_count.to_str()} +${hunk.new_start.to_str()},${hunk.new_count.to_str()} @@"
		hunks.map_with_index(|hunk, at| rows_of(hunk.lines).map_with_index(|row, index| { ..row, key: "${at.to_str()}/${index.to_str()}" }).prepend({ ..blank, key: at.to_str(), right: [{ class: "", text: header(hunk) }], right_class: "hunk-header", class: "hunk" })).join_map(|rows| rows)
	}

	## The diff of the file a Changes pane shows, as rows of the code view.
	git_code : State, Pane -> List(CodeRow)
	git_code = |state, shown|
		match (Model.git_pane(state, shown.id).file, Model.git_hunks_of(state, shown)) {
			(Selected(path), Hunks(hunks)) => Model.annotated(state, shown, Model.diff_code(Model.option(shown, "diff_layout"), path, hunks))
			_ => []
		}

	## A row of a Workspaces pane: a group of workspaces, by project or by
	## what they need from you, folded or not; a workspace in it; or a
	## session in that. `key` is the context a workspace or session row
	## focuses (`Context.to_str`), or `group:` and the group's. A row is
	## `creatable` when + on it starts an agent there, or creates a workspace
	## of its project. `counts` are a group's members, or a workspace's
	## uncommitted lines added and removed, as "+3" and "−1". `age` is how
	## long ago a session or workspace last changed (`Model.age`). A
	## workspace `pinned`, or its one session, lists first.
	Row : { key : Str, kind : [Group, Workspace, Session, Folder, File, Thread], title : Str, detail : Str, counts : Counts, dot : Str, status : Str, age : Str, focused : Bool, folded : Bool, creatable : Bool, pinned : Bool, depth : U64 }

	Counts : { members : Str, added : Str, removed : Str }

	no_counts : Counts
	no_counts = { members: "", added: "", removed: "" }

	## A Workspaces pane's rows, as its options group, filter and order them:
	## a workspace's one session in its place, with its branch if it is a
	## worktree and its changes, or a workspace of none or several, marked as
	## urgent as its most urgent session and unread while one is, over them.
	workspace_rows : State, Pane -> List(Row)
	workspace_rows = |state, shown| {
		folded = Model.option(shown, "folded").split_on("\n")
		order = Model.option(shown, "order")
		# Those still starting show where they will be, idle and without git.
		placeholders = state.creating.keep_if(|creating| creating.form.kind == Workspace).map(|creating| { id: Model.created_id(creating), provider: "", project_id: creating.form.place, name: creating.title, directory: "", kind: Checkout, branch: NotGit, state: Idle, dirty: Bool.False, changes: Uncounted, pinned: Bool.False, labels: [], session_ids: [] })
		sessions_in = |workspace| {
			agents = state.creating.keep_if(|creating| creating.form.kind == Agent and creating.form.place == workspace.id).map(|creating| Model.session(state, Model.created_id(creating)))
			listed_sessions = state.sessions.keep_if(|listed_session| workspace.session_ids.contains(listed_session.id)).concat(agents.drop_if(|agent| workspace.session_ids.contains(agent.id)))
			Model.ordered(listed_sessions, order, |listed_session| Model.changed(state, listed_session), |listed_session| listed_session.title)
		}
		workspace_changed = |workspace| if (Model.starting(state, workspace.id)) Model.newest else sessions_in(workspace).map(|listed_session| Model.changed(state, listed_session)).fold(0, U64.max)
		in_order = Model.ordered(state.workspaces.workspaces.concat(placeholders), order, workspace_changed, |workspace| workspace.name).drop_if(|workspace| Model.option(shown, "show_idle") == "false" and workspace.state == Idle and !Model.starting(state, workspace.id))
		listed = in_order.keep_if(|workspace| workspace.pinned).concat(in_order.drop_if(|workspace| workspace.pinned))
		groups =
			if Model.option(shown, "group_by") == "Status" {
				Attention.ranks.map(|rank| { key: "group:${attention_word(rank)}", title: sentence_case(attention_word(rank)), members: listed.keep_if(|workspace| workspace.state == rank), creatable: Bool.False }).drop_if(|group| group.members.is_empty())
			} else {
				projects = state.workspaces.projects.map(|project| { key: "group:${project.id}", title: sentence_case(project.name), members: listed.keep_if(|workspace| workspace.project_id == project.id), creatable: Bool.True })
				Model.ordered(projects, order, |group| group.members.map(workspace_changed).fold(0, U64.max), |group| group.title)
			}
		blank = { key: "", kind: Group, title: "", detail: "", counts: Model.no_counts, dot: "", status: "", age: "", focused: Bool.False, folded: Bool.False, creatable: Bool.False, pinned: Bool.False, depth: 0 }
		mark = |row| if (Model.starting(state, row.key) or Model.starting(state, row.key.drop_prefix("workspace:"))) { ..row, dot: "starting", status: "starting…", creatable: Bool.False } else row
		workspace_rows_of = |workspace| {
			sessions = sessions_in(workspace)
			branch = match workspace.branch {
				Branch(name) if name != workspace.name => name
				Detached => "detached"
				_ => ""
			}
			dot = if (workspace.session_ids.any(|session_id| Model.unread(state, session_id))) "${attention_dot(workspace.state)} unread" else attention_dot(workspace.state)
			newest_age = Model.ordered(sessions, "Latest", |listed_session| Model.changed(state, listed_session), |listed_session| listed_session.title).first().map_ok(|latest_session| Model.age(state, latest_session)) ?? ""
			row = mark({ ..blank, key: Context.to_str(Workspace(workspace.id)), kind: Workspace, title: workspace.name, detail: branch, counts: Model.change_counts(state, workspace), dot, age: newest_age, focused: state.focus == Workspace(workspace.id), creatable: Bool.True, pinned: workspace.pinned })
			match sessions.first() {
				Ok(lone) if sessions.len() == 1 => {
					lone_row = Model.session_row(state, lone)
					[mark({ ..lone_row, detail: if (workspace.kind == Worktree) branch_name(workspace.branch) else "", counts: row.counts, focused: lone_row.focused or row.focused, creatable: Bool.True, pinned: workspace.pinned })]
				}
				_ => sessions.map(|listed_session| mark({ ..Model.session_row(state, listed_session), depth: 1 })).prepend(row)
			}
		}
		groups.join_map(
			|group| {
				header = { ..blank, key: group.key, title: group.title, counts: { ..Model.no_counts, members: group.members.len().to_str() }, folded: folded.contains(group.key), creatable: group.creatable }
				if (header.folded) [header] else group.members.join_map(workspace_rows_of).prepend(header)
			},
		)
	}

	## A session's row, in a Workspaces or a Sessions pane.
	session_row : State, Chat.Session -> Row
	session_row = |state, listed_session| {
		rank = Attention.item(listed_session, []).state
		dot = if (Model.unread(state, listed_session.id)) "${attention_dot(rank)} unread" else attention_dot(rank)
		{ key: listed_session.id, kind: Session, title: listed_session.title, detail: "", counts: Model.no_counts, dot, status: attention_word(rank), age: Model.age(state, listed_session), focused: state.focus == Session(listed_session.id), folded: Bool.False, creatable: Bool.False, pinned: Bool.False, depth: 0 }
	}

	## A Sessions pane's rows: every session in its order, with its agent if
	## it shows that.
	session_rows : State, Pane -> List(Row)
	session_rows = |state, shown| Model.ordered(state.sessions, Model.option(shown, "order"), |listed_session| Model.changed(state, listed_session), |listed_session| listed_session.title).map(|listed_session| { ..Model.session_row(state, listed_session), detail: if (Model.option(shown, "show_agent") == "true") listed_session.agent else "" })

	## When a session last changed, as `Attention.recency` orders times: as
	## its inbox item says, else as it does. One starting is the newest.
	changed : State, Chat.Session -> U64
	changed = |state, listed_session|
		if (Model.starting(state, listed_session.id)) Model.newest else Attention.recency(state.attention.find_first(|item| item.session_id == listed_session.id).map_ok(|item| item.updated) ?? (listed_session.updated ?? ""))

	## How long ago a session last changed, as `Model.ago` says it.
	age : State, Chat.Session -> Str
	age = |state, listed_session| {
		last_change = state.attention.find_first(|item| item.session_id == listed_session.id).map_ok(|item| item.updated) ?? (listed_session.updated ?? "")
		if (Model.starting(state, listed_session.id)) "" else Model.ago(state, last_change)
	}

	## How long ago a time such as `2026-01-01T08:00:00.000Z` was, from the
	## minute last begun, as "now", "3m", "3h", "2d" or "4w"; "" for none.
	ago : State, Str -> Str
	ago = |state, time|
		match epoch_ms(time) {
			Ok(at) if state.now > 0 => {
				minutes = (state.now - at) // 60_000
				if (minutes < 1) "now" else if (minutes < 60) "${minutes.to_str()}m" else if (minutes < 1440) "${(minutes // 60).to_str()}h" else if (minutes < 10080) "${(minutes // 1440).to_str()}d" else "${(minutes // 10080).to_str()}w"
			}
			_ => ""
		}

	## Newer than any time `Attention.recency` gives.
	newest : U64
	newest = 100_000_000_000_000_000

	## `items` in the `order` a pane's option names: by `name`, or the latest
	## first, as `changed_at` tells; those alike in the order given.
	ordered : List(a), Str, (a -> U64), (a -> Str) -> List(a)
	ordered = |items, order, changed_at, name| {
		compared = |left, right| if (left < right) Before else if (left > right) After else Same
		lower = |text| text.to_utf8().map(|byte| if (byte >= 'A' and byte <= 'Z') byte + 32 else byte)
		keyed = items.map_with_index(|item, index| { item, index, changed: changed_at(item), name: if (order == "Name") lower(name(item)) else [] })
		by = |left, right| if (order == "Name") bytes_order(left.name, right.name) else compared(right.changed, left.changed)
		keyed.sort_with(|left, right| [by(left, right), compared(left.index, right.index)].find_first(|so_far| so_far != Same) ?? Same).map(|kept| kept.item)
	}

	## A workspace's uncommitted lines added and removed: as its provider
	## counts them, else as a Changes pane last saw them; nothing when they
	## are none or unknown.
	change_counts : State, Workspaces.Workspace -> Counts
	change_counts = |state, workspace| {
		seen = workspace.session_ids.map(|session_id| Session(session_id)).prepend(Workspace(workspace.id)).keep_oks(|context| Model.git_changes_of(state, context, Uncommitted)).first()
		counted =
			match (workspace.changes, seen) {
				(Counted(counts), _) if counts.additions + counts.deletions > 0 => Ok(counts)
				(_, Ok({ files, .. })) => Ok(files.fold({ additions: 0, deletions: 0 }, |sum, file| { additions: sum.additions + file.additions, deletions: sum.deletions + file.deletions }))
				_ => Err(Unknown)
			}
		match counted {
			Ok({ additions, deletions }) if additions + deletions > 0 => { members: "", added: "+${additions.to_str()}", removed: "−${deletions.to_str()}" }
			_ => Model.no_counts
		}
	}

	## The uncommitted lines added and removed in the workspace of what a
	## pane shows, for the right drawer's button to show.
	workspace_changes : State, Pane -> Counts
	workspace_changes = |state, shown| {
		workspace_id = match Model.context_of(state, shown) {
			Workspace(id) => id
			Session(session_id) => state.workspaces.workspaces.find_first(|listed| listed.session_ids.contains(session_id)).map_ok(|listed| listed.id) ?? (Model.session(state, session_id).workspace.map_ok(|placed| placed.id ?? "") ?? "")
		}
		state.workspaces.workspaces.find_first(|listed| listed.id == workspace_id).map_ok(|listed| Model.change_counts(state, listed)) ?? Model.no_counts
	}

	## Folds or unfolds a group of a Workspaces pane, which the snapshot
	## keeps, or focuses a workspace or a session; opens or closes a Files
	## pane's folder, or shows its file; or jumps to a review's thread.
	pick_row : State, { pane_id : Str, key : Str } -> State
	pick_row = |state, { pane_id, key }|
		if key.starts_with("group:") {
			folded = Model.option(Model.pane(state, pane_id), "folded").split_on("\n").drop_if(Str.is_empty)
			Model.set_option(state, pane_id, "folded", Str.join_with(if (folded.contains(key)) folded.drop_if(|group| group == key) else folded.append(key), "\n"))
		} else if key.starts_with("dir:") {
			Model.toggle_folder(state, pane_id, key.drop_prefix("dir:"))
		} else if key.starts_with("file:") {
			Model.show_file(state, pane_id, key.drop_prefix("file:"))
		} else if key.starts_with("thread:") {
			Model.jump_to_thread(state, { pane_id, thread: key.drop_prefix("thread:") })
		} else if key.starts_with("comment:") {
			state
		} else {
			if (key.starts_with("starting:") or key.starts_with("workspace:starting:")) state else Context.from_str(key).map_ok(|context| Model.open(state, context)) ?? state
		}

	## What a Files pane shows: its root, and no folder open nor file until
	## picked.
	file_pane : State, Str -> FilePane
	file_pane = |state, pane_id| state.file_panes.find_first(|shown| shown.pane == pane_id) ?? { pane: pane_id, folders: [], file: "" }

	set_file_pane : State, FilePane -> State
	set_file_pane = |state, shown| { ..state, file_panes: state.file_panes.drop_if(|old| old.pane == shown.pane).append(shown) }

	## Opens a folder of a Files pane, or closes it with those in it, at once;
	## the poll it sends at once lists what the UI doesn't have yet.
	toggle_folder : State, Str, Str -> State
	toggle_folder = |state, pane_id, path| {
		shown = Model.file_pane(state, pane_id)
		Model.set_file_pane(state, { ..shown, folders: if (shown.folders.contains(path)) shown.folders.drop_if(|folder| folder == path or folder.starts_with("${path}/")) else shown.folders.append(path) })
	}

	## Shows a file in a Files pane, the folders it is in open.
	show_file : State, Str, Str -> State
	show_file = |state, pane_id, path| {
		shown = Model.file_pane(state, pane_id)
		parts = path.split_on("/")
		folders = parts.drop_last(1).map_with_index(|_, index| Str.join_with(parts.take_first(index + 1), "/"))
		Model.set_file_pane(state, { ..shown, file: path, folders: folders.fold(shown.folders, |kept, folder| if (kept.contains(folder)) kept else kept.append(folder)) })
	}

	## Shows a file in the first Files pane, as its column's tab shown, from
	## a path elsewhere, such as in Changes.
	open_file : State, Str -> State
	open_file = |state, path|
		match Model.panes(state).find_first(|shown| shown.widget == "files") {
			Ok(files) => Model.activate_tab(Model.show_file(state, files.id, path), files.id)
			Err(NotFound) => state
		}

	## A Files pane's rows: its root's entries, folders first, and under each
	## folder open its own.
	file_rows : State, Pane -> List(Row)
	file_rows = |state, shown| folder_rows(state, Model.context_of(state, shown), Model.file_pane(state, shown.id), ".", 0)

	## What a Files pane says of its root, "" once it lists it.
	tree_status : State, Pane -> Str
	tree_status = |state, shown| {
		context = Model.context_of(state, shown)
		match state.trees.find_first(|known| known.context == context and known.tree.path == ".").map_ok(|known| known.tree.listing) {
			_ if context == Session("") => "Pick a session to see its files."
			Ok(Listed([])) => "No files."
			Ok(Listed(_)) => ""
			Ok(Unreadable(why)) => "Can't read its files: ${why}"
			_ => "Loading…"
		}
	}

	## What a Files pane says of its file: why it shows none of it or not
	## all, "" when it shows it whole or there is none.
	file_status : State, Pane -> Str
	file_status = |state, shown| {
		context = Model.context_of(state, shown)
		{ file, .. } = Model.file_pane(state, shown.id)
		match state.texts.find_first(|known| known.context == context and known.contents.path == file) {
			_ if file.is_empty() => ""
			Ok({ contents: { read: Binary({ size, .. }), .. }, .. }) => "A binary file of ${size_text(size)}."
			Ok({ contents: { read: TooLarge, .. }, .. }) => "Too large to show."
			Ok({ contents: { read: Unreadable(why), .. }, .. }) => "Can't read it: ${why}"
			Ok({ contents: { read: Text({ truncated: Bool.True, size, .. }), .. }, .. }) => "Its first ${size_text(Files.text_limit)} of ${size_text(size)}."
			Ok({ contents: { read: Text(_), .. }, lines, .. }) if lines.len() == Model.lines_shown => "Its first ${Model.lines_shown.to_str()} lines."
			Ok({ contents: { read: Text(_), .. }, .. }) => ""
			_ => "Loading…"
		}
	}

	## How many of a file's lines the code view shows at most.
	lines_shown : U64
	lines_shown = 2000

	## A row of the code view, a file's or a diff's: a line under its old and
	## new numbers ("" for none), its text (`right`) and, in a split diff, the
	## old line beside it (`left`), each side's class saying whether it was
	## added, removed or neither, or a hunk's header; the composer of a
	## comment on the lines over it; or a comment of a thread on them.
	## Clicking a number picks the line it says (`pick_line`).
	CodeRow : { key : Str, kind : [Code, Composer, Comment], old : Str, new : Str, old_pick : Pick, new_pick : Pick, left : List(Highlight.Token), right : List(Highlight.Token), left_class : Str, right_class : Str, class : Str, note : Note }

	## A line to comment on, on a side of a diff: none when `line` is 0.
	Pick : { side : Review.Side, line : U32 }

	## A comment as a row shows it: its thread's and its own id, who said it
	## and its state, and whether it is the thread's last, as a resolved
	## thread folded into one is.
	Note : { thread : Str, comment : Str, author : Str, state : Str, text : Str, last : Bool, resolved : Bool, draft : Bool }

	code_row : CodeRow
	code_row = { key: "", kind: Code, old: "", new: "", old_pick: { side: New, line: 0 }, new_pick: { side: New, line: 0 }, left: [], right: [], left_class: "", right_class: "", class: "", note: { thread: "", comment: "", author: "", state: "", text: "", last: Bool.False, resolved: Bool.False, draft: Bool.False } }

	## The file a Files pane shows, as rows of the code view.
	file_code : State, Pane -> List(CodeRow)
	file_code = |state, shown| {
		context = Model.context_of(state, shown)
		{ file, .. } = Model.file_pane(state, shown.id)
		lines = state.texts.find_first(|known| known.context == context and known.contents.path == file).map_ok(|known| known.lines) ?? []
		Model.annotated(state, shown, lines.map_with_index(|tokens, index| { ..Model.code_row, key: (index + 1).to_str(), new: (index + 1).to_str(), new_pick: { side: New, line: (index + 1).to_u32_wrap() }, right: tokens }))
	}

	## The file a Files or Changes pane shows, and the scope of review.v1
	## its lines are in.
	viewed : State, Pane -> Try({ path : Str, scope : Review.Scope }, [NoFile])
	viewed = |state, shown|
		match (shown.widget, Model.git_pane(state, shown.id)) {
			("files", _) if !Model.file_pane(state, shown.id).file.is_empty() => Ok({ path: Model.file_pane(state, shown.id).file, scope: File })
			("changes", { file: Selected(path), scope: Uncommitted, .. }) => Ok({ path, scope: Uncommitted })
			("changes", { file: Selected(path), scope: AgainstBase, .. }) => Ok({ path, scope: AgainstBase })
			("changes", { file: Selected(path), scope: Commit(sha), .. }) => Ok({ path, scope: Commit(sha) })
			_ => Err(NoFile)
		}

	## The code view's rows with the review's threads on their lines, each
	## after the line it ends on, its lines marked, and the composer after
	## the lines picked, which are marked as picked.
	annotated : State, Pane, List(CodeRow) -> List(CodeRow)
	annotated = |state, shown, rows|
		match Model.viewed(state, shown) {
			Err(NoFile) => rows
			Ok({ path, scope }) => {
				composer = state.composer
				threads = Model.review_of(state, Model.context_of(state, shown)).threads.keep_if(|thread| Review.shows(thread.anchor, path, scope) and !thread.outdated)
				composing_here = composer.pane == shown.id and composer.path == path and composer.scope == scope
				on = |picks, side, start, end| picks.any(|picked| picked.side == side and picked.line >= start and picked.line <= end)
				composer_row = { ..Model.code_row, key: "composer", kind: Composer }
				notes = |thread| {
					last = thread.comments.len() - 1
					listed = if (thread.resolved) thread.comments.take_first(1) else thread.comments
					shown_notes = listed.map_with_index(
						|comment, index| {
							note = { thread: thread.id, comment: comment.id, author: if (comment.author == Me) "You" else "Agent", state: comment_state(comment.state), text: comment.text, last: index == last or thread.resolved, resolved: thread.resolved, draft: comment.state == Draft }
							if (composing_here and composer.editing == comment.id) composer_row else { ..Model.code_row, key: "${thread.id}/${comment.id}", kind: Comment, note }
						},
					)
					if (composing_here and composer.thread == thread.id) shown_notes.append(composer_row) else shown_notes
				}
				rows.join_map(
					|row| {
						picks = [row.old_pick, row.new_pick].keep_if(|picked| picked.line > 0)
						picked = composing_here and on(picks, composer.side, composer.start, composer.end)
						marked = threads.any(|thread| on(picks, thread.anchor.side, thread.anchor.start_line, thread.anchor.end_line))
						ending = threads.keep_if(|thread| on(picks, thread.anchor.side, thread.anchor.end_line, thread.anchor.end_line))
						opened = composing_here and composer.thread.is_empty() and composer.editing.is_empty() and on(picks, composer.side, composer.end, composer.end)
						class = Str.join_with([if (picked) "picked" else "", if (marked) "marked" else "", if (row.right_class == "hunk-header") "hunk" else ""].drop_if(Str.is_empty), " ")
						ending.join_map(notes).concat(if (opened) [composer_row] else []).prepend({ ..row, class })
					},
				)
			}
		}

	## The review of a context as the daemon has it, with the requests on
	## their way applied.
	review_of : State, Context.Id -> Review.Snapshot
	review_of = |state, context| {
		stored = state.reviews.find_first(|known| known.context == context).map_ok(|known| known.review) ?? Review.empty
		state.reviewing.keep_if(|asked| Review.context(asked.request) == Context.to_str(context)).fold(stored, |review, asked| Review.applied(review, asked.request) ?? review)
	}

	## Picks a line of the file or diff a pane shows to comment on, which
	## opens the composer under it at once. With one line picked, a second
	## picks the lines from one to the other; the line picked again closes an
	## empty composer, and any other line starts again there, with what is
	## typed.
	pick_line : State, { pane_id : Str, picked : Pick } -> State
	pick_line = |state, { pane_id, picked }|
		match Model.viewed(state, Model.pane(state, pane_id)) {
			_ if picked.line == 0 => state
			Err(NoFile) => state
			Ok({ path, scope }) => {
				composer = state.composer
				same = composer.pane == pane_id and composer.path == path and composer.scope == scope and composer.side == picked.side and composer.thread.is_empty() and composer.editing.is_empty()
				one = composer.start == composer.end
				if same and one and composer.start != picked.line {
					Model.composing(state, { ..composer, start: U32.min(composer.start, picked.line), end: U32.max(composer.start, picked.line) })
				} else if same and one and composer.text.is_empty() {
					{ ..state, composer: Model.closed_composer }
				} else {
					Model.composing(state, { ..Model.closed_composer, pane: pane_id, path, scope, side: picked.side, start: picked.line, end: picked.line, text: if (same) composer.text else "" })
				}
			}
		}

	closed_composer : Composer
	closed_composer = { pane: "", path: "", scope: File, side: New, start: 0, end: 0, thread: "", editing: "", text: "" }

	## Opens the composer, focused to type in at once, which scrolls it into
	## view.
	composing : State, Composer -> State
	composing = |state, composer| { ..state, composer, jump: { serial: state.jump.serial + 1, panel: "comment", replace: "", push: "" } }

	## Opens the composer to reply to a thread, or to edit a draft of it, in
	## the pane showing it.
	compose : State, { pane_id : Str, thread : Str, editing : Str } -> State
	compose = |state, { pane_id, thread, editing }|
		match Model.viewed(state, Model.pane(state, pane_id)) {
			Ok({ path, scope }) => {
				text = Model.review_of(state, Model.context_of(state, Model.pane(state, pane_id))).threads.join_map(|shown| shown.comments).find_first(|comment| comment.id == editing).map_ok(|comment| comment.text) ?? ""
				Model.composing(state, { ..Model.closed_composer, pane: pane_id, path, scope, thread: if (editing.is_empty()) thread else "", editing, text })
			}
			Err(NoFile) => state
		}

	## The lines picked of the file or diff a pane shows, as they read.
	quoted : State, Pane, Composer -> Str
	quoted = |state, shown, { side, start, end, .. }| {
		context = Model.context_of(state, shown)
		on_side = |line| if (side == Old) line.old_line else line.new_line
		lines =
			match Model.viewed(state, shown) {
				Ok({ scope: File, path }) => (state.texts.find_first(|known| known.context == context and known.contents.path == path).map_ok(|known| known.lines) ?? []).map(|tokens| Str.join_with(tokens.map(|token| token.text), "")).sublist({ start: start.to_u64() - 1, len: (end - start + 1).to_u64() })
				_ =>
					match Model.git_hunks_of(state, shown) {
						Hunks(hunks) => hunks.join_map(|hunk| hunk.lines).keep_if(|line| on_side(line) >= start and on_side(line) <= end and (side == New or line.kind == Removed)).map(|line| line.text)
						_ => []
					}
			}
		Str.join_with(lines, "\n")
	}

	## Sends the comment the composer holds, shown at once as a draft, and
	## closes it.
	submit_comment : State -> State
	submit_comment = |state| {
		composer = state.composer
		shown = Model.pane(state, composer.pane)
		context = Context.to_str(Model.context_of(state, shown))
		text = composer.text.trim()
		anchor = { path: composer.path, scope: composer.scope, side: composer.side, start_line: composer.start, end_line: composer.end, quote: Model.quoted(state, shown, composer) }
		request =
			if !composer.editing.is_empty() {
				EditComment({ context, comment_id: composer.editing, text })
			} else if !composer.thread.is_empty() {
				AddComment({ context, place: Thread(composer.thread), author: Me, text })
			} else {
				AddComment({ context, place: Lines(anchor), author: Me, text })
			}
		if (text.is_empty()) state else Model.ask_review({ ..state, composer: Model.closed_composer }, request)
	}

	## Shows a ticket in a Tickets pane, or its list again for "".
	open_ticket : State, { pane_id : Str, ticket_id : Str } -> State
	open_ticket = |state, { pane_id, ticket_id }| { ..state, tickets: TicketDesk.with_view(state.tickets, pane_id, |view| { ..view, ticket: ticket_id }) }

	## Changes the filter of a Tickets pane's list.
	filter_tickets : State, Str, (Tickets.Filter -> Tickets.Filter) -> State
	filter_tickets = |state, pane_id, change| { ..state, tickets: TicketDesk.with_view(state.tickets, pane_id, |view| { ..view, filter: change(view.filter) }) }

	## Sends a review.v1 request, shown at once by applying it to the review
	## the UI has (`review_of`) until the daemon answers.
	ask_review : State, Review.Request -> State
	ask_review = |state, request| {
		serial = state.call_outbox.serial + 1
		{ ..state, call_outbox: { serial, key: "review.v1", text: Json.to_str({ capability: "review.v1", request }) }, reviewing: state.reviewing.append({ serial, request, accepted: 0 }), notice: "" }
	}

	## Takes the daemon's answer to a review.v1 request: accepted, it holds
	## until the poll it asks for shows it; refused, it is undone, with why.
	reviewed : State, U64, Str -> State
	reviewed = |state, serial, text| {
		answered : Try(Protocol.Answer(Review.Response), _)
		answered = Json.parse(text)
		match answered {
			Ok(Ok(_)) => Model.poll({ ..state, reviewing: state.reviewing.map(|asked| if (asked.serial == serial) { ..asked, accepted: state.poll.serial + 1 } else asked) })
			Ok(Err({ message, .. })) => { ..state, reviewing: state.reviewing.drop_if(|asked| asked.serial == serial), notice: message }
			Err(_) => { ..state, reviewing: state.reviewing.drop_if(|asked| asked.serial == serial), notice: "The daemon did not answer." }
		}
	}

	## Sends a tickets.v1 request, shown at once (`TicketDesk`) until the
	## daemon answers.
	ask_tickets : State, Tickets.Request -> State
	ask_tickets = |state, request| {
		serial = state.call_outbox.serial + 1
		{ ..state, call_outbox: { serial, key: "tickets.v1", text: Json.to_str({ capability: "tickets.v1", request }) }, tickets: { ..state.tickets, asked: state.tickets.asked.append({ serial, request, accepted: 0 }) }, notice: "" }
	}

	## Takes the daemon's answer to a tickets.v1 request: accepted, it holds
	## until the poll it asks for shows it; refused, it is undone, with why.
	tickets_answered : State, U64, Str -> State
	tickets_answered = |state, serial, text| {
		answered : Try(Protocol.Answer(Tickets.Response), _)
		answered = Json.parse(text)
		undone = |reason| { ..state, tickets: TicketDesk.answered(state.tickets, serial, Refused), notice: reason }
		match answered {
			Ok(Ok(_)) => Model.poll({ ..state, tickets: TicketDesk.answered(state.tickets, serial, Accepted(state.poll.serial + 1)) })
			Ok(Err({ message, .. })) => undone(message)
			Err(_) => undone("The daemon did not answer.")
		}
	}

	## Links the session the focus shows to a ticket by hand: the one
	## focused, or the focused workspace's that needs you most.
	link_ticket : State, Str -> State
	link_ticket = |state, ticket_id| {
		session_id = Model.session_of(state, Model.pane(state, ""))
		if (session_id.is_empty() or Model.starting(state, session_id)) state else Model.ask_tickets(state, Link({ session_id, ticket_id }))
	}

	## Comments a Tickets pane's draft on the ticket it shows.
	comment_ticket : State, Str -> State
	comment_ticket = |state, pane_id| {
		key = "${pane_id}/ticket"
		text = Model.draft(state, key).trim()
		ticket_id = TicketDesk.view(state.tickets, pane_id).ticket
		if (text.is_empty() or ticket_id.is_empty()) state else Model.ask_tickets(Model.set_draft(state, key, ""), Comment({ ticket_id, body: text }))
	}

	## Assigns a ticket to a person too, or no longer.
	assign : State, { ticket_id : Str, person_id : Str }, Bool -> State
	assign = |state, { ticket_id, person_id }, assigned| {
		assignees = TicketDesk.listing_shown(state.tickets).tickets.find_first(|shown| shown.id == ticket_id).map_ok(|shown| shown.assignees.map(|person| person.id)) ?? []
		Model.ask_tickets(state, SetAssignees({ ticket_id, person_ids: if (assigned) assignees.drop_if(|id| id == person_id).append(person_id) else assignees.drop_if(|id| id == person_id) }))
	}

	## What a comment's button asks: to edit the draft, delete it, reply to
	## its thread, or resolve the thread, or reopen it if resolved.
	review_comment : State, { pane_id : Str, note : Note, action : [Edit, Delete, Reply, Resolve] } -> State
	review_comment = |state, { pane_id, note, action }| {
		context = Context.to_str(Model.context_of(state, Model.pane(state, pane_id)))
		match action {
			Edit => Model.compose(state, { pane_id, thread: note.thread, editing: note.comment })
			Reply => Model.compose(state, { pane_id, thread: note.thread, editing: "" })
			Delete => Model.ask_review(state, DeleteComment({ context, comment_id: note.comment }))
			Resolve if note.resolved => Model.ask_review(state, Reopen({ context, thread_id: note.thread }))
			Resolve => Model.ask_review(state, Resolve({ context, thread_id: note.thread }))
		}
	}

	## The review of a pane's context, as its review panel lists it in a
	## tree's rows: its threads in the order of their files and lines, each
	## where it is, its first comment's first line and its state, then its
	## comments on the whole review.
	review_rows : State, Pane -> List(Row)
	review_rows = |state, shown| {
		review = Model.review_of(state, Model.context_of(state, shown))
		first_line = |comments| comments.first().map_ok(|comment| comment.text.trim().split_on("\n").first() ?? "") ?? ""
		thread_state = |thread|
			if thread.resolved {
				"resolved"
			} else if thread.outdated {
				"outdated"
			} else if thread.comments.any(|comment| comment.state == Draft) {
				"draft"
			} else {
				"open"
			}
		paths = review.threads.fold([], |so_far, thread| if (so_far.contains(thread.anchor.path)) so_far else so_far.append(thread.anchor.path))
		threads = paths.join_map(|path| review.threads.keep_if(|thread| thread.anchor.path == path).sort_with(|a, b| if (a.anchor.start_line < b.anchor.start_line) Before else if (a.anchor.start_line > b.anchor.start_line) After else Same))
		row = |key, title, detail, status| { key, kind: Thread, title, detail, counts: Model.no_counts, dot: status, status, age: "", focused: Bool.False, folded: Bool.False, creatable: Bool.False, pinned: Bool.False, depth: 0 }
		threads.map(|thread| row("thread:${thread.id}", Review.lines(thread.anchor), first_line(thread.comments), thread_state(thread))).concat(review.comments.map(|comment| row("comment:${comment.id}", "Overall", first_line([comment]), comment_state(comment.state))))
	}

	## What a review panel says of its review: its drafts and rounds sent,
	## each left out while none.
	review_summary : State, Pane -> Str
	review_summary = |state, shown| {
		review = Model.review_of(state, Model.context_of(state, shown))
		drafts = Review.drafts(review)
		Str.join_with([if (drafts == 0) "" else if (drafts == 1) "1 draft" else "${drafts.to_str()} drafts", if (review.round == 0) "" else if (review.round == 1) "1 round sent" else "${review.round.to_str()} rounds sent"].drop_if(Str.is_empty), " · ")
	}

	## Adds a pane's comment on the whole review, shown at once as a draft.
	comment_overall : State, Str -> State
	comment_overall = |state, pane_id| {
		key = "${pane_id}/review"
		text = Model.draft(state, key).trim()
		context = Context.to_str(Model.context_of(state, Model.pane(state, pane_id)))
		if (text.is_empty()) state else Model.ask_review(Model.set_draft(state, key, ""), AddComment({ context, place: Overall, author: Me, text }))
	}

	## Sends the drafts of a pane's review to the session it shows, as one
	## message: they show as sent at once, and as drafts again if the daemon
	## refuses.
	send_review : State, Str -> State
	send_review = |state, pane_id| {
		shown = Model.pane(state, pane_id)
		session_id = Model.session_of(state, shown)
		context = Context.to_str(Model.context_of(state, shown))
		if session_id.is_empty() or session_id.starts_with("starting:") {
			{ ..state, notice: "There is no agent to send the review to." }
		} else if Review.drafts(Model.review_of(state, Model.context_of(state, shown))) == 0 {
			{ ..state, notice: "There are no drafts to send." }
		} else {
			Model.ask_review(state, Send({ context, session_id }))
		}
	}

	## Shows the file or diff a thread is on, the Files pane for a file's and
	## the Changes pane for a diff's, with a reply to it open, focused,
	## which scrolls to it.
	jump_to_thread : State, { pane_id : Str, thread : Str } -> State
	jump_to_thread = |state, { pane_id, thread }| {
		found = Model.review_of(state, Model.context_of(state, Model.pane(state, pane_id))).threads.find_first(|shown| shown.id == thread)
		target = |widget| Model.panes(state).find_first(|shown| shown.widget == widget).map_ok(|shown| shown.id)
		diff = |changes_id, scope, path| Ok((Model.show_git(state, changes_id, scope, Selected(path)), changes_id))
		opened =
			match (found.map_ok(|shown| shown.anchor), target("files"), target("changes")) {
				(Ok({ scope: File, path, .. }), Ok(files_id), _) => Ok((Model.show_file(state, files_id, path), files_id))
				(Ok({ scope: Uncommitted, path, .. }), _, Ok(changes_id)) => diff(changes_id, Uncommitted, path)
				(Ok({ scope: AgainstBase, path, .. }), _, Ok(changes_id)) => diff(changes_id, AgainstBase, path)
				(Ok({ scope: Commit(sha), path, .. }), _, Ok(changes_id)) => diff(changes_id, Commit(sha), path)
				_ => Err(NoPane)
			}
		match opened {
			Ok((showing, target_id)) => Model.compose(Model.activate_tab(showing, target_id), { pane_id: target_id, thread, editing: "" })
			Err(NoPane) => state
		}
	}

	## Opens a Workspaces pane's form: from a workspace's row, or a session's
	## alone in its workspace, to start an agent there of the first kind its
	## provider starts; from a project's,
	## to create a workspace of it, and from the pane's header (`key` ""), of
	## the first project. Other rows open none.
	open_form : State, { pane_id : Str, key : Str } -> State
	open_form = |state, { pane_id, key }| {
		project = if (key.is_empty()) state.workspaces.projects.first() else state.workspaces.projects.find_first(|listed| "group:${listed.id}" == key)
		placed = |session_id| state.workspaces.workspaces.find_first(|listed| listed.session_ids.contains(session_id)).map_ok(|listed| Workspace(listed.id)) ?? Session(session_id)
		match (Context.from_str(key).map_ok(|context| if (context == Session(key)) placed(key) else context), project) {
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
		serial = state.call_outbox.serial + 1
		optional = |text| if (text.trim().is_empty()) Err(Missing) else Ok(text.trim())
		prompt = form.prompt.trim()
		if form.kind == Agent {
			call : { capability : Str, request : Chat.Request }
			call = { capability: "chat.v1", request: Create({ place: Workspace(form.place), agent: form.agent, model: optional(form.model), prompt }) }
			title = if (prompt.is_empty()) "New ${form.agent} agent" else prompt.split_on("\n").first() ?? prompt
			started = { ..state, form: Model.closed_form, creating: state.creating.append({ serial, form, title, id: "" }), call_outbox: { serial, key: call.capability, text: Json.to_str(call) }, notice: "" }
			if (form.agent.is_empty()) { ..state, form: { ..form, failed: "Pick a kind of agent." } } else Model.open(started, Session(Model.starting_key(serial)))
		} else {
			call : { capability : Str, request : Workspaces.Request }
			call = { capability: "workspaces.v1", request: Create({ project_id: form.place, kind: if (form.worktree) Worktree else Checkout, branch: optional(form.branch) }) }
			title = optional(form.branch) ?? "New workspace"
			{ ..state, form: Model.closed_form, creating: state.creating.append({ serial, form, title, id: "" }), call_outbox: { serial, key: call.capability, text: Json.to_str(call) }, notice: "" }
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

	## The rooms as the daemon last listed them, with the joins and leaves on
	## their way applied.
	rooms_listed : State -> List(Rooms.Room)
	rooms_listed = |state| {
		joined = |listed, room_id, member| listed.map(|room| if (room.id == room_id) { ..room, joined: member } else room)
		state.room_asks.fold(
			state.rooms,
			|listed, asked|
				match asked.request {
					Join({ room_id }) => joined(listed, room_id, Bool.True)
					Leave({ room_id }) => joined(listed, room_id, Bool.False)
					_ => listed
				},
		)
	}

	## Whether a join or leave of a room is on its way.
	joining : State, Str -> Bool
	joining = |state, room_id| state.room_asks.any(|asked| asked.request == Join({ room_id: room_id }) or asked.request == Leave({ room_id: room_id }))

	## Joins a room you aren't in, or leaves one you are, shown at once.
	toggle_joined : State, Str -> State
	toggle_joined = |state, room_id|
		match Model.rooms_listed(state).find_first(|room| room.id == room_id) {
			Ok(room) if !Model.joining(state, room_id) => Model.ask_rooms(state, if (room.joined) Leave({ room_id: room_id }) else Join({ room_id: room_id }))
			_ => state
		}

	room_pane : State, Str -> RoomPane
	room_pane = |state, pane_id| state.room_panes.find_first(|shown| shown.pane == pane_id) ?? { pane: pane_id, room_id: "", root: "" }

	## Opens a room in a Rooms pane, or with "" the list of rooms again.
	open_room : State, { pane_id : Str, room_id : Str } -> State
	open_room = |state, { pane_id, room_id }| { ..state, room_panes: state.room_panes.drop_if(|shown| shown.pane == pane_id).append({ pane: pane_id, room_id, root: "" }) }

	## Opens a thread beside the room a Rooms pane shows, by its root, or
	## closes it with "".
	open_thread : State, { pane_id : Str, root : Str } -> State
	open_thread = |state, { pane_id, root }| { ..state, room_panes: state.room_panes.map(|shown| if (shown.pane == pane_id) { ..shown, root } else shown) }

	## A room as listed, or as its id alone tells.
	room_of : State, Str -> Rooms.Room
	room_of = |state, room_id| Model.rooms_listed(state).find_first(|room| room.id == room_id) ?? Rooms.room({ id: room_id, provider: "", name: room_id, kind: Channel })

	## The entries of a room's messages, or of a thread in it by its root.
	room_log : State, Str, Str -> List(Rooms.Entry)
	room_log = |state, room_id, root| state.room_logs.find_first(|log| log.room_id == room_id and log.root == root).map_ok(|log| log.entries) ?? []

	## Whether a room's messages, or a thread's, have arrived.
	room_loaded : State, Str, Str -> Bool
	room_loaded = |state, room_id, root| state.room_logs.any(|log| log.room_id == room_id and log.root == root)

	## A room's or thread's log with the entries after those it has.
	logged : State, Str, Str, List(Rooms.Entry) -> State
	logged = |state, room_id, root, arrived| {
		known = Model.room_log(state, room_id, root)
		last = known.last().map_ok(|entry| entry.sequence) ?? 0
		{ ..state, room_logs: state.room_logs.drop_if(|log| log.room_id == room_id and log.root == root).append({ room_id, root, entries: known.concat(arrived.keep_if(|entry| entry.sequence > last)) }) }
	}

	room_members_of : State, Str -> List(Rooms.Member)
	room_members_of = |state, room_id| state.room_members.find_first(|known| known.room_id == room_id).map_ok(|known| known.members) ?? []

	## A room's member as its members topic tells, or as its id alone does.
	room_member : State, Str, Str -> Rooms.Member
	room_member = |state, room_id, member_id| Model.room_members_of(state, room_id).find_first(|known| known.id == member_id) ?? { id: member_id, provider: "", name: member_id, picture: Err(Missing), kind: Person, role: Member, presence: Unknown }

	## The names of the other members of the room a draft is for (by its
	## key, as `send_to_room` takes it) that start with the mention it ends
	## with, such as Scout for "@sc"; none if it ends with none.
	mention_choices : State, Str -> List(Str)
	mention_choices = |state, key| {
		room_id = Model.room_pane(state, key.drop_suffix("/thread")).room_id
		me = Model.room_of(state, room_id).me ?? ""
		match mention_typed(Model.draft(state, key)) {
			Ok({ typed, .. }) => Model.room_members_of(state, room_id).keep_if(|member| member.id != me and member.name.with_ascii_lowercased().starts_with(typed.with_ascii_lowercased())).map(|member| member.name)
			Err(NoMention) => []
		}
	}

	## Mentions a member as @Name in place of the mention a draft ends with.
	mention : State, { key : Str, name : Str } -> State
	mention = |state, { key, name }|
		match mention_typed(Model.draft(state, key)) {
			Ok({ before, .. }) => { ..Model.set_draft(state, key, "${before}@${name} "), drafts_rewritten: { pane: key, count: state.drafts_rewritten.count + 1 } }
			Err(NoMention) => state
		}

	## The ids of a room's members a message mentions as @Name.
	mentioned : State, Str, Str -> List(Str)
	mentioned = |state, room_id, text| {
		lowered = text.with_ascii_lowercased()
		Model.room_members_of(state, room_id).keep_if(|member| lowered.contains("@${member.name.with_ascii_lowercased()}")).map(|member| member.id)
	}

	## The top-level messages of the room a Rooms pane opened, by their times.
	room_lines : State, Str -> List(RoomLine)
	room_lines = |state, pane_id| {
		room_id = Model.room_pane(state, pane_id).room_id
		log = Model.room_log(state, room_id, "")
		threads = Rooms.threads(log)
		by_time(Rooms.messages(log).keep_if(|posted| posted.place == TopLevel)).map(|posted| { ..Model.room_line(state, posted, threads), threaded: Bool.True }).concat(Model.sending_lines(state, room_id, ""))
	}

	## The thread a Rooms pane opened: its top-level message, then its
	## replies by their times.
	thread_lines : State, Str -> List(RoomLine)
	thread_lines = |state, pane_id| {
		{ room_id, root, .. } = Model.room_pane(state, pane_id)
		posted = Rooms.messages(Model.room_log(state, room_id, "")).keep_if(|message| message.id == root).concat(by_time(Rooms.messages(Model.room_log(state, room_id, root)).keep_if(|message| message.place != TopLevel)))
		posted.map(|message| Model.room_line(state, message, [])).concat(Model.sending_lines(state, room_id, root))
	}

	## The messages sent to a room's top level, or to a thread by its root,
	## that no log has posted yet.
	sending_lines : State, Str, Str -> List(RoomLine)
	sending_lines = |state, room_id, root| {
		me = Model.room_of(state, room_id).me ?? ""
		state.room_asks.keep_oks(
			|asked|
				match asked.request {
					Send(sent) if sent.room_id == room_id and (if (root.is_empty()) sent.place == TopLevel else sent.place != TopLevel and Rooms.root_of(Rooms.message({ id: "", room_id, author: me, text: "", time: "", place: sent.place, mentions: [] })) == root) => {
						line = Model.room_line(state, Rooms.message({ id: "sending:${asked.serial.to_str()}", room_id, author: me, text: sent.text, time: "", place: sent.place, mentions: sent.mentions }), [])
						Ok({ ..line, author: if (Model.room_members_of(state, room_id).any(|member| member.id == me)) line.author else "You", status: if (asked.failed.is_empty()) "Sending…" else "Not sent: ${asked.failed}", failed: !asked.failed.is_empty(), serial: asked.serial })
					}
					_ => Err(NotSent)
				},
		)
	}

	room_line : State, Rooms.Message, List(Rooms.Thread) -> RoomLine
	room_line = |state, posted, threads| {
		author = Model.room_member(state, posted.room_id, posted.author)
		me = Model.room_of(state, posted.room_id).me ?? ""
		thread = threads.find_first(|summary| summary.root == posted.id) ?? { root: posted.id, replies: 0, last_reply: Err(Missing), participants: [] }
		{
			id: posted.id,
			author: author.name,
			agent: author.kind != Person,
			ago: Model.ago(state, posted.time),
			time: posted.time,
			text: posted.text,
			edited: posted.edited,
			deleted: posted.deleted,
			reactions: Model.reactions_shown(state, posted, me),
			threaded: Bool.False,
			replies: thread.replies,
			repliers: Str.join_with(thread.participants.map(|member_id| Model.room_member(state, posted.room_id, member_id).name), ", "),
			last_reply: thread.last_reply.map_ok(|time| Model.ago(state, time)) ?? "",
			status: "",
			failed: Bool.False,
			serial: 0,
		}
	}

	## A message's reactions with yours on their way applied.
	reactions_shown : State, Rooms.Message, Str -> List({ emoji : Str, count : U64, mine : Bool, pending : Bool })
	reactions_shown = |state, posted, me| {
		reacting = state.room_asks.keep_oks(
			|asked|
				match asked.request {
					React({ message_id, emoji, .. }) if message_id == posted.id => Ok({ emoji, by: me, added: Bool.True })
					Unreact({ message_id, emoji, .. }) if message_id == posted.id => Ok({ emoji, by: me, added: Bool.False })
					_ => Err(NotReacting)
				},
		)
		reacting.fold(posted.reactions, Rooms.reacted).map(|reaction| { emoji: reaction.emoji, count: reaction.by.len(), mine: reaction.by.contains(me), pending: reacting.any(|asked| asked.emoji == reaction.emoji) })
	}

	## Reacts to a message in the room a Rooms pane opened with `emoji`, or
	## takes back your reaction if `mine`, shown at once.
	toggle_reaction : State, { pane_id : Str, message_id : Str, emoji : Str, mine : Bool } -> State
	toggle_reaction = |state, { pane_id, message_id, emoji, mine }| {
		room_id = Model.room_pane(state, pane_id).room_id
		Model.ask_rooms(state, if (mine) Unreact({ room_id, message_id, emoji }) else React({ room_id, message_id, emoji }))
	}

	## Who types in a room's messages, or a thread's, as "Scout is typing…":
	## those who said they type there and posted nothing since.
	typing : State, Str, Str -> Str
	typing = |state, room_id, root| {
		typists = Model.room_log(state, room_id, root).fold(
			[],
			|so_far, entry|
				match entry.event {
					Typing(typed) => if (so_far.contains(typed.member)) so_far else so_far.append(typed.member)
					Posted(posted) => so_far.drop_if(|typist| typist == posted.author)
					_ => so_far
				},
		)
		names = typists.map(|member_id| Model.room_member(state, room_id, member_id).name)
		match names {
			[] => ""
			[one] => "${one} is typing…"
			_ => "${Str.join_with(names, ", ")} are typing…"
		}
	}

	## Sends the draft of a Rooms pane's room, or of the thread it opened
	## (key "<pane>/thread"), shown at once as sending, with the members it
	## mentions, and clears it. An empty draft says it needs text.
	send_to_room : State, Str -> State
	send_to_room = |state, key| {
		pane_id = key.drop_suffix("/thread")
		{ room_id, root, .. } = Model.room_pane(state, pane_id)
		text = Model.draft(state, key).trim()
		sent_to = if (key == pane_id) TopLevel else Reply({ root, parent: root })
		cleared = { ..Model.set_draft(state, key, ""), drafts_rewritten: { pane: key, count: state.drafts_rewritten.count + 1 } }
		if (text.is_empty()) { ..state, notice: "A message needs text." } else Model.ask_rooms(cleared, Send({ room_id, text, place: sent_to, mentions: Model.mentioned(state, room_id, text) }))
	}

	## Sends a message the daemon refused again, or with `again` false gives
	## it up.
	resend : State, { serial : U64, again : Bool } -> State
	resend = |state, { serial, again }| {
		kept = { ..state, room_asks: state.room_asks.drop_if(|asked| asked.serial == serial) }
		match state.room_asks.find_first(|asked| asked.serial == serial) {
			Ok(asked) if again => Model.ask_rooms(kept, asked.request)
			_ => kept
		}
	}

	## Sends a rooms.v1 request, shown at once until the daemon answers.
	ask_rooms : State, Rooms.Request -> State
	ask_rooms = |state, request| {
		serial = state.call_outbox.serial + 1
		{ ..state, call_outbox: { serial, key: "rooms.v1", text: Json.to_str({ capability: "rooms.v1", request }) }, room_asks: state.room_asks.append({ serial, request, accepted: 0, message_id: "", failed: "" }), notice: "" }
	}

	## Without the messages sent that a log has posted.
	posted_sent : State -> State
	posted_sent = |state| {
		posted = |message_id|
			state.room_logs.any(
				|log|
					log.entries.any(
						|entry|
							match entry.event {
								Posted(message) => message.id == message_id
								_ => Bool.False
							},
					),
			)
		{ ..state, room_asks: state.room_asks.drop_if(|asked| !asked.message_id.is_empty() and posted(asked.message_id)) }
	}

	## Takes the daemon's answer to a rooms.v1 request: a message sent holds
	## until a log posts it, another request accepted until the poll it asks
	## for shows it; refused, a message stays with why it failed, and another
	## request is undone, with why.
	rooms_answered : State, U64, Str -> State
	rooms_answered = |state, serial, text| {
		answered : Try(Protocol.Answer(Rooms.Response), _)
		answered = Json.parse(text)
		sends = |asked|
			match asked.request {
				Send(_) => asked.serial == serial
				_ => Bool.False
			}
		undone = |reason| { ..state, room_asks: state.room_asks.drop_if(|asked| asked.serial == serial and !sends(asked)).map(|asked| if (sends(asked)) { ..asked, failed: reason } else asked), notice: reason }
		match answered {
			Ok(Ok(Sent({ message_id }))) => Model.poll(Model.posted_sent({ ..state, room_asks: state.room_asks.map(|asked| if (asked.serial == serial) { ..asked, message_id } else asked) }))
			Ok(Ok(Rejected(reason))) => undone(reason)
			Ok(Ok(_)) => Model.poll({ ..state, room_asks: state.room_asks.map(|asked| if (asked.serial == serial) { ..asked, accepted: state.poll.serial + 1 } else asked) })
			Ok(Err({ message, .. })) => undone(message)
			Err(_) => undone("The daemon did not answer.")
		}
	}

	## What a pane's body shows: its widget, a wait for the daemon's manifest,
	## a placeholder naming what is missing, or in the main area, a diff
	## opened there from Changes.
	## `NoView` is a widget's that liton has no view of yet.
	Body : [Sessions, Workspaces, Chat, Inbox, Changes, Files, Tickets, Rooms, Capabilities, Connecting, Missing, MainDiff, NoView]

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
		else if (shown.id == Model.main_area_pane(state) and !Model.main_diff(state).is_empty())
			MainDiff
		else
			match shown.widget {
				"sessions" => Sessions
				"workspaces" => Workspaces
				"chat" => Chat
				"inbox" => Inbox
				"changes" => Changes
				"files" => Files
				"tickets" => Tickets
				"rooms" => Rooms
				"capabilities" => Capabilities
				_ => NoView
			}
	}
}

# A Changes pane's git and review are followed only while it is on screen.
expect {
	state = { ..Model.initial(""), focus: Session("a") }
	Model.subjects(state) == [Sessions, Timeline("a"), Items, Changes({ context: Session("a"), scope: Uncommitted }), WorkspaceList, Agents, Threads(Session("a"))] and Model.subjects(Model.toggle_drawer(state, Right)) == [Sessions, Timeline("a"), Items, WorkspaceList, Agents]
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

# An answer names the provider's choice taken, and Allow or Deny none.
expect {
	plan = { ..Chat.permission({ request_id: "p", tool: "ExitPlanMode", description: "Plan" }), choices: Ok([{ id: "implement", label: "Implement", allows: Bool.True, style: Primary }]) }
	sent = |asked| Model.choices(asked).map(|choice| Model.answer(Model.initial(""), { session_id: "s", request_id: "p", choice }).outbox.request)
	sent(plan) == [AnswerPermission({ session_id: "s", request_id: "p", allowed: Bool.True, choice: Ok("implement") })] and sent({ ..plan, choices: Err(Missing) }) == [AnswerPermission({ session_id: "s", request_id: "p", allowed: Bool.True, choice: Err(Missing) }), AnswerPermission({ session_id: "s", request_id: "p", allowed: Bool.False, choice: Err(Missing) })]
}

# One poll at a time: what is asked meanwhile is sent once it answers.
expect {
	sent = Model.poll({ ..Model.initial(""), focus: Session("a") })
	meanwhile = Model.follow({ ..sent, focus: Session("b") })
	answered = Model.polled(meanwhile, sent.poll, [])
	Model.tick(sent, 0).poll.serial == 1 and Model.follow(sent).poll_again == Bool.False and meanwhile.poll.serial == 1 and answered.polling and answered.poll.subjects.contains(Timeline("b"))
}

expect {
	state = { ..Model.initial(""), focus: Session("a") }
	pinned = Model.toggle_pin(state, "pane-2")
	Model.session_of({ ..pinned, focus: Session("b") }, Model.pane(pinned, "pane-2")) == "a"
}

expect {
	saved = Json.to_str(Model.snapshot(Model.toggle_tabs(Model.initial(""), "pane-2")))
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
	Model.restore(saved).map_ok(Model.layout_of) == Ok({ shell: Tiling, columns: [{ id: "column-1", size: 1, tabbed: Bool.False, active: "pane-7", panes: [chat] }], collapsed: [], hidden: [] }) and Model.initial(saved).next_id == 8
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
	moved.columns.map(|column| column.panes.map(|pane| pane.id)) == [["pane-1", "pane-3"], ["pane-2"], ["pane-4", "pane-5"]] and moved.columns.map(|column| column.active) == ["pane-3", "pane-2", "pane-4"] and moved.collapsed == []
}

expect {
	state = Model.layout(Model.initial(""), Model.tiling)
	split = Model.move_pane(Model.move_pane(state, "pane-2", Left), "pane-2", Left)
	Model.move_pane(state, "pane-1", Left).columns == state.columns and split.columns.map(|column| column.panes.map(|pane| pane.id)) == [["pane-2"], ["pane-1"], ["pane-3"]]
}

# A drop reorders a slot's tabs or moves a pane to another slot it fits, and
# in Tiling into a column or a new one beside it.
expect {
	state = Model.initial("")
	ids = |placed| placed.columns.map(|column| column.panes.map(|pane| pane.id))
	reordered = Model.place(state, "pane-4", { column: "column-3", at: Before("pane-3") })
	tiling = Model.layout(state, Model.tiling)
	beside = Model.place(tiling, "pane-3", { column: "column-1", at: NewLeft })
	ids(reordered) == [["pane-1"], ["pane-2"], ["pane-4", "pane-3", "pane-5"]]
		and reordered.columns.map(|column| column.active) == ["pane-1", "pane-2", "pane-4"]
		and ids(Model.place(state, "pane-4", { column: "column-2", at: After("pane-2") })) == [["pane-1"], ["pane-2", "pane-4"], ["pane-3", "pane-5"]]
		and ids(beside) == [["pane-3"], ["pane-1"], ["pane-2"]]
		and beside.active_column == beside.columns.first().map_ok(|column| column.id) ?? ""
		and ids(Model.place(tiling, "pane-1", { column: "column-2", at: End })) == [["pane-2", "pane-1"], ["pane-3"]]
}

# Only a drop that moves a pane where it fits places it.
expect {
	state = Model.initial("")
	tiling = Model.layout(state, Model.tiling)
	allowed = |placed, id, wanted| Model.drop_place(placed, id, wanted) == wanted
	allowed(state, "pane-4", { column: "column-3", at: Before("pane-3") })
		and allowed(state, "pane-4", { column: "column-2", at: End })
		and !allowed(state, "pane-2", { column: "column-1", at: End })
		and !allowed(state, "pane-4", { column: "column-3", at: End })
		and !allowed(state, "pane-4", { column: "column-3", at: After("pane-4") })
		and !allowed(state, "pane-4", { column: "column-3", at: NewLeft })
		and allowed(tiling, "pane-1", { column: "column-3", at: NewRight })
		and !allowed(tiling, "pane-1", { column: "column-1", at: NewRight })
		and !allowed(tiling, "pane-1", { column: "column-9", at: End })
}

expect {
	closed = Model.close_pane({ ..Model.layout(Model.initial(""), Model.tiling), active_column: "column-2" }, "pane-2")
	closed.columns.map(|column| column.id) == ["column-1", "column-3"] and closed.active_column == "column-1"
}

expect {
	state = Model.add_pane(Model.close_pane(Model.initial(""), "pane-1"), "ci")
	state.columns.map(|column| column.panes.map(|pane| pane.widget)) == [[], ["chat", "ci"], ["changes", "files", "tickets"]] and state.active_column == "column-2"
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

# Focused on a workspace, Changes follows its git, and the chat its session
# that needs you most; a pane pinned then stays on the workspace.
expect {
	placed = |id, status| { ..Chat.session({ id, provider: "mock", agent: "claude", title: id, status }), workspace: Ok({ id: Ok("w1"), directory: "/w" }) }
	state = { ..Model.initial(""), focus: Workspace("w1"), sessions: [placed("a", Idle), placed("b", AwaitingPermission)] }
	pinned = Model.toggle_pin(state, "pane-3")
	Model.subjects(state) == [Sessions, Timeline("b"), Items, Changes({ context: Workspace("w1"), scope: Uncommitted }), WorkspaceList, Agents, Threads(Workspace("w1"))] and Model.pane(pinned, "pane-3").pinned == "workspace:w1" and Model.context_of({ ..pinned, focus: Session("a") }, Model.pane(pinned, "pane-3")) == Workspace("w1")
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
	keys(state) == ["group:p1", "s1", "workspace:w2"]
		and keys(folded) == ["group:p1"]
		and keys(Model.pick_row(folded, { pane_id: "pane-4", key: "group:p1" })) == keys(state)
		and keys(by_status) == ["group:waiting for you", "workspace:w2", "group:idle", "s1"]
		and keys({ ..state, sessions: state.sessions.append(Chat.session({ id: "s2", provider: "mock", agent: "claude", title: "Docs", status: Idle })), workspaces: { ..listed, workspaces: [workspace("w1", Idle, ["s1", "s2"])] } }) == ["group:p1", "workspace:w1", "s1", "s2"]
		and keys(Model.set_option(state, "pane-4", "show_idle", "false")) == ["group:p1", "workspace:w2"]
		and Model.pick_row(state, { pane_id: "pane-4", key: "workspace:w1" }).focus == Workspace("w1")
		and Model.workspace_rows(state, Model.pane(state, "pane-4")).map(|row| row.counts) == [{ ..Model.no_counts, members: "2" }, { members: "", added: "+2", removed: "−1" }, { members: "", added: "+2", removed: "−1" }]
		and Model.subjects(state).contains(WorkspaceList)
}

## A Files pane's rows of `folder`, `depth` folders deep, and of each folder
## open in it.
folder_rows : Model.State, Context.Id, Model.FilePane, Str, U64 -> List(Model.Row)
folder_rows = |state, context, shown, folder, depth| {
	blank = { key: "", kind: File, title: "", detail: "", counts: Model.no_counts, dot: "", status: "", age: "", focused: Bool.False, folded: Bool.False, creatable: Bool.False, pinned: Bool.False, depth }
	entries =
		match state.trees.find_first(|known| known.context == context and known.tree.path == folder).map_ok(|known| known.tree.listing) {
			Ok(Listed(listed)) => listed.keep_if(|entry| entry.kind == Directory).concat(listed.drop_if(|entry| entry.kind == Directory))
			_ => []
		}
	entries.join_map(
		|entry| {
			path = if (folder == ".") entry.name else "${folder}/${entry.name}"
			match entry.kind {
				Directory if shown.folders.contains(path) => folder_rows(state, context, shown, path, depth + 1).prepend({ ..blank, key: "dir:${path}", kind: Folder, title: entry.name })
				Directory => [{ ..blank, key: "dir:${path}", kind: Folder, title: entry.name, folded: Bool.True }]
				_ => [{ ..blank, key: "file:${path}", title: entry.name, detail: if (entry.kind == Symlink) "link" else "", focused: path == shown.file }]
			}
		},
	)
}

## The rows of the changed `files` in `folder`, `depth` folders deep: its
## folders first, each over its own rows unless folded, then its files.
changed_rows : List(WorkspaceGit.File), List(Str), Str, U64 -> List(Model.ChangedRow)
changed_rows = |files, folded, folder, depth| {
	inside = files.keep_if(|file| folder.is_empty() or file.path.starts_with("${folder}/"))
	rest = |file| if (folder.is_empty()) file.path else file.path.drop_prefix("${folder}/")
	child = |name| if (folder.is_empty()) name else "${folder}/${name}"
	names = inside.keep_oks(|file| rest(file).split_first("/").map_ok(|parts| parts.before)).fold([], |found, name| if (found.contains(name)) found else found.append(name))
	folders = names.join_map(
		|name| {
			path = child(name)
			under = files.keep_if(|file| file.path.starts_with("${path}/"))
			row = { path, folder: Bool.True, folded: folded.contains(path), depth, file: { path, change: Modified, additions: under.fold(0, |sum, file| file.additions + sum), deletions: under.fold(0, |sum, file| file.deletions + sum), body: Text } }
			if (row.folded) [row] else changed_rows(files, folded, path, depth + 1).prepend(row)
		},
	)
	folders.concat(inside.keep_if(|file| rest(file).split_first("/").is_err()).map(|file| { path: file.path, folder: Bool.False, folded: Bool.False, depth, file }))
}

## A size in bytes, as "4 KB" or "1.2 MB".
size_text : U64 -> Str
size_text = |bytes|
	if bytes < 1_000 {
		"${bytes.to_str()} bytes"
	} else if bytes < 1_000_000 {
		"${(bytes // 1_000).to_str()} KB"
	} else {
		"${(bytes // 1_000_000).to_str()}.${(bytes // 100_000 % 10).to_str()} MB"
	}

## A comment's state as its row says it.
comment_state : [Draft, Sent(U32)] -> Str
comment_state = |state|
	match state {
		Draft => "draft"
		Sent(round) => "sent in round ${round.to_str()}"
	}

## The mention a draft ends with, `@` and what is typed after it, and
## the draft before it.
mention_typed : Str -> Try({ before : Str, typed : Str }, [NoMention])
mention_typed = |text| {
	spaced = text.split_last(" ").map_ok(|parts| { before: "${parts.before} ", word: parts.after }) ?? { before: "", word: text }
	{ before, word } = spaced.word.split_last("\n").map_ok(|parts| { before: "${spaced.before}${parts.before}\n", word: parts.after }) ?? spaced
	if (word.starts_with("@")) Ok({ before, typed: word.drop_prefix("@") }) else Err(NoMention)
}

# "@sc" offers Scout, who replaces it, and the message sent mentions Scout.
expect {
	scout = { id: "scout", provider: "mock", name: "Scout", picture: Err(Missing), kind: Agent({ owner: Err(Missing) }), role: Member, presence: Online }
	state = { ..Model.initial(""), room_panes: [{ pane: "p", room_id: "general", root: "" }], room_members: [{ room_id: "general", members: [scout] }], drafts: [{ pane: "p", text: "thanks\n@sc" }] }
	chosen = Model.mention(state, { key: "p", name: "Scout" })
	Model.mention_choices(state, "p") == ["Scout"] and Model.draft(chosen, "p") == "thanks\n@Scout " and Model.send_to_room(chosen, "p").room_asks.map(|asked| asked.request) == [Send({ room_id: "general", text: "thanks\n@Scout", place: TopLevel, mentions: ["scout"] })]
}

## Messages in the order of their times, those alike as posted.
by_time : List(Rooms.Message) -> List(Rooms.Message)
by_time = |posted| {
	keyed = posted.map_with_index(|message, index| { message, index, at: epoch_ms(message.time) ?? 0 })
	keyed.sort_with(|left, right| if (left.at < right.at or (left.at == right.at and left.index < right.index)) Before else if (left.at == right.at and left.index == right.index) Same else After).map(|kept| kept.message)
}

## A UTC time such as `2026-01-01T08:00:00.000Z` in milliseconds since
## 1970, to the second.
epoch_ms : Str -> Try(I64, [NotTime])
epoch_ms = |time| {
	bytes = time.to_utf8()
	number = |from, length| bytes.sublist({ start: from, len: length }).fold(0, |sum, digit| sum * 10 + (digit - '0').to_i64())
	shaped = bytes.len() >= 19 and bytes.get(4) == Ok('-') and bytes.get(10) == Ok('T') and bytes.get(13) == Ok(':')
	if shaped {
		(month, day) = (number(5, 2), number(8, 2))
		year = if (month <= 2) number(0, 4) - 1 else number(0, 4)
		year_of_era = year % 400
		day_of_year = (153 * (if (month > 2) month - 3 else month + 9) + 2) // 5 + day - 1
		days = (year // 400) * 146_097 + year_of_era * 365 + year_of_era // 4 - year_of_era // 100 + day_of_year - 719_468
		Ok(((days * 24 + number(11, 2)) * 60 + number(14, 2)) * 60_000 + number(17, 2) * 1000)
	} else {
		Err(NotTime)
	}
}

# A row says how long ago its session changed, from the minute last begun.
expect {
	state = { ..Model.initial(""), now: epoch_ms("2026-01-01T10:00:59Z") ?? 0 }
	changed_at = |updated| Model.age(state, { ..Chat.session({ id: "s1", provider: "mock", agent: "claude", title: "Fix", status: Idle }), updated: Ok(updated) })
	[changed_at("2026-01-01T10:00:30.000Z"), changed_at("2026-01-01T09:57:00Z"), changed_at("2026-01-01T07:00:00Z"), changed_at("2025-12-30T10:00:00Z"), changed_at("2025-12-01T10:00:00Z"), changed_at("")] == ["now", "3m", "3h", "2d", "4w", ""]
}

expect epoch_ms("1970-01-01T00:00:00Z") == Ok(0) and epoch_ms("2026-01-01T08:00:30.000Z") == Ok(1_767_254_430_000) and epoch_ms("2000-03-01T00:00:00Z") == Ok(951_868_800_000) and epoch_ms("") == Err(NotTime)

## Text with its first letter a capital, as a group's title is written.
sentence_case : Str -> Str
sentence_case = |text| {
	bytes = text.to_utf8()
	match bytes.first() {
		Ok(first) if first >= 'a' and first <= 'z' => Str.from_utf8(bytes.drop_first(1).prepend(first - 32)) ?? text
		_ => text
	}
}

## A branch's name, "detached", or "" outside git.
branch_name : [Branch(Str), Detached, NotGit] -> Str
branch_name = |branch|
	match branch {
		Branch(name) => name
		Detached => "detached"
		NotGit => ""
	}

## Byte strings in order, as a dictionary orders words.
bytes_order : List(U8), List(U8) -> [Before, After, Same]
bytes_order = |left, right|
	match (left.first(), right.first()) {
		(Ok(first), Ok(second)) if first == second => bytes_order(left.drop_first(1), right.drop_first(1))
		(Ok(first), Ok(second)) => if (first < second) Before else After
		(Err(_), Ok(_)) => Before
		(Ok(_), Err(_)) => After
		_ => Same
	}

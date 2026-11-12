## The UI's state and every change to it, apart from the view so they can be
## tested without a browser.
import cap.Capability
import cap.Chat
import cap.Manifest
import Widgets

Model := [].{

	## `pinned` is the session a pane shows whatever the focus is, or "" to
	## follow the focus.
	Pane : { id : Str, widget : Str, pinned : Str }

	## Panes side by side make a row of columns. A column stacks its panes, or
	## when `tabbed` shows only its `active` one. `size` weighs its width.
	Column : { id : Str, size : U32, tabbed : Bool, active : Str, panes : List(Pane) }

	## How columns are laid out: freely in Tiling, or in a Workbench's three
	## slots, the left drawer, the main area and the right drawer.
	Shell : [Workbench, Tiling]

	Layout : { shell : Shell, columns : List(Column) }

	## Where a column sits: in a Workbench's slots, or anywhere in Tiling.
	Slot : [Left, Main, Right, Free]

	## The part of the model a snapshot saves: deterministic JSON others can load.
	Snapshot : { version : U32, shell : Shell, columns : List(Column) }

	Timeline : { session_id : Str, entries : List(Chat.Entry) }

	## A message or permission answer sent, until its session's timeline shows
	## it after the event numbered `after`. `failed` says why the daemon did not
	## take it, or is "" while it waits.
	Sent : { serial : U64, session_id : Str, request : Chat.Request, after : U64, failed : Str }

	State : {
		capabilities : List(Capability.Id),
		providers : List(Manifest.Provider),
		sessions : List(Chat.Session),
		timelines : List(Timeline),
		focus : Str,
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
		outbox : { serial : U64, request : Chat.Request },
		sent : List(Sent),

		## Counts each second, and each request the daemon accepts, so the UI
		## polls again.
		ticks : U64,
		notice : Str,
		show_settings : Bool,
		snapshot_text : Str,
	}

	## The Developer preset, the default: a Workbench of sessions, the chat
	## following the focus, and the focused session's changes beside what the
	## daemon advertises.
	developer : Layout
	developer = {
		shell: Workbench,
		columns: [
			{ id: "column-1", size: 1, tabbed: Bool.True, active: "pane-1", panes: [{ id: "pane-1", widget: "sessions", pinned: "" }] },
			{ id: "column-2", size: 1, tabbed: Bool.True, active: "pane-2", panes: [{ id: "pane-2", widget: "chat", pinned: "" }] },
			{ id: "column-3", size: 1, tabbed: Bool.True, active: "pane-3", panes: [{ id: "pane-3", widget: "changes", pinned: "" }, { id: "pane-4", widget: "capabilities", pinned: "" }] },
		],
	}

	## The Tiling preset: sessions, a wider chat and what the daemon advertises,
	## each in a column.
	tiling : Layout
	tiling = {
		shell: Tiling,
		columns: [
			{ id: "column-1", size: 1, tabbed: Bool.False, active: "pane-1", panes: [{ id: "pane-1", widget: "sessions", pinned: "" }] },
			{ id: "column-2", size: 2, tabbed: Bool.False, active: "pane-2", panes: [{ id: "pane-2", widget: "chat", pinned: "" }] },
			{ id: "column-3", size: 1, tabbed: Bool.False, active: "pane-3", panes: [{ id: "pane-3", widget: "capabilities", pinned: "" }] },
		],
	}

	initial : Str -> State
	initial = |saved|
		Model.layout(
			{
				capabilities: [],
				providers: [],
				sessions: [],
				timelines: [],
				focus: "",
				shell: Tiling,
				columns: [],
				collapsed: [],
				active_column: "",
				jump: { serial: 0, panel: "" },
				next_id: 1,
				drafts: [],
				outbox: { serial: 0, request: ListSessions },
				sent: [],
				ticks: 0,
				notice: "",
				show_settings: Bool.False,
				snapshot_text: "",
			},
			Model.restore(saved) ?? Model.developer,
		)

	## Shows a layout, counting ids on from the numbers ending theirs. A
	## Workbench shows its main area first.
	layout : State, Layout -> State
	layout = |state, { shell, columns }| {
		ids = columns.join_map(|column| column.panes.map(|pane| pane.id).append(column.id))
		next_id = ids.fold(1, |next, id| U64.max(next, (U64.from_str(id.split_last("-").map_ok(|parts| parts.after) ?? "") ?? 0) + 1))
		shown = if (shell == Workbench) columns.get(1) else columns.first()
		jump = { serial: state.jump.serial + 1, panel: if (shell == Workbench) Model.panel_ref(Main) else "" }
		{ ..state, shell, columns, next_id, collapsed: [], jump, active_column: shown.map_ok(|column| column.id) ?? "" }
	}

	snapshot : State -> Snapshot
	snapshot = |state| { version: 3, shell: state.shell, columns: state.columns }

	## The snapshot settings show, of the layout as it is now.
	with_snapshot_text : State -> State
	with_snapshot_text = |state| { ..state, snapshot_text: Json.to_str(Model.snapshot(state)) }

	## Reads a snapshot. A version 1 or 2 one loads in Tiling, a version 1 one
	## with a column for each pane, unless it holds just the old default's
	## widgets: then it loads the Developer preset.
	restore : Str -> Try(Layout, [Invalid])
	restore = |text| {
		current : Try(Snapshot, _)
		current = Json.parse(text)
		second : Try({ version : U32, columns : List(Column) }, _)
		second = Json.parse(text)
		first : Try({ version : U32, panes : List(Pane) }, _)
		first = Json.parse(text)
		match (current, second, first) {
			(Ok({ version: 3, shell, columns }), _, _) if shell == Tiling or columns.len() == 3 => Ok({ shell, columns })
			(_, Ok({ version: 2, columns }), _) => Ok(Model.migrated(columns))
			(_, _, Ok({ version: 1, panes })) => Ok(Model.migrated(panes.map_with_index(|pane, index| { id: "column-${(index + 1).to_str()}", size: 1, tabbed: Bool.False, active: pane.id, panes: [pane] })))
			_ => Err(Invalid)
		}
	}

	migrated : List(Column) -> Layout
	migrated = |columns|
		if (columns.map(|column| column.panes.map(|pane| pane.widget)) == [["sessions"], ["chat"], ["capabilities"]]) Model.developer else { shell: Tiling, columns }

	load_snapshot : State -> State
	load_snapshot = |state|
		match Model.restore(state.snapshot_text) {
			Ok(loaded) => { ..Model.layout(state, loaded), notice: "Loaded a layout of ${loaded.columns.len().to_str()} columns." }
			Err(Invalid) => { ..state, notice: "That is not a liton snapshot." }
		}

	advertise : State, Manifest.Advertised -> State
	advertise = |state, advertised| { ..state, providers: advertised.providers, capabilities: Manifest.capabilities(advertised) }

	## Every pane, column by column.
	panes : State -> List(Pane)
	panes = |state| state.columns.join_map(|column| column.panes)

	## A new pane of `widget`: a tab in a Workbench's main area, or a column of
	## its own at the end in Tiling.
	add_pane : State, Str -> State
	add_pane = |state, widget| {
		pane = { id: "pane-${state.next_id.to_str()}", widget, pinned: "" }
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

	## Pins a following pane to the focused session, or lets a pinned one follow.
	toggle_pin : State, Str -> State
	toggle_pin = |state, id| {
		pin = |pane| if (pane.id != id) pane else if (pane.pinned.is_empty()) { ..pane, pinned: state.focus } else { ..pane, pinned: "" }
		{ ..state, columns: state.columns.map(|column| { ..column, panes: column.panes.map(pin) }) }
	}

	pane : State, Str -> Pane
	pane = |state, id| Model.panes(state).find_first(|candidate| candidate.id == id) ?? { id, widget: "", pinned: "" }

	session_of : State, Pane -> Str
	session_of = |state, shown| if (shown.pinned.is_empty()) state.focus else shown.pinned

	entries : State, Str -> List(Chat.Entry)
	entries = |state, session_id|
		state.timelines.find_first(|timeline| timeline.session_id == session_id).map_ok(|timeline| timeline.entries) ?? []

	## A known session, or one named by its id until the daemon lists it.
	session : State, Str -> Chat.Session
	session = |state, session_id| state.sessions.find_first(|known| known.id == session_id) ?? { id: session_id, provider: "", agent: "", title: session_id, status: Idle }

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

	last_sequence : State, Str -> U64
	last_sequence = |state, session_id| Model.entries(state, session_id).last().map_ok(|entry| entry.sequence) ?? 0

	## What one poll asks for: each session a chat pane shows, after the last
	## event the UI has of it.
	watches : State -> List({ session_id : Str, after : U64 })
	watches = |state| {
		shown =
			Model.panes(state)
				.keep_if(|candidate| candidate.widget == "chat")
				.map(|candidate| Model.session_of(state, candidate))
				.drop_if(|session_id| session_id.is_empty())
		unique = shown.fold([], |found, session_id| if (found.contains(session_id)) found else found.append(session_id))
		unique.map(|session_id| { session_id, after: Model.last_sequence(state, session_id) })
	}

	## Takes a poll's answer: the sessions, and the events after those the UI
	## already has, so overlapping polls add nothing twice.
	polled : State, Chat.Polled -> State
	polled = |state, answer| {
		merged = answer.timelines.fold(
			state.timelines,
			|timelines, { session_id, entries: fresh }| {
				after = Model.last_sequence({ ..state, timelines }, session_id)
				added = fresh.keep_if(|entry| entry.sequence > after)
				if (timelines.any(|timeline| timeline.session_id == session_id))
					timelines.map(|timeline| if (timeline.session_id == session_id) { ..timeline, entries: timeline.entries.concat(added) } else timeline)
				else
					timelines.append({ session_id, entries: added })
			},
		)
		focus = if (state.focus.is_empty()) (answer.sessions.first().map_ok(|first| first.id) ?? "") else state.focus
		settled = { ..state, sessions: answer.sessions, timelines: merged, focus }
		{ ..settled, sent: settled.sent.drop_if(|sent| Model.confirmed(settled, sent)) }
	}

	## Whether a sent request's session's timeline shows it.
	confirmed : State, Sent -> Bool
	confirmed = |state, sent| {
		timeline = Model.entries(state, sent.session_id)
		match sent.request {
			SendMessage({ text, .. }) => timeline.any(|entry| entry.sequence > sent.after and entry.event == UserMessage({ text: text }))
			AnswerPermission({ request_id, .. }) => !Chat.pending_permissions(timeline).contains(request_id)
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
			_ => ""
		}
		sent = { serial, session_id, request, after: Model.last_sequence(state, session_id), failed: "" }
		{ ..state, outbox: { serial, request }, sent: state.sent.append(sent), notice: "" }
	}

	## Takes the daemon's refusal of a request: a message stays, failed with
	## `reason`, and a permission request's prompt comes back.
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

	## Sends a failed message again.
	retry : State, Str -> State
	retry = |state, serial|
		match state.sent.find_first(|sent| sent.serial.to_str() == serial) {
			Ok(failed) => Model.send({ ..state, sent: state.sent.drop_if(|sent| sent.serial == failed.serial) }, failed.request)
			Err(NotFound) => state
		}

	## What was sent to a session that its timeline does not show yet.
	unconfirmed : State, Str -> List(Sent)
	unconfirmed = |state, session_id| state.sent.keep_if(|sent| sent.session_id == session_id)

	## Whether a chat pane shows a session whose timeline has not arrived yet.
	loading : State, Str -> Bool
	loading = |state, session_id| !session_id.is_empty() and !state.timelines.any(|timeline| timeline.session_id == session_id)

	draft : State, Str -> Str
	draft = |state, pane_id| state.drafts.find_first(|candidate| candidate.pane == pane_id).map_ok(|found| found.text) ?? ""

	set_draft : State, Str, Str -> State
	set_draft = |state, pane_id, text| { ..state, drafts: state.drafts.drop_if(|found| found.pane == pane_id).append({ pane: pane_id, text }) }

	## Sends a pane's draft to the session the pane shows.
	submit : State, Str -> State
	submit = |state, pane_id| {
		text = Model.draft(state, pane_id).trim()
		session_id = Model.session_of(state, Model.pane(state, pane_id))
		if (text.is_empty() or session_id.is_empty())
			state
		else
			Model.send(Model.set_draft(state, pane_id, ""), SendMessage({ session_id, text }))
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

	## What a pane's body shows: its widget, a wait for the daemon's manifest,
	## or a placeholder naming what is missing.
	Body : [Sessions, Chat, Capabilities, Connecting, Missing]

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
				"chat" => Chat
				_ => Capabilities
			}
	}
}

expect {
	state = Model.initial("")
	Model.watches({ ..state, focus: "a" }) == [{ session_id: "a", after: 0 }]
}

expect {
	state = { ..Model.initial(""), focus: "a" }
	answer = { sessions: [], timelines: [{ session_id: "a", entries: [{ sequence: 1, event: StatusChanged(Running) }] }] }
	twice = Model.polled(Model.polled(state, answer), answer)
	Model.entries(twice, "a").len() == 1 and Model.watches(twice) == [{ session_id: "a", after: 1 }]
}

expect {
	state = { ..Model.initial(""), focus: "a" }
	pinned = Model.toggle_pin(state, "pane-2")
	Model.session_of({ ..pinned, focus: "b" }, Model.pane(pinned, "pane-2")) == "a"
}

expect {
	saved = Json.to_str(Model.snapshot(Model.toggle_tabs(Model.initial(""), "column-2")))
	Json.to_str(Model.snapshot(Model.initial(saved))) == saved
}

expect {
	saved = Json.to_str(Model.snapshot(Model.layout(Model.initial(""), Model.tiling)))
	Json.to_str(Model.snapshot(Model.initial(saved))) == saved
}

expect {
	saved = "{\"version\":1,\"panes\":[{\"id\":\"pane-7\",\"widget\":\"chat\",\"pinned\":\"\"}]}"
	chat = { id: "pane-7", widget: "chat", pinned: "" }
	Model.restore(saved) == Ok({ shell: Tiling, columns: [{ id: "column-1", size: 1, tabbed: Bool.False, active: "pane-7", panes: [chat] }] }) and Model.initial(saved).next_id == 8
}

expect {
	version_2 : List(Model.Column) -> Str
	version_2 = |columns| {
		old : { version : U32, columns : List(Model.Column) }
		old = { version: 2, columns }
		Json.to_str(old)
	}
	old_default = version_2(Model.tiling.columns.map(|column| { ..column, size: 3 }))
	Model.restore(old_default) == Ok(Model.developer) and Model.restore(version_2(Model.tiling.columns.drop_first(1))).map_ok(|layout| layout.shell) == Ok(Tiling)
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
	state.columns.map(|column| column.panes.map(|pane| pane.widget)) == [[], ["chat", "ci"], ["changes", "capabilities"]] and state.active_column == "column-2"
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

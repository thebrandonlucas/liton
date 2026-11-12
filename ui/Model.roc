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

	## The part of the model a snapshot saves: deterministic JSON others can load.
	Snapshot : { version : U32, panes : List(Pane) }

	Timeline : { session_id : Str, entries : List(Chat.Entry) }

	State : {
		capabilities : List(Capability.Id),
		providers : List(Manifest.Provider),
		sessions : List(Chat.Session),
		timelines : List(Timeline),
		focus : Str,
		panes : List(Pane),
		next_pane : U64,
		drafts : List({ pane : Str, text : Str }),
		outbox : { serial : U64, request : Chat.Request },
		ticks : U64,
		notice : Str,
		show_snapshot : Bool,
		snapshot_text : Str,
	}

	## The Developer preset: sessions, a chat following the focus, and what the
	## daemon advertises.
	preset : List(Pane)
	preset = [
		{ id: "pane-1", widget: "sessions", pinned: "" },
		{ id: "pane-2", widget: "chat", pinned: "" },
		{ id: "pane-3", widget: "capabilities", pinned: "" },
	]

	initial : Str -> State
	initial = |saved| {
		panes = Model.restore(saved) ?? Model.preset
		{
			capabilities: [],
			providers: [],
			sessions: [],
			timelines: [],
			focus: "",
			panes,
			next_pane: panes.len() + 1,
			drafts: [],
			outbox: { serial: 0, request: ListSessions },
			ticks: 0,
			notice: "",
			show_snapshot: Bool.False,
			snapshot_text: "",
		}
	}

	snapshot : State -> Snapshot
	snapshot = |state| { version: 1, panes: state.panes }

	restore : Str -> Try(List(Pane), [Invalid])
	restore = |text| {
		decoded : Try(Snapshot, _)
		decoded = Json.parse(text)
		match decoded {
			Ok({ version: 1, panes }) => Ok(panes)
			_ => Err(Invalid)
		}
	}

	load_snapshot : State -> State
	load_snapshot = |state|
		match Model.restore(state.snapshot_text) {
			Ok(panes) => { ..state, panes, next_pane: panes.len() + 1, notice: "Loaded a layout of ${panes.len().to_str()} panes." }
			Err(Invalid) => { ..state, notice: "That is not a version 1 liton snapshot." }
		}

	advertise : State, Manifest.Advertised -> State
	advertise = |state, advertised| { ..state, providers: advertised.providers, capabilities: Manifest.capabilities(advertised) }

	add_pane : State, Str -> State
	add_pane = |state, widget| {
		id = "pane-${state.next_pane.to_str()}"
		{ ..state, panes: state.panes.append({ id, widget, pinned: "" }), next_pane: state.next_pane + 1 }
	}

	close_pane : State, Str -> State
	close_pane = |state, id| { ..state, panes: state.panes.drop_if(|pane| pane.id == id) }

	## Pins a following pane to the focused session, or lets a pinned one follow.
	toggle_pin : State, Str -> State
	toggle_pin = |state, id| {
		pin = |pane| if (pane.id != id) pane else if (pane.pinned.is_empty()) { ..pane, pinned: state.focus } else { ..pane, pinned: "" }
		{ ..state, panes: state.panes.map(pin) }
	}

	pane : State, Str -> Pane
	pane = |state, id| state.panes.find_first(|candidate| candidate.id == id) ?? { id, widget: "", pinned: "" }

	session_of : State, Pane -> Str
	session_of = |state, shown| if (shown.pinned.is_empty()) state.focus else shown.pinned

	entries : State, Str -> List(Chat.Entry)
	entries = |state, session_id|
		state.timelines.find_first(|timeline| timeline.session_id == session_id).map_ok(|timeline| timeline.entries) ?? []

	last_sequence : State, Str -> U64
	last_sequence = |state, session_id| Model.entries(state, session_id).last().map_ok(|entry| entry.sequence) ?? 0

	## What one poll asks for: each session a chat pane shows, after the last
	## event the UI has of it.
	watches : State -> List({ session_id : Str, after : U64 })
	watches = |state| {
		shown =
			state.panes
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
		{ ..state, sessions: answer.sessions, timelines: merged, focus }
	}

	send : State, Chat.Request -> State
	send = |state, request| { ..state, outbox: { serial: state.outbox.serial + 1, request }, notice: "" }

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

	## The latest unanswered permission request in the session a pane shows.
	pending : State, Str -> Try({ session_id : Str, request_id : Str, tool : Str, description : Str }, [NoneWaiting])
	pending = |state, pane_id| {
		session_id = Model.session_of(state, Model.pane(state, pane_id))
		timeline = Model.entries(state, session_id)
		request_id = Chat.pending_permissions(timeline).last() ? |_| NoneWaiting
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

expect Model.restore(Json.to_str(Model.snapshot(Model.initial("")))) == Ok(Model.preset)

## The palette Ctrl+K or Cmd+K opens: the commands that apply now and the
## places to go, sessions, workspaces, rooms and tickets, filtered by what
## is typed.
import Commands
import Keymap
import Model
import TicketDesk

Palette := [].{

	## An entry, by a `key` that says what running it does: `command:<id>`,
	## `session:<id>`, `workspace:<id>`, `room:<id>` or `ticket:<id>`.
	## `keys` is how its binding is written, "" for none, and `picked`
	## whether Enter runs it.
	Entry : { key : Str, title : Str, group : Str, keys : Str, picked : Bool }

	## Every entry: the commands that apply, then the sessions, the
	## workspaces and `other_places`.
	entries : Model.State -> List(Entry)
	entries = |state| {
		entry = |key, title, group, keys| { key, title, group, keys, picked: Bool.False }
		order = Commands.workspace_order(state)
		workspace_keys = |workspace_id| order.find_first_index(|listed| listed == workspace_id).map_ok(|index| Keymap.text_of(Keymap.defaults, "workspace.${(index + 1).to_str()}")) ?? ""
		project_name = |project_id| state.workspaces.projects.find_first(|project| project.id == project_id).map_ok(|project| " in ${project.name}") ?? ""
		Commands.all(state)
			.keep_if(|command| !command.id.starts_with("workspace.") and (command.applies)(state))
			.map(|command| entry("command:${command.id}", command.title, command.group, Keymap.text_of(Keymap.defaults, command.id)))
			.concat(state.sessions.map(|session| entry("session:${session.id}", session.title, "Session", "")))
			.concat(state.workspaces.workspaces.map(|workspace| entry("workspace:${workspace.id}", workspace.name, "Workspace${project_name(workspace.project_id)}", workspace_keys(workspace.id))))
			.concat(Palette.other_places(state))
	}

	## Rooms and tickets, while a Rooms or a Tickets pane is in the layout to
	## open them in.
	other_places : Model.State -> List(Entry)
	other_places = |state| {
		entry = |key, title, group| { key, title, group, keys: "", picked: Bool.False }
		laid_out = |widget| Model.panes(state).any(|pane| pane.widget == widget)
		rooms = if (laid_out("rooms")) Model.rooms_listed(state).map(|room| entry("room:${room.id}", room.name, "Room")) else []
		tickets = if (laid_out("tickets")) TicketDesk.listing_shown(state.tickets).tickets.map(|ticket| entry("ticket:${ticket.id}", "${ticket.key} ${ticket.title}", "Ticket")) else []
		rooms.concat(tickets)
	}

	## Opens a room or a ticket in the first Rooms or Tickets pane, shown.
	open_other_place : Model.State, Str -> Model.State
	open_other_place = |state, key| {
		in_pane = |widget, open| Model.panes(state).find_first(|pane| pane.widget == widget).map_ok(|pane| Palette.reveal(open(state, pane.id), pane.id)) ?? state
		if key.starts_with("room:") {
			in_pane("rooms", |opened, pane_id| Model.open_room(opened, { pane_id, room_id: key.drop_prefix("room:") }))
		} else if key.starts_with("ticket:") {
			in_pane("tickets", |opened, pane_id| Model.open_ticket(opened, { pane_id, ticket_id: key.drop_prefix("ticket:") }))
		} else {
			state
		}
	}

	## Shows a pane focused: out of hiding, its column's tab, its drawer
	## open, and its column on a narrow screen.
	reveal : Model.State, Str -> Model.State
	reveal = |state, pane_id| {
		revealed = Model.show_pane(state, pane_id)
		match state.columns.find_first(|column| column.panes.any(|listed| listed.id == pane_id)) {
			Ok(column) => Model.jump_to({ ..revealed, collapsed: revealed.collapsed.drop_if(|slot| slot == Model.slot_of(revealed, column.id)) }, column.id, Push)
			Err(NotFound) => revealed
		}
	}

	## How well what is typed matches a title, the lower the better: as its
	## start, a word's start, anywhere in it, or its letters in order.
	rank : Str, Str -> Try(U64, [NoMatch])
	rank = |query_typed, title| {
		(query, lowered) = (query_typed.trim().with_ascii_lowercased(), title.with_ascii_lowercased())
		in_order = query.to_utf8().fold(
			{ rest: lowered.to_utf8(), found: Bool.True },
			|so_far, byte| match so_far.rest.find_first_index(|candidate| candidate == byte) {
				Ok(index) => { ..so_far, rest: so_far.rest.drop_first(index + 1) }
				Err(NotFound) => { rest: [], found: Bool.False }
			},
		)
		if lowered.starts_with(query) {
			Ok(0)
		} else if lowered.contains(" ${query}") {
			Ok(1)
		} else if lowered.contains(query) {
			Ok(2)
		} else if in_order.found {
			Ok(3)
		} else {
			Err(NoMatch)
		}
	}

	## The entries what is typed matches, the best first (`rank`), then those
	## run latest, then as `entries` lists them; the one `picked` marked.
	shown : Model.State -> List(Entry)
	shown = |state| {
		compared = |left, right| if (left < right) Before else if (left > right) After else Same
		ran_at = |key| state.ran.find_first_index(|ran| ran == key) ?? state.ran.len()
		Palette.entries(state)
			.map_with_index(|entry, index| Palette.rank(state.palette.query, entry.title).map_ok(|matched| { entry, index, rank: matched, ran: ran_at(entry.key) }))
			.keep_oks(|ranked| ranked)
			.sort_with(|left, right| [compared(left.rank, right.rank), compared(left.ran, right.ran), compared(left.index, right.index)].find_first(|so_far| so_far != Same) ?? Same)
			.map_with_index(|ranked, index| { ..ranked.entry, picked: index == state.palette.picked })
	}

	## Takes what is typed, picking the best entry.
	typed : Model.State, Str -> Model.State
	typed = |state, query| { ..state, palette: { ..state.palette, query, picked: 0 } }

	## Picks the entry above or below the one picked, round from either end.
	move : Model.State, [Up, Down] -> Model.State
	move = |state, way| {
		count = Palette.shown(state).len()
		picked = state.palette.picked
		moved = if (count == 0) 0 else if (way == Down) (picked + 1) % count else if (picked == 0) count - 1 else picked - 1
		{ ..state, palette: { ..state.palette, picked: moved } }
	}

	## Closes the palette and runs an entry, which then lists first while
	## it matches.
	run : Model.State, Str -> Model.State
	run = |state0, key| {
		state = { ..state0, palette: { ..state0.palette, open: Bool.False }, ran: state0.ran.drop_if(|ran| ran == key).prepend(key).take_first(20) }
		if key.starts_with("command:") {
			Commands.run_first(state, [key.drop_prefix("command:")])
		} else if key.starts_with("session:") {
			Model.open(state, Session(key.drop_prefix("session:")))
		} else if key.starts_with("workspace:") {
			Model.open(state, Workspace(key.drop_prefix("workspace:")))
		} else {
			Palette.open_other_place(state, key)
		}
	}

	## Runs the entry picked, if any is shown.
	run_picked : Model.State -> Model.State
	run_picked = |state| Palette.shown(state).find_first(|entry| entry.picked).map_ok(|entry| Palette.run(state, entry.key)) ?? state
}

expect Palette.rank("ttings", "Open or close Settings") == Ok(2) and Palette.rank("open", "Open or close Settings") == Ok(0) and Palette.rank("close", "Open or close Settings") == Ok(1) and Palette.rank("ocs", "Open or close Settings") == Ok(3) and Palette.rank("xyz", "Open or close Settings") == Err(NoMatch)

# Typing filters, arrows pick, Enter runs, and what ran lists first after.
expect {
	opened = Commands.open_palette(Model.initial(""))
	settings = Palette.typed(opened, "settings")
	ran = Palette.run_picked(settings)
	again = Commands.open_palette(ran)
	settings.palette.picked == 0 and Palette.shown(settings).map(|entry| entry.key) == ["command:settings"] and ran.show_settings and !ran.palette.open and Palette.shown(again).first().map_ok(|entry| entry.key) == Ok("command:settings") and Palette.move(Palette.move(again, Up), Down).palette.picked == 0
}

expect !Keymap.pressed(Keymap.defaults, Commands.open_palette(Model.initial("")), "Escape").palette.open

## Every action keys run, by name: what it is called, the group it is
## listed under, when it applies and what it does to the model.
import cap.Review
import Model

Commands := [].{

	## `applies` says whether the command can run now, and `run` runs it.
	Command : { id : Str, title : Str, group : Str, applies : Model.State -> Bool, run : Model.State -> Model.State }

	## The commands, each preset's numbered by its place, the first's `preset.1`.
	all : Model.State -> List(Command)
	all = |state| {
		workbench = |shown| shown.shell == Workbench
		always = |_| Bool.True
		[
			{ id: "drawer.left", title: "Show or hide the left drawer", group: "View", applies: workbench, run: |shown| Model.toggle_drawer(shown, Left) },
			{ id: "drawer.right", title: "Show or hide the right drawer", group: "View", applies: workbench, run: |shown| Model.toggle_drawer(shown, Right) },
			{ id: "palette", title: "Open or close the palette", group: "View", applies: always, run: |shown| if (shown.palette.open) Commands.close(shown) else Commands.open_palette(shown) },
			{ id: "settings", title: "Open or close Settings", group: "View", applies: always, run: |shown| Model.with_snapshot_text({ ..shown, show_settings: !shown.show_settings }) },
			{ id: "shortcuts", title: "Show or hide the keys", group: "View", applies: always, run: |shown| { ..shown, show_shortcuts: !shown.show_shortcuts } },
			{ id: "close", title: "Close", group: "View", applies: Commands.closes, run: Commands.close },
			{ id: "thread.close", title: "Close the thread", group: "Rooms", applies: Commands.thread_open, run: |shown| Model.open_thread(shown, { pane_id: "", root: "" }) },
			{ id: "rooms.focus", title: "Go to the rooms", group: "Rooms", applies: |shown| Model.panes(shown).any(|pane| pane.widget == "rooms"), run: Model.focus_rooms },
			{ id: "agent.stop", title: "Stop the chat's agent", group: "Chat", applies: Commands.stops, run: |shown| Model.stop(shown, Commands.chat(shown).id) },
			{ id: "workspace.previous", title: "Go to the workspace before", group: "Workspaces", applies: |shown| Commands.workspace_order(shown).len() > 1, run: |shown| Commands.step_workspace(shown, -1) },
			{ id: "workspace.next", title: "Go to the workspace after", group: "Workspaces", applies: |shown| Commands.workspace_order(shown).len() > 1, run: |shown| Commands.step_workspace(shown, 1) },
			{ id: "tab.new", title: "Open the new tab menu", group: "Tabs", applies: |shown| !Model.tab_menu_items(shown).is_empty(), run: |shown| { ..shown, menu: if (shown.menu == Model.tab_menu) "" else Model.tab_menu } },
			{ id: "tab.close", title: "Close the tab", group: "Tabs", applies: |shown| Model.shown_closing_tab(shown).is_ok(), run: Model.close_shown_tab },
		]
			.concat(Commands.layout)
			.concat(Commands.review)
			.concat(state.presets.map_with_index(|preset, index| { id: "preset.${(index + 1).to_str()}", title: "Show the ${preset.name} preset", group: "Presets", applies: always, run: |shown| Model.with_snapshot_text(Model.use_preset(shown, preset.name)) }))
			.concat(Commands.workspace_order(state).map_with_index(|workspace_id, index| { id: "workspace.${(index + 1).to_str()}", title: "Go to workspace ${(index + 1).to_str()}", group: "Workspaces", applies: always, run: |shown| Model.open(shown, Workspace(workspace_id)) }))
	}

	## The layout's commands, each for a side: focus, move the pane focused,
	## swap, join into tabs and resize by the tile focused, and split it
	## right or down.
	layout : List(Command)
	layout = {
		sides = [(Left, "left", "on the left"), (Right, "right", "on the right"), (Up, "up", "above"), (Down, "down", "below")]
		beside = |side| |shown| Model.beside_focus(shown, side).is_ok()
		focused = |shown| Model.focused_tile(shown).is_ok()
		each_side = |name, title, applies, run| sides.map(|(side, word, placed)| { id: "layout.${name}-${word}", title: "${title} ${placed}", group: "Layout", applies: applies(side), run: |shown| run(shown, side) })
		[]
			.concat(each_side("focus", "Focus the tile", beside, Model.focus_beside))
			.concat(each_side("move", "Move the pane to the tile", |_| focused, Model.move_focused))
			.concat(each_side("swap", "Swap with the tile", beside, Model.swap_beside))
			.concat(each_side("join", "Join the tabs of the tile", beside, Model.join_beside))
			.concat(each_side("resize", "Move the tile's edge", |_| focused, Model.resize_focused))
			.concat([(Right, "right", "Split the pane off to the right"), (Down, "down", "Split the pane off below")].map(|(side, word, title)| { id: "layout.split-${word}", title, group: "Layout", applies: |shown| Model.tile_of(shown, shown.focused_pane).map_ok(|tile| tile.panes.len() > 1) ?? Bool.False, run: |shown| Model.split_focused(shown, side) }))
	}

	## The Review surface's commands, as crit.md's keys run them: on the
	## Review view on screen, step through its hunks and threads, comment on
	## what is focused, mark the file in view viewed and finish the review;
	## and submit or cancel the comment being written.
	review : List(Command)
	review = {
		viewing = |state| Model.review_shown(state).is_ok()
		on_view = |change| |state| Model.review_shown(state).map_ok(|view| change(state, view.id)) ?? state
		composing = |state| !state.composer.pane.is_empty()
		[
			{ id: "review.next-hunk", title: "Focus the next hunk", group: "Review", applies: viewing, run: on_view(|state, pane_id| Model.step_hunk(state, pane_id, Next)) },
			{ id: "review.previous-hunk", title: "Focus the previous hunk", group: "Review", applies: viewing, run: on_view(|state, pane_id| Model.step_hunk(state, pane_id, Previous)) },
			{ id: "review.next-comment", title: "Focus the next thread", group: "Review", applies: viewing, run: on_view(|state, pane_id| Model.step_thread(state, pane_id, Next)) },
			{ id: "review.previous-comment", title: "Focus the previous thread", group: "Review", applies: viewing, run: on_view(|state, pane_id| Model.step_thread(state, pane_id, Previous)) },
			{ id: "review.comment", title: "Comment on the lines or thread focused", group: "Review", applies: |state| viewing(state) and Commands.review_focused(state), run: on_view(Model.comment_focused) },
			{ id: "review.submit", title: "Keep the comment as a draft", group: "Review", applies: composing, run: Model.submit_comment },
			{ id: "review.cancel", title: "Cancel the comment", group: "Review", applies: composing, run: |state| { ..state, composer: Model.closed_composer } },
			{ id: "review.viewed", title: "Mark the file in view viewed", group: "Review", applies: |state| viewing(state) and !Model.review_focus(state).is_empty(), run: on_view(|state, pane_id| Model.toggle_viewed(state, { pane_id, path: Model.review_focus(state) })) },
			{ id: "review.finish", title: "Finish the review", group: "Review", applies: |state| Model.review_shown(state).map_ok(|view| Review.drafts(Model.review_of(state, Model.context_of(state, view))) > 0) ?? Bool.False, run: on_view(Model.finish_review) },
		]
	}

	## Whether a room's thread is open, rather than the Review surface's
	## focus.
	thread_open : Model.State -> Bool
	thread_open = |state|
		match state.sub_focus {
			Thread(_) => Bool.True
			_ => Bool.False
		}

	## Whether the Review surface has lines or a thread focused.
	review_focused : Model.State -> Bool
	review_focused = |state|
		match state.sub_focus {
			Lines(_) | ReviewThread(_) => Bool.True
			_ => Bool.False
		}

	## The workspaces by their ids, in the order the first Workspaces pane
	## shows them, else as listed.
	workspace_order : Model.State -> List(Str)
	workspace_order = |state| {
		listed = state.workspaces.workspaces
		match Model.panes(state).find_first(|shown| shown.widget == "workspaces") {
			Ok(shown) =>
				Model.workspace_rows(state, shown).keep_oks(
					|row|
						match row.kind {
							Workspace => Ok(row.key.drop_prefix("workspace:"))
							Session if row.depth == 0 => listed.find_first(|workspace| workspace.session_ids.contains(row.key)).map_ok(|workspace| workspace.id)
							_ => Err(NotFound)
						},
				)
			Err(NotFound) => listed.map(|workspace| workspace.id)
		}
	}

	## Goes to the workspace `by` places after the one focused in the order
	## of `workspace_order`, round from the end to the start, or the first.
	step_workspace : Model.State, I64 -> Model.State
	step_workspace = |state, by| {
		order = Commands.workspace_order(state)
		count = order.len().to_i64_wrap()
		at = match Model.focused(state, [Workspace]) {
			Workspace(workspace_id) => order.find_first_index(|listed| listed == workspace_id).map_ok(|index| index.to_i64_wrap()) ?? -1
			_ => -1
		}
		next = if (at < 0) 0 else (at + by + count) % count
		order.get(next.to_u64_wrap()).map_ok(|workspace_id| Model.open(state, Workspace(workspace_id))) ?? state
	}

	## Runs the first of the commands named that applies, if any does.
	run_first : Model.State, List(Str) -> Model.State
	run_first = |state, ids| {
		commands = Commands.all(state)
		match ids.join_map(|id| commands.keep_if(|command| command.id == id)).find_first(|command| (command.applies)(state)) {
			Ok(command) => (command.run)(state)
			Err(NotFound) => state
		}
	}

	## Opens the palette, empty, with what is typed in it focused.
	open_palette : Model.State -> Model.State
	open_palette = |state| { ..state, palette: { open: Bool.True, query: "", picked: 0 }, menu: "", jump: { serial: state.jump.serial + 1, panel: "palette", replace: "", push: "" } }

	## Whether something is open to close: the palette, the keys, a row's
	## renaming, a menu, Settings or a Workspaces pane's form.
	closes : Model.State -> Bool
	closes = |state| state.palette.open or state.show_shortcuts or !state.renaming.key.is_empty() or state.show_settings or !state.menu.is_empty() or state.form.kind != Closed

	## Closes the palette, else the keys, else leaves a row's renaming, else
	## closes a menu and Settings, else a Workspaces pane's form.
	close : Model.State -> Model.State
	close = |state|
		if state.palette.open {
			{ ..state, palette: { ..state.palette, open: Bool.False } }
		} else if state.show_shortcuts {
			{ ..state, show_shortcuts: Bool.False }
		} else if !state.renaming.key.is_empty() {
			{ ..state, renaming: Model.not_renaming }
		} else if state.show_settings or !state.menu.is_empty() {
			{ ..state, show_settings: Bool.False, menu: "" }
		} else {
			{ ..state, form: Model.closed_form }
		}

	## The chat focused, else the first.
	chat : Model.State -> Model.Pane
	chat = |state| {
		chats = Model.panes(state).keep_if(|shown| shown.widget == "chat")
		chats.find_first(|shown| shown.id == state.focused_pane) ?? (chats.first() ?? Model.pane(state, ""))
	}

	## Whether the agent of `chat`'s session is working and not being stopped.
	stops : Model.State -> Bool
	stops = |state| {
		session = Model.session(state, Model.session_of(state, Commands.chat(state)))
		Model.busy(session.status) and Model.stopping(state, session.id) != Stopping
	}
}

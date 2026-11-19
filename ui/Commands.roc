## Every action keys run, by name: what it is called, the group it is
## listed under, when it applies and what it does to the model.
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
			{ id: "agent.stop", title: "Stop the chat's agent", group: "Chat", applies: Commands.stops, run: |shown| Model.stop(shown, Commands.chat(shown).id) },
		]
			.concat(state.presets.map_with_index(|preset, index| { id: "preset.${(index + 1).to_str()}", title: "Show the ${preset.name} preset", group: "Presets", applies: always, run: |shown| Model.with_snapshot_text(Model.use_preset(shown, preset.name)) }))
			.concat(Commands.workspace_order(state).map_with_index(|workspace_id, index| { id: "workspace.${(index + 1).to_str()}", title: "Go to workspace ${(index + 1).to_str()}", group: "Workspaces", applies: always, run: |shown| Model.open(shown, Workspace(workspace_id)) }))
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

## The keys that run commands (ui/Commands.roc), as data: a key or a
## sequence of keys, Linear's `g` then `3`, for each command. A key is
## named as `Keymap.name` names it: `Mod+b` for Ctrl+B or Cmd+B, `Alt+1`,
## or the key itself, such as `g`, `?` or `Escape`.
import pf.Engine
import Commands
import Model

Keymap := [].{

	Binding : { keys : List(Str), command : Str }

	## Cmd with a letter is heard anywhere, Ctrl with one, as other keys,
	## only outside a text field, as Ctrl+B and Ctrl+E move the caret on a
	## Mac. 1 to 9, with or without Alt, show a preset, and `g` then 1 to 9
	## goes to a workspace. Escape closes what is open, else stops the agent.
	defaults : List(Binding)
	defaults = {
		digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
		[
			{ keys: ["Mod+b"], command: "drawer.left" },
			{ keys: ["Mod+e"], command: "drawer.right" },
			{ keys: ["Mod+,"], command: "settings" },
			{ keys: ["Mod+k"], command: "palette" },
			{ keys: ["?"], command: "shortcuts" },
			{ keys: ["Escape"], command: "close" },
			{ keys: ["Escape"], command: "agent.stop" },
		]
			.concat(digits.join_map(|digit| [{ keys: [digit], command: "preset.${digit}" }, { keys: ["Alt+${digit}"], command: "preset.${digit}" }]))
			.concat(digits.map(|digit| { keys: ["g", digit], command: "workspace.${digit}" }))
	}

	## The keys the page hears: Cmd's anywhere, Ctrl's and every other key
	## outside a text field, and Escape anywhere, with the browser's default
	## for those with Cmd or Ctrl prevented.
	heard : List(Binding) -> Engine.Keymap
	heard = |bindings| {
		chords = bindings.keep_oks(|binding| binding.keys.first()).keep_if(|key| key.starts_with("Mod+")).map(|key| Engine.Chord.plain(key.drop_prefix("Mod+")))
		Engine.Keymap.prevent(chords.map(|chord| chord.with_meta()))
			.concat(Engine.Keymap.prevent(chords.map(|chord| chord.with_ctrl())).outside_text())
			.concat(Engine.Keymap.keep([Engine.Chord.plain("Escape")]))
			.concat(Engine.Keymap.every.outside_text())
	}

	## A key's name in a binding. Option with a digit types ¡ to ª on a Mac.
	name : Engine.Key -> Str
	name = |key|
		if key.ctrl or key.meta {
			"Mod+${key.key.with_ascii_lowercased()}"
		} else if key.alt {
			digit = ["¡", "™", "£", "¢", "∞", "§", "¶", "•", "ª"].find_first_index(|glyph| glyph == key.key).map_ok(|index| (index + 1).to_str()) ?? key.key
			"Alt+${digit}"
		} else {
			key.key
		}

	## Takes a key pressed: runs the command its sequence completes, the
	## first bound that applies, or keeps it while it begins a longer one.
	## A key that ends no sequence begun starts again on its own; Escape
	## then only ends it. Shift, Ctrl, Alt and Cmd alone change nothing.
	pressed : List(Binding), Model.State, Str -> Model.State
	pressed = |bindings, state, key|
		if ["Shift", "Control", "Alt", "Meta"].contains(key) {
			state
		} else {
			typed = state.keys_typed.keys.append(key)
			cleared = { ..state, keys_typed: { ..state.keys_typed, keys: [] } }
			commands = Commands.all(state)
			exact = bindings.keep_if(|binding| binding.keys == typed).map(|binding| binding.command)
			if exact.any(|id| commands.any(|command| command.id == id and (command.applies)(state))) {
				Commands.run_first(cleared, exact)
			} else if bindings.any(|binding| binding.keys.len() > typed.len() and binding.keys.take_first(typed.len()) == typed) {
				{ ..state, keys_typed: { keys: typed, serial: state.keys_typed.serial + 1 } }
			} else if state.keys_typed.keys.is_empty() {
				state
			} else if key == "Escape" {
				cleared
			} else {
				Keymap.pressed(bindings, cleared, key)
			}
		}

	## Ends the sequence numbered `serial` if it is still being typed.
	paused : Model.State, U64 -> Model.State
	paused = |state, serial| if (state.keys_typed.serial == serial) { ..state, keys_typed: { ..state.keys_typed, keys: [] } } else state

	## How a binding's keys are written: Ctrl+B, Alt+1, G then 3.
	text : List(Str) -> Str
	text = |keys| {
		written = |key| {
			(modifier, rest) = if (key.starts_with("Mod+")) ("Ctrl+", key.drop_prefix("Mod+")) else if (key.starts_with("Alt+")) ("Alt+", key.drop_prefix("Alt+")) else ("", key)
			"${modifier}${if (rest.count_utf8_bytes() == 1) rest.with_ascii_uppercased() else rest}"
		}
		Str.join_with(keys.map(written), " then ")
	}

	## Each command bound, by its title, with its bindings written.
	listed : List(Binding), Model.State -> List({ title : Str, keys : Str })
	listed = |bindings, state|
		Commands.all(state).keep_oks(
			|command|
				match bindings.keep_if(|binding| binding.command == command.id).map(|binding| Keymap.text(binding.keys)) {
					[] => Err(Unbound)
					written => Ok({ title: command.title, keys: Str.join_with(written, " or ") })
				},
		)

	## How the first binding of a command is written, "" for none.
	text_of : List(Binding), Str -> Str
	text_of = |bindings, id| bindings.find_first(|binding| binding.command == id).map_ok(|binding| Keymap.text(binding.keys)) ?? ""
}

# 1 to 9, with Alt or without, show the presets in order, however the one
# shown was changed.
expect {
	state = Keymap.pressed(Keymap.defaults, Model.toggle_drawer(Model.initial(""), Right), "3")
	Model.preset_shown(state, "Tiling") and Model.preset_shown(Keymap.pressed(Keymap.defaults, Model.toggle_tabs(state, "pane-2"), "Alt+1"), "Developer") and Keymap.pressed(Keymap.defaults, state, "7") == state
}

# `g` waits for the key after it: a digit goes to that workspace, Escape
# or a pause ends it, and another key starts again on its own.
expect {
	listed = { ..Model.initial(""), workspaces: { projects: [{ id: "p1", provider: "mock", name: "app", directory: "/w" }], workspaces: [{ id: "w1", provider: "mock", project_id: "p1", name: "main", directory: "/w", kind: Checkout, branch: NotGit, state: Idle, dirty: Bool.False, changes: Uncounted, pinned: Bool.False, labels: [], session_ids: [] }] } }
	waiting = Keymap.pressed(Keymap.defaults, listed, "g")
	waiting.keys_typed.keys == ["g"] and Keymap.pressed(Keymap.defaults, waiting, "1").focus == Workspace("w1") and Keymap.pressed(Keymap.defaults, waiting, "Escape").keys_typed.keys == [] and Keymap.paused(waiting, waiting.keys_typed.serial).keys_typed.keys == [] and Model.preset_shown(Keymap.pressed(Keymap.defaults, waiting, "3"), "Tiling")
}

expect Keymap.text(["Mod+,"]) == "Ctrl+," and Keymap.text(["g", "3"]) == "G then 3" and Keymap.text(["Escape"]) == "Escape"

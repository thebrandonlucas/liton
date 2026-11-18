## A pane dragged by its tab or header to where `Model.place` puts it, as
## plain data apart from the view. Tabs (`tab:` and the pane's id), headers
## (`head:`), panes (`pane:`) and columns (`column:` and the column's id)
## are the pointer zones it drops on.
import pf.Engine
import Model

Drag := [].{

	## Nothing held; a press on the tab or header of pane `pane`, while the
	## pointer stays in the zone it pressed (`from`); then the drag, with
	## where dropping it places the pane.
	Gesture : [Idle, Pressed({ pane : Str, pointer : U32, from : Str }), Dragging({ pane : Str, pointer : U32, over : Model.Place })]

	idle : Gesture
	idle = Idle

	## A main-button mouse or pen press. A touch scrolls or taps, as on a
	## phone, where a Workbench shows one panel at a time.
	pressed : Gesture, Str, Engine.Pointer -> Gesture
	pressed = |gesture, pane, pointer|
		match (gesture, pointer.button, pointer.kind) {
			(Idle, Main, Mouse) | (Idle, Main, Pen) => Pressed({ pane, pointer: pointer.id, from: Drag.zone(pointer) })
			_ => gesture
		}

	## Leaving the zone pressed starts the drag, which then follows the place
	## under the pointer.
	moved : Gesture, Model.State, Engine.Pointer -> Gesture
	moved = |gesture, state, pointer|
		match gesture {
			Pressed(held) if held.pointer == pointer.id and Drag.zone(pointer) != held.from => Dragging({ pane: held.pane, pointer: held.pointer, over: Drag.place_at(state, held.pane, pointer) })
			Dragging(held) if held.pointer == pointer.id => Dragging({ ..held, over: Drag.place_at(state, held.pane, pointer) })
			_ => gesture
		}

	## The layout with the pane dragged placed where it is released, unless
	## that is nowhere.
	dropped : Model.State, Gesture, Engine.Pointer -> Model.State
	dropped = |state, gesture, pointer|
		match gesture {
			Dragging(held) if held.pointer == pointer.id => {
				place = Drag.place_at(state, held.pane, pointer)
				if (place.column.is_empty()) state else Model.place(state, held.pane, place)
			}
			_ => state
		}

	## A release or cancel of the pointer pressed ends the gesture.
	released : Gesture, Engine.Pointer -> Gesture
	released = |gesture, pointer|
		match gesture {
			Pressed({ pointer: id, .. }) | Dragging({ pointer: id, .. }) if id == pointer.id => Idle
			_ => gesture
		}

	## Escape leaves a drag.
	key_pressed : Gesture, Str -> Gesture
	key_pressed = |gesture, key| if (key == "Escape") Idle else gesture

	dragging : Gesture -> Bool
	dragging = |gesture|
		match gesture {
			Dragging(_) => Bool.True
			_ => Bool.False
		}

	## Where the drag would place its pane, nowhere while none is dragged.
	over : Gesture -> Model.Place
	over = |gesture|
		match gesture {
			Dragging(held) => held.over
			_ => Model.nowhere
		}

	zone : Engine.Pointer -> Str
	zone = |pointer|
		match pointer.at {
			In({ zone: name, .. }) => name
			Outside => ""
		}

	## Where dropping pane `id` under the pointer places it (`Model.drop_place`).
	place_at : Model.State, Str, Engine.Pointer -> Model.Place
	place_at = |state, id, pointer|
		match pointer.at {
			In({ zone: name, x, y }) => Model.drop_place(state, id, Drag.place_of(state, name, x, y))
			Outside => Model.nowhere
		}

	## The place a zone names at `x` and `y`, in ten thousandths of its box:
	## before or after a tab by its halves, before a stacked pane by its
	## header, before or after it by its halves, else at its column's end. In
	## Tiling, a pane's or column's outer sixths are a new column beside it.
	place_of : Model.State, Str, U16, U16 -> Model.Place
	place_of = |state, name, x, y| {
		(kind, key) = name.split_first(":").map_ok(|parts| (parts.before, parts.after)) ?? ("", "")
		match state.columns.find_first(|column| column.id == key or column.panes.any(|listed_pane| listed_pane.id == key)) {
			Ok(column) => {
				at = match kind {
					"tab" => if (x < 5000) Before(key) else After(key)
					_ if state.shell == Tiling and x < 1667 => NewLeft
					_ if state.shell == Tiling and x > 8333 => NewRight
					"head" if !column.tabbed => Before(key)
					"pane" if !column.tabbed => if (y < 5000) Before(key) else After(key)
					_ => End
				}
				{ column: column.id, at }
			}
			Err(NotFound) => Model.nowhere
		}
	}
}

# A tab's halves place before and after it, and Tiling's outer sixths of a
# pane a new column beside its own.
expect {
	state = Model.initial("")
	tiling = Model.layout(state, Model.tiling)
	[
		Drag.place_of(state, "tab:pane-3", 2000, 5000),
		Drag.place_of(state, "tab:pane-3", 8000, 5000),
		Drag.place_of(state, "pane:pane-2", 500, 5000),
		Drag.place_of(state, "column:column-1", 5000, 5000),
		Drag.place_of(tiling, "pane:pane-2", 500, 5000),
		Drag.place_of(tiling, "pane:pane-2", 5000, 7000),
		Drag.place_of(tiling, "head:pane-2", 5000, 7000),
		Drag.place_of(tiling, "column:column-3", 9000, 5000),
		Drag.place_of(state, "elsewhere", 5000, 5000),
	]
		== [
			{ column: "column-3", at: Before("pane-3") },
			{ column: "column-3", at: After("pane-3") },
			{ column: "column-2", at: End },
			{ column: "column-1", at: End },
			{ column: "column-2", at: NewLeft },
			{ column: "column-2", at: After("pane-2") },
			{ column: "column-2", at: Before("pane-2") },
			{ column: "column-3", at: NewRight },
			Model.nowhere,
		]
}

# A press drags once it leaves its tab, a drop places the pane, and a touch,
# another pointer or Escape drags nothing.
expect {
	state = Model.initial("")
	pointer : Engine.Pointer
	pointer = { id: 1, kind: Mouse, button: Main, buttons: 1, modifiers: { shift: Bool.False, ctrl: Bool.False, alt: Bool.False, meta: Bool.False }, primary: Bool.True, at: In({ zone: "tab:pane-4", x: 5000, y: 5000 }) }
	over_chat = { ..pointer, button: None, at: In({ zone: "pane:pane-2", x: 5000, y: 5000 }) }
	pressed = Drag.pressed(Idle, "pane-4", pointer)
	dragged = Drag.moved(Drag.moved(pressed, state, { ..pointer, button: None, at: In({ zone: "tab:pane-4", x: 9000, y: 5000 }) }), state, over_chat)
	dropped = Drag.dropped(state, dragged, over_chat)
	pressed == Pressed({ pane: "pane-4", pointer: 1, from: "tab:pane-4" })
		and Drag.over(dragged) == { column: "column-2", at: End }
		and dropped.columns.map(|column| column.panes.map(|pane| pane.id)) == [["pane-1"], ["pane-2", "pane-4"], ["pane-3", "pane-5"]]
		and Drag.dropped(state, pressed, over_chat).columns == state.columns
		and Drag.dropped(state, dragged, { ..over_chat, at: Outside }).columns == state.columns
		and Drag.released(dragged, over_chat) == Idle
		and Drag.released(dragged, { ..over_chat, id: 2 }) == dragged
		and Drag.moved(dragged, state, { ..over_chat, id: 2, at: Outside }) == dragged
		and Drag.pressed(Idle, "pane-4", { ..pointer, kind: Touch }) == Idle
		and Drag.key_pressed(dragged, "Escape") == Idle
}

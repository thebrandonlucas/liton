## A pane dragged by its tab or header to where `Model.place` puts it, as
## plain data apart from the view. Tabs (`tab:` and the pane's id), headers
## (`head:`), panes (`pane:`) and tiles (`tile:` and the tile's id) are the
## pointer zones it drops on.
import pf.Engine
import Model

Drag := [].{

	## Nothing held; a press on the tab or header of pane `pane`, while the
	## pointer stays in the zone it pressed (`from`); then the drag, with
	## where dropping it places the pane.
	Gesture : [Idle, Pressed({ pane : Str, pointer : U32, from : Str }), Dragging({ pane : Str, pointer : U32, over : Model.Drop })]

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
			Dragging(held) if held.pointer == pointer.id => Model.place(state, held.pane, Drag.place_at(state, held.pane, pointer))
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
	over : Gesture -> Model.Drop
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
	place_at : Model.State, Str, Engine.Pointer -> Model.Drop
	place_at = |state, id, pointer|
		match pointer.at {
			In({ zone: name, x, y }) => Model.drop_place(state, id, Drag.place_of(state, name, x, y))
			Outside => Model.nowhere
		}

	## Where a zone names at `x` and `y`, in ten thousandths of its box:
	## before or after a tab by its halves, into a tile's tabs by a header,
	## and by a pane or tile, beside it on the side of its outer sixth the
	## pointer is in, or else into its tabs.
	place_of : Model.State, Str, U16, U16 -> Model.Drop
	place_of = |state, name, x, y| {
		(kind, key) = name.split_first(":").map_ok(|parts| (parts.before, parts.after)) ?? ("", "")
		match state.grid.tiles.find_first(|tile| tile.id == key or tile.panes.any(|listed_pane| listed_pane.id == key)) {
			Ok(tile) =>
				match kind {
					"tab" => Into({ tile: tile.id, at: if (x < 5000) Before(key) else After(key) })
					"head" => Into({ tile: tile.id, at: End })
					_ if x < 1667 => Beside({ tile: tile.id, side: Left })
					_ if x > 8333 => Beside({ tile: tile.id, side: Right })
					_ if y < 1667 => Beside({ tile: tile.id, side: Up })
					_ if y > 8333 => Beside({ tile: tile.id, side: Down })
					_ => Into({ tile: tile.id, at: End })
				}
			Err(NotFound) => Model.nowhere
		}
	}
}

# A tab's halves place before and after it, a pane's outer sixths beside its
# tile, and its middle into its tabs.
expect {
	state = Model.initial("")
	[
		Drag.place_of(state, "tab:pane-3", 2000, 5000),
		Drag.place_of(state, "tab:pane-3", 8000, 5000),
		Drag.place_of(state, "pane:pane-2", 5000, 5000),
		Drag.place_of(state, "tile:tile-1", 5000, 5000),
		Drag.place_of(state, "pane:pane-2", 500, 5000),
		Drag.place_of(state, "pane:pane-2", 5000, 9000),
		Drag.place_of(state, "head:pane-2", 5000, 9000),
		Drag.place_of(state, "tile:tile-3", 9000, 5000),
		Drag.place_of(state, "elsewhere", 5000, 5000),
	]
		== [
			Into({ tile: "tile-3", at: Before("pane-3") }),
			Into({ tile: "tile-3", at: After("pane-3") }),
			Into({ tile: "tile-2", at: End }),
			Into({ tile: "tile-1", at: End }),
			Beside({ tile: "tile-2", side: Left }),
			Beside({ tile: "tile-2", side: Down }),
			Into({ tile: "tile-2", at: End }),
			Beside({ tile: "tile-3", side: Right }),
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
		and Drag.over(dragged) == Into({ tile: "tile-2", at: End })
		and dropped.grid.tiles.map(|tile| tile.panes.map(|pane| pane.id)) == [["pane-1"], ["pane-2", "pane-8", "pane-4"], ["pane-3", "pane-5"]]
		and Drag.dropped(state, pressed, over_chat).grid == state.grid
		and Drag.dropped(state, dragged, { ..over_chat, at: Outside }).grid == state.grid
		and Drag.released(dragged, over_chat) == Idle
		and Drag.released(dragged, { ..over_chat, id: 2 }) == dragged
		and Drag.moved(dragged, state, { ..over_chat, id: 2, at: Outside }) == dragged
		and Drag.pressed(Idle, "pane-4", { ..pointer, kind: Touch }) == Idle
		and Drag.key_pressed(dragged, "Escape") == Idle
}

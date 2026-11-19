## A pane dragged by its tab or header to where `Model.place` puts it, as
## plain data apart from the view. While it is dragged, the page reports the
## pointer (`pointer`, ui/ports.mjs): where it is, for the ghost following
## it, and the tile and tab under it as the layout was when the drag began,
## so the layout shown as if dropped there (`previewed`) doesn't move what
## the pointer is over.
import pf.Engine
import pf.Port
import Model

Drag := [].{

	## Nothing held; a press on the tab or header of pane `pane`; then the
	## drag, with the pointer as the page last reported it.
	Gesture : [Idle, Pressed({ pane : Str, pointer : U32 }), Dragging({ pane : Str, pointer : U32, at : Pointer })]

	## What the page reports of the pointer pressed: moved, released or
	## cancelled, where it is on the screen, in pixels, and the tile and tab
	## under it (their `data-tile` and `data-tab`) as the layout was when the
	## press began, with how far across and down that tab or tile it is, in
	## ten thousandths; "" outside them. It reports a release only after a
	## move.
	Pointer : { phase : [Moved, Released, Cancelled], x : I32, y : I32, tile : Str, tab : Str, across : U16, down : U16 }

	## The pointer pressed on a pane's tab or header, reported until it is
	## released.
	pointer : Port.Subscription({ pointer : U32 }, Pointer)
	pointer = Port.subscription({ name: "liton/drag/pointer", delivery: Latest })

	idle : Gesture
	idle = Idle

	## A main-button mouse or pen press. A touch scrolls or taps, as on a
	## phone, where a Workbench shows one panel at a time.
	pressed : Gesture, Str, Engine.Pointer -> Gesture
	pressed = |gesture, pane, pressing|
		match (gesture, pressing.button, pressing.kind) {
			(Idle, Main, Mouse) | (Idle, Main, Pen) => Pressed({ pane, pointer: pressing.id })
			_ => gesture
		}

	## A press released before it moved, which was a click.
	released : Gesture, Engine.Pointer -> Gesture
	released = |gesture, releasing|
		match gesture {
			Pressed({ pointer: id, .. }) if id == releasing.id => Idle
			_ => gesture
		}

	## The pane and pointer pressed, which the page reports on while held.
	held : Gesture -> [Holding({ pane : Str, pointer : U32 }), NotHolding]
	held = |gesture|
		match gesture {
			Pressed(holding) => Holding(holding)
			Dragging({ pane, pointer: id, .. }) => Holding({ pane, pointer: id })
			Idle => NotHolding
		}

	## A move drags the pane, and a release or cancel ends the gesture.
	heard : Gesture, Pointer -> Gesture
	heard = |gesture, at|
		match (gesture, at.phase) {
			(Pressed({ pane, pointer: id }), Moved) => Dragging({ pane, pointer: id, at })
			(Dragging({ pane, pointer: id, .. }), Moved) => Dragging({ pane, pointer: id, at })
			(_, Moved) => gesture
			_ => Idle
		}

	## The layout with the pane held put where it is released (`drop_at`).
	dropped : Model.State, { pane : Str, pointer : U32 }, Pointer -> Model.State
	dropped = |state, { pane, .. }, at| if (at.phase == Released) Model.place(state, pane, Drag.drop_at(state, pane, at)) else state

	## Escape leaves a drag.
	key_pressed : Gesture, Str -> Gesture
	key_pressed = |gesture, key| if (key == "Escape") Idle else gesture

	dragging : Gesture -> Bool
	dragging = |gesture|
		match gesture {
			Dragging(_) => Bool.True
			_ => Bool.False
		}

	## Where the drag would put its pane, nowhere while none is dragged.
	over : Model.State, Gesture -> Model.Drop
	over = |state, gesture|
		match gesture {
			Dragging({ pane, at, .. }) => Drag.drop_at(state, pane, at)
			_ => Model.nowhere
		}

	## The layout shown: while a pane is dragged, as if dropped where it is.
	previewed : Model.State, Gesture -> Model.State
	previewed = |state, gesture|
		match gesture {
			Dragging({ pane, .. }) => Model.place(state, pane, Drag.over(state, gesture))
			_ => state
		}

	## Where dropping pane `id` at `at` puts it (`Model.drop_place`): before
	## or after the tab under the pointer, by its halves; beside the tile
	## under it, on the side of the nearest edge if within a fifth of it;
	## else into that tile's tabs.
	drop_at : Model.State, Str, Pointer -> Model.Drop
	drop_at = |state, id, at| {
		across = at.across.to_u64().min(10000)
		down = at.down.to_u64().min(10000)
		nearest = [(Right, 10000 - across), (Up, down), (Down, 10000 - down)].fold((Left, across), |closest, (edge, away)| if (away < closest.1) (edge, away) else closest)
		wanted =
			if (at.tile.is_empty())
				Model.nowhere
			else if (!at.tab.is_empty())
				Into({ tile: at.tile, at: if (across < 5000) Before(at.tab) else After(at.tab) })
			else if (nearest.1 < 2000)
				Beside({ tile: at.tile, side: nearest.0 })
			else
				Into({ tile: at.tile, at: End })
		Model.drop_place(state, id, wanted)
	}
}

pointer_at : [Moved, Released, Cancelled], Str, Str, U16, U16 -> Drag.Pointer
pointer_at = |phase, tile, tab, across, down| { phase, x: 0, y: 0, tile, tab, across, down }

# A tab's halves put a pane before and after it, a tile's fifth by an edge
# beside it, and its middle into its tabs; outside the tiles, or where the
# pane doesn't fit, nowhere.
expect {
	state = Model.initial("")
	at = |tile, tab, across, down| Drag.drop_at(state, "pane-4", pointer_at(Moved, tile, tab, across, down))
	[at("tile-3", "pane-3", 2000, 5000), at("tile-3", "pane-3", 8000, 5000), at("tile-2", "", 5000, 5000), at("tile-2", "", 500, 5000), at("tile-2", "", 5000, 9000), at("tile-3", "", 5000, 9500), at("tile-3", "", 9500, 5000), at("", "", 5000, 5000)]
		== [
			Into({ tile: "tile-3", at: Before("pane-3") }),
			Into({ tile: "tile-3", at: After("pane-3") }),
			Into({ tile: "tile-2", at: End }),
			Beside({ tile: "tile-2", side: Left }),
			Beside({ tile: "tile-2", side: Down }),
			Beside({ tile: "tile-3", side: Down }),
			Model.nowhere,
			Model.nowhere,
		]
}

# While dragged, the layout shows the pane where it would drop; a release
# puts it there, and Escape, a cancel or a release outside the tiles leaves
# the layout as it was.
expect {
	state = Model.initial("")
	pressing : Engine.Pointer
	pressing = { id: 1, kind: Mouse, button: Main, buttons: 1, modifiers: { shift: Bool.False, ctrl: Bool.False, alt: Bool.False, meta: Bool.False }, primary: Bool.True, at: Outside }
	pressed = Drag.pressed(Idle, "pane-4", pressing)
	over_chat = pointer_at(Moved, "tile-2", "", 5000, 5000)
	dragged = Drag.heard(pressed, over_chat)
	below_main = Drag.heard(dragged, pointer_at(Moved, "tile-2", "", 5000, 9500))
	ids = |shown| shown.grid.tiles.map(|tile| tile.panes.map(|pane| pane.id))
	pressed == Pressed({ pane: "pane-4", pointer: 1 })
		and ids(Drag.previewed(state, dragged)) == [["pane-1"], ["pane-2", "pane-8", "pane-4"], ["pane-3", "pane-5"]]
		and Drag.previewed(state, below_main).grid.rows == [1, 1]
		and Drag.dropped(state, { pane: "pane-4", pointer: 1 }, { ..over_chat, phase: Released }) == Drag.previewed(state, dragged)
		and Drag.dropped(state, { pane: "pane-4", pointer: 1 }, { ..over_chat, phase: Cancelled }) == state
		and Drag.dropped(state, { pane: "pane-4", pointer: 1 }, pointer_at(Released, "", "", 0, 0)) == state
		and Drag.previewed(state, Drag.key_pressed(dragged, "Escape")) == state
		and Drag.heard(dragged, { ..over_chat, phase: Released }) == Idle
		and Drag.released(pressed, pressing) == Idle
		and Drag.released(dragged, pressing) == dragged
		and Drag.pressed(Idle, "pane-4", { ..pressing, kind: Touch }) == Idle
}

## A pane dragged by its tab or header to where `Model.place` puts it, as
## plain data apart from the view. While it is dragged, the page reports the
## pointer (`pointer`, ui/ports.mjs): where it is, for the ghost following
## it, and the tile and tab under it as the layout was when the drag began,
## so the layout shown as if dropped there (`previewed`) doesn't move what
## the pointer is over. A line between tiles is dragged alike, the tracks
## beside it resized as it moves.
import pf.Engine
import pf.Port
import Model

Drag := [].{

	## Nothing held; a press on the tab or header of pane `pane`; then the
	## drag, with the pointer as the page last reported it; or a line between
	## tiles held, and once moved how far across the two tracks beside it,
	## in ten thousandths, the pointer is.
	Gesture : [Idle, Pressed({ pane : Str, pointer : U32 }), Dragging({ pane : Str, pointer : U32, at : Pointer }), Resizing({ pointer : U32, line : Line, share : [Unmoved, At(U64)] })]

	## A column line or a row line of the grid, by its number.
	Line : [Across(U64), Down(U64)]

	## What the page reports of the pointer pressed: moved, released or
	## cancelled, where it is on the screen, in pixels, and the tile and tab
	## under it (their `data-tile` and `data-tab`) as the layout was when the
	## press began, with how far across and down that tab or tile it is, in
	## ten thousandths; "" outside them. While a line is held, `across` or
	## `down` is instead how far across the two tracks beside it the pointer
	## is. It reports a release only after a move.
	Pointer : { phase : [Moved, Released, Cancelled], x : I32, y : I32, tile : Str, tab : Str, across : U16, down : U16 }

	## The pointer pressed on a pane's tab or header, or on the column line
	## `column` or row line `row` (0 for neither), reported until it is
	## released.
	pointer : Port.Subscription({ pointer : U32, column : U64, row : U64 }, Pointer)
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

	## A main-button press on a line between tiles.
	pressed_line : Gesture, Line, Engine.Pointer -> Gesture
	pressed_line = |gesture, line, pressing|
		match (gesture, pressing.button, pressing.kind) {
			(Idle, Main, Mouse) | (Idle, Main, Pen) => Resizing({ pointer: pressing.id, line, share: Unmoved })
			_ => gesture
		}

	## A press released before it moved, which was a click.
	released : Gesture, Engine.Pointer -> Gesture
	released = |gesture, releasing|
		match gesture {
			Pressed({ pointer: id, .. }) | Resizing({ pointer: id, share: Unmoved, .. }) if id == releasing.id => Idle
			_ => gesture
		}

	## The pointer pressed and what it holds, a pane or a line, which the
	## page reports on while held.
	held : Gesture -> [Holding({ pointer : U32, pane : Str, column : U64, row : U64 }), NotHolding]
	held = |gesture|
		match gesture {
			Pressed({ pane, pointer: id }) | Dragging({ pane, pointer: id, .. }) => Holding({ pointer: id, pane, column: 0, row: 0 })
			Resizing({ pointer: id, line: Across(line), .. }) => Holding({ pointer: id, pane: "", column: line, row: 0 })
			Resizing({ pointer: id, line: Down(line), .. }) => Holding({ pointer: id, pane: "", column: 0, row: line })
			Idle => NotHolding
		}

	## A move drags the pane, and a release or cancel ends the gesture.
	heard : Gesture, Pointer -> Gesture
	heard = |gesture, at|
		match (gesture, at.phase) {
			(Pressed({ pane, pointer: id }), Moved) => Dragging({ pane, pointer: id, at })
			(Dragging({ pane, pointer: id, .. }), Moved) => Dragging({ pane, pointer: id, at })
			(Resizing(holding), Moved) => Resizing({ ..holding, share: At(Drag.share(holding.line, at)) })
			(_, Moved) => gesture
			_ => Idle
		}

	## How far across the tracks beside `line` the pointer is.
	share : Line, Pointer -> U64
	share = |line, at|
		match line {
			Across(_) => at.across.to_u64()
			Down(_) => at.down.to_u64()
		}

	## The layout with the pane held put where it is released (`drop_at`),
	## or the line held moved there.
	dropped : Model.State, { pointer : U32, pane : Str, column : U64, row : U64 }, Pointer -> Model.State
	dropped = |state, { pane, column, row, .. }, at|
		match at.phase {
			Released if column > 0 => Model.resize_line(state, Across(column), at.across.to_u64())
			Released if row > 0 => Model.resize_line(state, Down(row), at.down.to_u64())
			Released => Model.place(state, pane, Drag.drop_at(state, pane, at))
			_ => state
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

	## Where the drag would put its pane, nowhere while none is dragged.
	over : Model.State, Gesture -> Model.Drop
	over = |state, gesture|
		match gesture {
			Dragging({ pane, at, .. }) => Drag.drop_at(state, pane, at)
			_ => Model.nowhere
		}

	## The layout shown: while a pane is dragged, as if dropped where it is,
	## and while a line is, with the line where it is.
	previewed : Model.State, Gesture -> Model.State
	previewed = |state, gesture|
		match gesture {
			Dragging({ pane, .. }) => Model.place(state, pane, Drag.over(state, gesture))
			Resizing({ line, share: At(moved_to), .. }) => Model.resize_line(state, line, moved_to)
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
	holding = { pointer: 1, pane: "pane-4", column: 0, row: 0 }
	pressed == Pressed({ pane: "pane-4", pointer: 1 })
		and ids(Drag.previewed(state, dragged)) == [["pane-1"], ["pane-2", "pane-8", "pane-4"], ["pane-3", "pane-5"]]
		and Drag.previewed(state, below_main).grid.rows == [1, 1]
		and Drag.dropped(state, holding, { ..over_chat, phase: Released }) == Drag.previewed(state, dragged)
		and Drag.dropped(state, holding, { ..over_chat, phase: Cancelled }) == state
		and Drag.dropped(state, holding, pointer_at(Released, "", "", 0, 0)) == state
		and Drag.previewed(state, Drag.key_pressed(dragged, "Escape")) == state
		and Drag.heard(dragged, { ..over_chat, phase: Released }) == Idle
		and Drag.released(pressed, pressing) == Idle
		and Drag.released(dragged, pressing) == dragged
		and Drag.pressed(Idle, "pane-4", { ..pressing, kind: Touch }) == Idle
}

# A line between tiles held moves as the pointer does, resizing the tracks
# beside it, and stays where it is released.
expect {
	tiling = Model.layout(Model.initial(""), Model.tiling)
	pressing : Engine.Pointer
	pressing = { id: 1, kind: Mouse, button: Main, buttons: 1, modifiers: { shift: Bool.False, ctrl: Bool.False, alt: Bool.False, meta: Bool.False }, primary: Bool.True, at: Outside }
	pressed = Drag.pressed_line(Idle, Across(1), pressing)
	moved = Drag.heard(pressed, pointer_at(Moved, "", "", 2500, 0))
	Drag.held(pressed) == Holding({ pointer: 1, pane: "", column: 1, row: 0 })
		and Drag.previewed(tiling, pressed) == tiling
		and Drag.previewed(tiling, moved).grid.columns == [3, 9, 4]
		and Drag.dropped(tiling, { pointer: 1, pane: "", column: 1, row: 0 }, pointer_at(Released, "", "", 2500, 0)).grid.columns == [3, 9, 4]
		and Drag.released(pressed, pressing) == Idle
}

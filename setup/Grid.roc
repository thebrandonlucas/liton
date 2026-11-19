## A layout as a CSS grid: column and row tracks weighed by their relative
## sizes, and tiles, each a rectangle of cells showing one or more panes as
## tabs. Every operation is pure. A split cuts a track in two where the tile
## split needs a line, a close grows the tiles beside the closed one over its
## cells, and tracks no tile needs apart merge again, so the grid stays as
## small as the tiles allow.
Grid := [].{

	## `pinned` is the context a pane shows whatever the focus is, or "" to
	## follow the focus. `options` holds the values set of its widget's options;
	## the rest have their defaults.
	Pane : { id : Str, widget : Str, pinned : Str, options : List({ key : Str, value : Str }) }

	## A tile covers the cells between the column lines `left` and `right` and
	## the row lines `top` and `bottom`, counted from 0 at the grid's left and
	## top edges. It shows `active` of its panes.
	Tile : { id : Str, left : U64, top : U64, right : U64, bottom : U64, active : Str, panes : List(Pane) }

	## The sizes of the column and row tracks, and the tiles over them.
	Layout : { columns : List(U64), rows : List(U64), tiles : List(Tile) }

	## A side of a tile, or the way something moves.
	Side : [Left, Right, Up, Down]

	## One tile over one cell.
	single : Tile -> Layout
	single = |tile| { columns: [1], rows: [1], tiles: [{ ..tile, left: 0, top: 0, right: 1, bottom: 1 }] }

	## A grid of no tiles.
	empty : Layout
	empty = { columns: [], rows: [], tiles: [] }

	## `added` in a new column at the right, as wide as the columns are on
	## average, over every row.
	appended : Layout, Tile -> Layout
	appended = |grid, tile|
		if (grid.tiles.is_empty())
			Grid.single(tile)
		else
			Grid.normalized({ ..grid, columns: grid.columns.append(grid.columns.fold(0, |sum, size| sum + size) // grid.columns.len()), tiles: grid.tiles.append({ ..tile, left: grid.columns.len(), top: 0, right: grid.columns.len() + 1, bottom: grid.rows.len() }) })

	## Tile `id` cut in two, `added` taking the half on `side`.
	split : Layout, Str, Side, Tile -> Layout
	split = |grid, id, side, added|
		match side {
			Left => Grid.split_across(grid, id, Bool.True, added)
			Right => Grid.split_across(grid, id, Bool.False, added)
			Up => Grid.transposed(Grid.split_across(Grid.transposed(grid), id, Bool.True, added))
			Down => Grid.transposed(Grid.split_across(Grid.transposed(grid), id, Bool.False, added))
		}

	## Tile `id` cut in two across its columns, `added` taking the left half
	## when `before`, else the right.
	split_across : Layout, Str, Bool, Tile -> Layout
	split_across = |grid, id, before, added|
		match grid.tiles.find_first(|tile| tile.id == id) {
			Err(NotFound) => grid
			Ok(found) => {
				(with_line, line) = Grid.cut(grid, found)
				target = with_line.tiles.find_first(|tile| tile.id == id) ?? found
				(kept, taken) =
					if (before)
						({ ..target, left: line }, { ..added, left: target.left, right: line, top: target.top, bottom: target.bottom })
					else
						({ ..target, right: line }, { ..added, left: line, right: target.right, top: target.top, bottom: target.bottom })
				Grid.normalized({ ..with_line, tiles: with_line.tiles.map(|tile| if (tile.id == id) kept else tile).append(taken) })
			}
		}

	## The grid with a column line through the middle of `tile`, and that
	## line: one there already, or one cutting the track under the middle in
	## two, which the tiles over it then span.
	cut : Layout, Tile -> (Layout, U64)
	cut = |grid, tile| {
		doubled = grid.columns.map(|size| size * 2)
		positions = Grid.lines(doubled)
		middle = ((positions.get(tile.left) ?? 0) + (positions.get(tile.right) ?? 0)) // 2
		match positions.find_first_index(|at| at == middle) {
			Ok(line) => (grid, line)
			Err(NotFound) => {
				track = positions.keep_if(|at| at < middle).len() - 1
				start = positions.get(track) ?? 0
				end = positions.get(track + 1) ?? 0
				columns = doubled.take_first(track).concat([middle - start, end - middle]).concat(doubled.drop_first(track + 1))
				tiles = grid.tiles.map(|over| { ..over, left: if (over.left > track) over.left + 1 else over.left, right: if (over.right > track) over.right + 1 else over.right })
				({ ..grid, columns, tiles }, track + 1)
			}
		}
	}

	## Where each line is, from 0 at the start to the sum of `sizes` at the end.
	lines : List(U64) -> List(U64)
	lines = |sizes| sizes.fold([0], |at, size| at.append((at.last() ?? 0) + size))

	## Tile `id` taken away, the tiles beside it on one side grown over its
	## cells: the first side, of left, right, up and down, whose tiles cover
	## exactly its edge and each may join it (`joins` the id of the tile
	## beside and of the one closed). If none do, its cells stay empty.
	close : Layout, Str, (Str, Str -> Bool) -> Layout
	close = |grid, id, joins|
		match grid.tiles.find_first(|tile| tile.id == id) {
			Err(NotFound) => grid
			Ok(closed) => {
				rest = { ..grid, tiles: grid.tiles.drop_if(|tile| tile.id == id) }
				Grid.compacted([Left, Right, Up, Down].keep_oks(|side| Grid.grown(rest, closed, side, joins)).first() ?? rest)
			}
		}

	## The grid with the tiles on `side` of the tile `closed` grown over its
	## cells, if they cover that side and `joins` lets each take its place.
	grown : Layout, Tile, Side, (Str, Str -> Bool) -> Try(Layout, [NoFit])
	grown = |grid, closed, side, joins|
		match side {
			Left => Grid.grown_left(grid, closed, joins)
			Right => Grid.grown_left(Grid.mirrored(grid), Grid.mirrored_tile(closed, grid.columns.len()), joins).map_ok(Grid.mirrored)
			Up => Grid.grown_left(Grid.transposed(grid), Grid.transposed_tile(closed), joins).map_ok(Grid.transposed)
			Down => Grid.grown(Grid.transposed(grid), Grid.transposed_tile(closed), Right, joins).map_ok(Grid.transposed)
		}

	## `grown` for the tiles on the left of `closed`.
	grown_left : Layout, Tile, (Str, Str -> Bool) -> Try(Layout, [NoFit])
	grown_left = |grid, closed, joins| {
		touching = grid.tiles.keep_if(|tile| tile.right == closed.left and tile.top < closed.bottom and tile.bottom > closed.top)
		within = touching.all(|tile| tile.top >= closed.top and tile.bottom <= closed.bottom and joins(tile.id, closed.id))
		covered = touching.fold(0, |sum, tile| sum + tile.bottom - tile.top) == closed.bottom - closed.top
		if (!touching.is_empty() and within and covered)
			Ok({ ..grid, tiles: grid.tiles.map(|tile| if (touching.any(|grows| grows.id == tile.id)) { ..tile, right: closed.right } else tile) })
		else
			Err(NoFit)
	}

	## The tile beside tile `id` on `side` sharing the most of its edge,
	## the topmost or leftmost of those.
	beside : Layout, Str, Side -> Try(Tile, [NotFound])
	beside = |grid, id, side|
		match (grid.tiles.find_first(|tile| tile.id == id), side) {
			(Err(NotFound), _) => Err(NotFound)
			(Ok(from), Left) => Grid.beside_left(grid, from)
			(Ok(from), Right) => Grid.beside_left(Grid.mirrored(grid), Grid.mirrored_tile(from, grid.columns.len())).map_ok(|tile| Grid.mirrored_tile(tile, grid.columns.len()))
			(Ok(from), Up) => Grid.beside_left(Grid.transposed(grid), Grid.transposed_tile(from)).map_ok(Grid.transposed_tile)
			(Ok(_), Down) => Grid.beside(Grid.transposed(grid), id, Right).map_ok(Grid.transposed_tile)
		}

	## The tile on the left of `from` that shares the most of its height.
	beside_left : Layout, Tile -> Try(Tile, [NotFound])
	beside_left = |grid, from| {
		shared = |tile| U64.min(tile.bottom, from.bottom) - U64.max(tile.top, from.top)
		touching = grid.tiles.keep_if(|tile| tile.right == from.left and tile.top < from.bottom and tile.bottom > from.top)
		most = touching.fold(0, |widest, tile| U64.max(widest, shared(tile)))
		sharing_most = touching.keep_if(|tile| shared(tile) == most)
		sharing_most.find_first(|tile| !sharing_most.any(|other| other.top < tile.top))
	}

	## Tile `from`'s panes moved into tile `into`'s tabs, its active one shown,
	## and tile `from` closed as `close` does.
	join : Layout, Str, Str, (Str, Str -> Bool) -> Layout
	join = |grid, from, into, joins|
		match grid.tiles.find_first(|tile| tile.id == from) {
			Ok(joined) if from != into and grid.tiles.any(|tile| tile.id == into) => {
				added = { ..grid, tiles: grid.tiles.map(|tile| if (tile.id == into) { ..tile, active: joined.active, panes: tile.panes.concat(joined.panes) } else tile) }
				Grid.close(added, from, joins)
			}
			_ => grid
		}

	## Tile `from` closed and put on `side` of tile `target`.
	moved_to_edge : Layout, Str, Str, Side, (Str, Str -> Bool) -> Layout
	moved_to_edge = |grid, from, target, side, joins|
		match grid.tiles.find_first(|tile| tile.id == from) {
			Ok(moving) if from != target and grid.tiles.any(|tile| tile.id == target) => Grid.split(Grid.close(grid, from, joins), target, side, moving)
			_ => grid
		}

	## Tiles `first` and `second` in each other's place.
	swapped : Layout, Str, Str -> Layout
	swapped = |grid, first, second|
		match (grid.tiles.find_first(|tile| tile.id == first), grid.tiles.find_first(|tile| tile.id == second)) {
			(Ok(one), Ok(other)) => {
				placed = |tile, at| { ..tile, left: at.left, top: at.top, right: at.right, bottom: at.bottom }
				{ ..grid, tiles: grid.tiles.map(|tile| if (tile.id == first) placed(tile, other) else if (tile.id == second) placed(tile, one) else tile) }
			}
			_ => grid
		}

	## The column `line` moved to `share` ten thousandths of the way across the
	## two tracks beside it, each keeping a twentieth of them at least.
	resized_columns : Layout, U64, U64 -> Layout
	resized_columns = |grid, line, share|
		match (grid.columns.get(line.max(1) - 1), grid.columns.get(line)) {
			(Ok(before), Ok(after)) if line > 0 => {
				both = (before + after) * 100
				first = both * share.max(500).min(9500) // 10000
				columns = grid.columns.map_with_index(|size, track| if (track + 1 == line) first else if (track == line) both - first else size * 100)
				Grid.normalized({ ..grid, columns })
			}
			_ => grid
		}

	## `resized_columns` for the rows on either side of row line `line`.
	resized_rows : Layout, U64, U64 -> Layout
	resized_rows = |grid, line, share| Grid.transposed(Grid.resized_columns(Grid.transposed(grid), line, share))

	## How far across the two tracks beside column `line` it is, in ten
	## thousandths.
	column_share : Layout, U64 -> U64
	column_share = |grid, line|
		match (grid.columns.get(line.max(1) - 1), grid.columns.get(line)) {
			(Ok(before), Ok(after)) if line > 0 => before * 10000 // (before + after)
			_ => 5000
		}

	## `column_share` for the rows on either side of row line `line`.
	row_share : Layout, U64 -> U64
	row_share = |grid, line| Grid.column_share(Grid.transposed(grid), line)

	## The edge on `side` of tile `id` moved a tenth of the two tracks beside
	## it that way, or if that edge is the grid's, its other edge.
	nudged : Layout, Str, Side -> Layout
	nudged = |grid, id, side|
		match (grid.tiles.find_first(|tile| tile.id == id), side) {
			(Err(NotFound), _) => grid
			(Ok(tile), Left) | (Ok(tile), Right) => {
				line = if (tile.right < grid.columns.len()) tile.right else tile.left
				share = Grid.column_share(grid, line)
				Grid.resized_columns(grid, line, if (side == Left) share - share.min(1000) else share + 1000)
			}
			(Ok(_), _) => Grid.transposed(Grid.nudged(Grid.transposed(grid), id, if (side == Up) Left else Right))
		}

	## The grid without tracks no tile covers, and with the two tracks beside
	## a line no tile's edge is on merged, its sizes as small as they can be.
	compacted : Layout -> Layout
	compacted = |grid| Grid.normalized(Grid.transposed(Grid.compacted_columns(Grid.transposed(Grid.compacted_columns(grid)))))

	## `compacted` for the grid's columns alone.
	compacted_columns : Layout -> Layout
	compacted_columns = |grid| {
		tracks = grid.columns.map_with_index(|_, track| track)
		uncovered = tracks.find_first(|track| !grid.tiles.any(|tile| tile.left <= track and tile.right > track))
		unused = tracks.drop_first(1).find_first(|line| !grid.tiles.any(|tile| tile.left == line or tile.right == line))
		shifted = |at, past| if (at > past) at - 1 else at
		match (uncovered, unused) {
			(Ok(track), _) => Grid.compacted_columns({ ..grid, columns: grid.columns.drop_at(track), tiles: grid.tiles.map(|tile| { ..tile, left: shifted(tile.left, track), right: shifted(tile.right, track) }) })
			(_, Ok(line)) => Grid.compacted_columns({ ..grid, columns: grid.columns.map_with_index(|size, track| if (track + 1 == line) size + (grid.columns.get(line) ?? 0) else size).drop_at(line), tiles: grid.tiles.map(|tile| { ..tile, left: shifted(tile.left, line), right: shifted(tile.right, line) }) })
			_ => grid
		}
	}

	## The sizes of each axis divided by what they share.
	normalized : Layout -> Layout
	normalized = |grid| {
		divided = |sizes| {
			common = sizes.fold(0, divisor)
			if (common > 1) sizes.map(|size| size // common) else sizes
		}
		{ ..grid, columns: divided(grid.columns), rows: divided(grid.rows) }
	}

	## Columns as rows and rows as columns.
	transposed : Layout -> Layout
	transposed = |grid| { columns: grid.rows, rows: grid.columns, tiles: grid.tiles.map(Grid.transposed_tile) }

	## A tile with its columns as rows and its rows as columns.
	transposed_tile : Tile -> Tile
	transposed_tile = |tile| { ..tile, left: tile.top, top: tile.left, right: tile.bottom, bottom: tile.right }

	## The grid as a mirror shows it, its columns right to left.
	mirrored : Layout -> Layout
	mirrored = |grid| { ..grid, columns: grid.columns.fold([], |reversed, size| reversed.prepend(size)), tiles: grid.tiles.map(|tile| Grid.mirrored_tile(tile, grid.columns.len())) }

	## A tile of a grid `columns` wide as a mirror shows it.
	mirrored_tile : Tile, U64 -> Tile
	mirrored_tile = |tile, columns| { ..tile, left: columns - tile.right, right: columns - tile.left }
}

## The greatest common divisor, 0 sharing everything.
divisor : U64, U64 -> U64
divisor = |a, b| if (b == 0) a else divisor(b, a % b)

tile : Str -> Grid.Tile
tile = |id| { id, left: 0, top: 0, right: 1, bottom: 1, active: id, panes: [{ id, widget: id, pinned: "", options: [] }] }

anywhere : Str, Str -> Bool
anywhere = |_, _| Bool.True

bounds : Grid.Layout -> List((Str, U64, U64, U64, U64))
bounds = |grid| grid.tiles.map(|placed| (placed.id, placed.left, placed.top, placed.right, placed.bottom))

# Splitting halves a tile, cutting a track where it needs a line, and an
# existing line in its middle does.
expect {
	halves = Grid.split(Grid.single(tile("a")), "a", Right, tile("b"))
	thirds = Grid.split(halves, "b", Down, tile("c"))
	quarters = Grid.split({ columns: [1, 1], rows: [1], tiles: [{ ..tile("wide"), right: 2 }] }, "wide", Left, tile("d"))
	halves == { columns: [1, 1], rows: [1], tiles: [{ ..tile("a"), right: 1 }, { ..tile("b"), left: 1, right: 2 }] }
		and thirds.rows == [1, 1]
		and bounds(thirds) == [("a", 0, 0, 1, 2), ("b", 1, 0, 2, 1), ("c", 1, 1, 2, 2)]
		and bounds(quarters) == [("wide", 1, 0, 2, 1), ("d", 0, 0, 1, 1)]
		and bounds(Grid.split(Grid.split(halves, "a", Left, tile("e")), "b", Up, tile("f"))) == [("a", 1, 0, 2, 2), ("b", 2, 1, 3, 2), ("e", 0, 0, 1, 2), ("f", 2, 0, 3, 1)]
}

# A tile added goes in a column of its own at the right, over every row.
expect {
	three = Grid.split(Grid.split(Grid.single(tile("a")), "a", Right, tile("b")), "b", Down, tile("c"))
	Grid.appended(Grid.empty, tile("a")) == Grid.single(tile("a")) and bounds(Grid.appended(three, tile("d"))) == [("a", 0, 0, 1, 2), ("b", 1, 0, 2, 1), ("c", 1, 1, 2, 2), ("d", 2, 0, 3, 2)]
}

# Closing a tile grows the tiles beside it that cover its edge, and merges
# the tracks no tile needs apart.
expect {
	three = Grid.split(Grid.split(Grid.single(tile("a")), "a", Right, tile("b")), "b", Down, tile("c"))
	Grid.close(three, "c", anywhere) == Grid.split(Grid.single(tile("a")), "a", Right, tile("b"))
		and Grid.close(three, "a", anywhere) == { columns: [1], rows: [1, 1], tiles: [{ ..tile("b"), left: 0, right: 1, bottom: 1 }, { ..tile("c"), top: 1, bottom: 2 }] }
		and bounds(Grid.close(Grid.split(Grid.split(Grid.single(tile("a")), "a", Right, tile("b")), "b", Right, tile("c")), "b", |grows, _| grows != "a")) == [("a", 0, 0, 1, 1), ("c", 1, 0, 2, 1)]
		and Grid.close(Grid.single(tile("a")), "a", anywhere) == Grid.empty
}

# Joining moves a tile's tabs into another's, and moving puts a tile on
# another's edge.
expect {
	three = Grid.split(Grid.split(Grid.single(tile("a")), "a", Right, tile("b")), "b", Down, tile("c"))
	joined = Grid.join(three, "c", "a", anywhere)
	moved = Grid.moved_to_edge(three, "a", "c", Down, anywhere)
	joined.tiles.map(|placed| (placed.id, placed.active, placed.panes.map(|pane| pane.id))) == [("a", "c", ["a", "c"]), ("b", "b", ["b"])]
		and bounds(joined) == [("a", 0, 0, 1, 1), ("b", 1, 0, 2, 1)]
		and bounds(moved) == [("b", 0, 0, 1, 1), ("c", 0, 1, 1, 2), ("a", 0, 2, 1, 3)]
		and Grid.join(three, "a", "a", anywhere) == three
}

# Tracks resize by the line between them, keeping a twentieth each.
expect {
	halves = Grid.split(Grid.single(tile("a")), "a", Right, tile("b"))
	Grid.resized_columns(halves, 1, 2500).columns == [1, 3]
		and Grid.resized_columns(halves, 1, 0).columns == [1, 19]
		and Grid.nudged(halves, "b", Right).columns == [3, 2]
		and Grid.nudged(halves, "a", Left).columns == [2, 3]
		and Grid.column_share({ ..halves, columns: [1, 3] }, 1) == 2500
		and Grid.nudged(Grid.single(tile("a")), "a", Right) == Grid.single(tile("a"))
}

# The tile beside another is the one sharing the most of its edge.
expect {
	three = Grid.split(Grid.split(Grid.single(tile("a")), "a", Right, tile("b")), "b", Down, tile("c"))
	Grid.beside(three, "a", Right).map_ok(|found| found.id) == Ok("b")
		and Grid.beside(three, "c", Left).map_ok(|found| found.id) == Ok("a")
		and Grid.beside(three, "b", Down).map_ok(|found| found.id) == Ok("c")
		and Grid.beside(three, "c", Up).map_ok(|found| found.id) == Ok("b")
		and Grid.beside(three, "a", Left) == Err(NotFound)
		and bounds(Grid.swapped(three, "a", "c")) == [("a", 1, 1, 2, 2), ("b", 1, 0, 2, 1), ("c", 0, 0, 1, 2)]
}

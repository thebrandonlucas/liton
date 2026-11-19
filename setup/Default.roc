## liton's own setup, which Litonfile.roc evaluates and another setup builds
## on: no remotes, attention derived from chat, the Developer, Inbox, Tiling,
## Chat, Rooms, Review and Board presets, Developer first, and the Pastoral, Hypr, Plain,
## Neutral, Sky and Graphite themes, Pastoral first; a new browser's deck
## holds Developer, Rooms, Review and Board. The UI offers these presets and themes when its daemon
## offers none.
import Grid
import Setup

Default := [].{

	## A Workbench as Paseo's: the workspaces by their status, the one
	## picked as tabs of its sessions' chats and the ticket opened, and the
	## changes and files of the workspace and the tickets, as tabs, in the
	## Neutral theme.
	developer : Setup.Preset
	developer = {
		name: "Developer",
		snapshot: {
			version: Setup.snapshot_version,
			shell: Workbench,
			grid: {
				columns: [1, 1, 1],
				rows: [1],
				tiles: [
					{ id: "tile-1", left: 0, top: 0, right: 1, bottom: 1, active: "pane-1", panes: [{ id: "pane-1", widget: "workspaces", pinned: "", options: [{ key: "group_by", value: "Status" }, { key: "sessions", value: "Tabs" }] }] },
					{ id: "tile-2", left: 1, top: 0, right: 2, bottom: 1, active: "pane-2", panes: [{ id: "pane-2", widget: "chat", pinned: "", options: [] }, { id: "pane-8", widget: "ticket", pinned: "", options: [] }] },
					{ id: "tile-3", left: 2, top: 0, right: 3, bottom: 1, active: "pane-3", panes: [{ id: "pane-3", widget: "changes", pinned: "", options: [] }, { id: "pane-4", widget: "files", pinned: "", options: [] }, { id: "pane-5", widget: "tickets", pinned: "", options: [] }] },
				],
			},
			collapsed: [],
			hidden: ["pane-8"],
			theme: "Neutral",
		},
	}

	## A Workbench of what needs you, with the rooms as a tab beside it, the
	## chat following the item opened with the room opened as a tab beside
	## it, and the Developer preset's right drawer, collapsed.
	inbox : Setup.Preset
	inbox = {
		name: "Inbox",
		snapshot: {
			..Default.developer.snapshot,
			grid: Default.with_tiles(
				Default.developer.snapshot.grid,
				|tile|
					if (tile.id == "tile-1")
						{ ..tile, panes: [{ id: "pane-1", widget: "inbox", pinned: "", options: [] }, { id: "pane-6", widget: "rooms", pinned: "", options: [] }] }
					else if (tile.id == "tile-2")
						{ ..tile, panes: tile.panes.append({ id: "pane-7", widget: "room", pinned: "", options: [] }) }
					else
						tile,
			),
			collapsed: [Right],
			theme: "",
		},
	}

	## A chat app: the sessions, the latest first, beside one large chat,
	## with the right drawer hidden.
	chat : Setup.Preset
	chat = {
		name: "Chat",
		snapshot: { ..Default.developer.snapshot, grid: Default.with_tiles(Default.developer.snapshot.grid, |tile| if (tile.id == "tile-1") { ..tile, panes: [{ id: "pane-1", widget: "sessions", pinned: "", options: [{ key: "show_agent", value: "false" }] }] } else tile), collapsed: [Right], theme: "" },
	}

	## Talking in rooms, as Buzz does: the rooms, the room picked large, and
	## its thread or members in the right drawer, hidden until opened, in
	## the Sky theme.
	rooms : Setup.Preset
	rooms = {
		name: "Rooms",
		snapshot: {
			version: Setup.snapshot_version,
			shell: Workbench,
			grid: {
				columns: [1, 1, 1],
				rows: [1],
				tiles: [
					{ id: "tile-1", left: 0, top: 0, right: 1, bottom: 1, active: "pane-1", panes: [{ id: "pane-1", widget: "rooms", pinned: "", options: [] }] },
					{ id: "tile-2", left: 1, top: 0, right: 2, bottom: 1, active: "pane-2", panes: [{ id: "pane-2", widget: "room", pinned: "", options: [] }] },
					{ id: "tile-3", left: 2, top: 0, right: 3, bottom: 1, active: "pane-3", panes: [{ id: "pane-3", widget: "thread", pinned: "", options: [] }, { id: "pane-4", widget: "members", pinned: "", options: [] }] },
				],
			},
			collapsed: [Right],
			hidden: ["pane-3", "pane-4"],
			theme: "Sky",
		},
	}

	## Review, modelled on crit.md: the changed files, with the workspaces
	## as a tab beside them, every changed file's diff with the review's
	## threads at their lines, and the threads, with the chat as a tab
	## beside them, as a Workbench whose main area is the widest.
	review : Setup.Preset
	review = {
		name: "Review",
		snapshot: {
			..Default.developer.snapshot,
			grid: {
				columns: [1, 3, 1],
				rows: [1],
				tiles: [
					{ id: "tile-1", left: 0, top: 0, right: 1, bottom: 1, active: "pane-1", panes: [{ id: "pane-1", widget: "review-files", pinned: "", options: [] }, { id: "pane-4", widget: "workspaces", pinned: "", options: [] }] },
					{ id: "tile-2", left: 1, top: 0, right: 2, bottom: 1, active: "pane-2", panes: [{ id: "pane-2", widget: "review", pinned: "", options: [] }] },
					{ id: "tile-3", left: 2, top: 0, right: 3, bottom: 1, active: "pane-3", panes: [{ id: "pane-3", widget: "review-threads", pinned: "", options: [] }, { id: "pane-5", widget: "chat", pinned: "", options: [] }] },
				],
			},
			hidden: [],
		},
	}

	## Tickets, as Linear lays them out: the scopes to pick from, the tickets
	## of the scope picked, and the properties of the one under the cursor,
	## with a chat hidden beside the tickets until a session is opened.
	board : Setup.Preset
	board = {
		name: "Board",
		snapshot: {
			..Default.developer.snapshot,
			grid: Default.with_tiles(
				Default.developer.snapshot.grid,
				|tile|
					if (tile.id == "tile-1")
						{ ..tile, panes: [{ id: "pane-1", widget: "ticket-scopes", pinned: "", options: [] }] }
					else if (tile.id == "tile-2")
						{ ..tile, panes: [{ id: "pane-2", widget: "board", pinned: "", options: [] }, { id: "pane-3", widget: "chat", pinned: "", options: [] }] }
					else
						{ ..tile, active: "pane-4", panes: [{ id: "pane-4", widget: "ticket-properties", pinned: "", options: [] }] },
			),
			hidden: ["pane-3"],
			theme: "Graphite",
		},
	}

	with_tiles : Grid.Layout, (Grid.Tile -> Grid.Tile) -> Grid.Layout
	with_tiles = |grid, change| { ..grid, tiles: grid.tiles.map(change) }

	## Sessions, a wider chat and what the daemon advertises, side by side.
	tiling : Setup.Preset
	tiling = {
		name: "Tiling",
		snapshot: {
			version: Setup.snapshot_version,
			shell: Tiling,
			grid: {
				columns: [1, 2, 1],
				rows: [1],
				tiles: [
					{ id: "tile-1", left: 0, top: 0, right: 1, bottom: 1, active: "pane-1", panes: [{ id: "pane-1", widget: "sessions", pinned: "", options: [] }] },
					{ id: "tile-2", left: 1, top: 0, right: 2, bottom: 1, active: "pane-2", panes: [{ id: "pane-2", widget: "chat", pinned: "", options: [] }] },
					{ id: "tile-3", left: 2, top: 0, right: 3, bottom: 1, active: "pane-3", panes: [{ id: "pane-3", widget: "capabilities", pinned: "", options: [] }] },
				],
			},
			collapsed: [],
			hidden: [],
			theme: "",
		},
	}

	## Gold over Thomas Cole's "The Arcadian or Pastoral State" (1834, public
	## domain), dimmed under dark glass tiles, with a serif display face: the
	## default. The painting is served from the daemon's static files.
	pastoral : Setup.Theme
	pastoral = {
		name: "Pastoral",
		scheme: Dark,
		accent: "#e8c872",
		accent_to: "#e8c872",
		text: "#ece8dc",
		muted: "#a8a08a",
		edge: 22,
		edge_active: 70,
		glass: { tint: "#0c0c0c", opacity: 55, blur: 5 },
		background: Image({ url: "/ui/backgrounds/pastoral.webp", dim: 45 }),
		gap: 10,
		radius: 10,
		fonts: { ui: Default.system_font, mono: Default.mono_font, display: "\"EB Garamond\", \"Iowan Old Style\", \"Palatino Linotype\", Palatino, Georgia, serif" },
		motion: Normal,
	}

	## Tiles on a deep violet and teal gradient, the focused one's edge fading
	## from teal to violet, as a tiling window manager draws it.
	hypr : Setup.Theme
	hypr = {
		name: "Hypr",
		scheme: Dark,
		accent: "#2fd8c4",
		accent_to: "#a580ff",
		text: "#e6e8f0",
		muted: "#9ba2b8",
		edge: 18,
		edge_active: 90,
		glass: { tint: "#0e1018", opacity: 55, blur: 8 },
		background: Gradient({ base: "#07080f", from: "#24184f", to: "#073331", glow: "#a580ff" }),
		gap: 8,
		radius: 12,
		fonts: { ui: Default.system_font, mono: Default.mono_font, display: Default.mono_font },
		motion: Normal,
	}

	## Light and calm: opaque tiles on a flat background, nothing moving.
	plain : Setup.Theme
	plain = {
		name: "Plain",
		scheme: Light,
		accent: "#3559e0",
		accent_to: "#3559e0",
		text: "#1d1d1b",
		muted: "#5f5f5a",
		edge: 18,
		edge_active: 80,
		glass: { tint: "#ffffff", opacity: 100, blur: 0 },
		background: Flat("#f2f2ef"),
		gap: 8,
		radius: 8,
		fonts: { ui: Default.system_font, mono: Default.mono_font, display: Default.system_font },
		motion: Reduced,
	}

	## Flat and neutral, as Paseo is: near-black opaque tiles side by side,
	## the platform's font, and no focused edge, so no pane dims either.
	neutral : Setup.Theme
	neutral = {
		name: "Neutral",
		scheme: Dark,
		accent: "#fafafa",
		accent_to: "#fafafa",
		text: "#fafafa",
		muted: "#a1a5a4",
		edge: 6,
		edge_active: 6,
		glass: { tint: "#1e2120", opacity: 100, blur: 0 },
		background: Flat("#1b1d1c"),
		gap: 0,
		radius: 8,
		fonts: { ui: Default.system_font, mono: Default.mono_font, display: Default.system_font },
		motion: Normal,
	}

	## Light and soft, for talking in rooms: white tiles with neutral grey
	## edges on a pale sky, the focused edge fading to violet.
	sky : Setup.Theme
	sky = {
		name: "Sky",
		scheme: Light,
		accent: "#1a1a1a",
		accent_to: "#8b5cf6",
		text: "#1a1a1a",
		muted: "#6b6b6b",
		edge: 10,
		edge_active: 45,
		glass: { tint: "#ffffff", opacity: 94, blur: 12 },
		background: Gradient({ base: "#f5f6fa", from: "#d9e6fb", to: "#f3e3f3", glow: "#b9d3ff" }),
		gap: 10,
		radius: 16,
		fonts: { ui: Default.system_font, mono: Default.mono_font, display: Default.system_font },
		motion: Normal,
	}

	## Dense and dark, as Linear is: opaque near-black tiles a hairline
	## apart on black, grey edges and one quiet indigo accent, nothing
	## blurred. The Board preset's.
	graphite : Setup.Theme
	graphite = {
		name: "Graphite",
		scheme: Dark,
		accent: "#5e6ad2",
		accent_to: "#5e6ad2",
		text: "#e2e4e7",
		muted: "#8a8f98",
		edge: 16,
		edge_active: 60,
		glass: { tint: "#101112", opacity: 100, blur: 0 },
		background: Flat("#08090a"),
		gap: 1,
		radius: 4,
		fonts: { ui: "Inter, ${Default.system_font}", mono: Default.mono_font, display: "Inter, ${Default.system_font}" },
		motion: Normal,
	}

	## The platform's own faces, so no font is downloaded; JetBrains Mono where
	## it is installed.
	system_font : Str
	system_font = "system-ui, -apple-system, \"Segoe UI\", Roboto, sans-serif"

	mono_font : Str
	mono_font = "\"JetBrains Mono\", \"Iosevka\", ui-monospace, \"SF Mono\", Menlo, Consolas, monospace"

	setup : Setup.Declared
	setup = { remotes: [], transformers: ["attention"], presets: [Default.developer, Default.inbox, Default.tiling, Default.chat, Default.rooms, Default.review, Default.board], default_preset: "Developer", themes: [Default.pastoral, Default.hypr, Default.plain, Default.neutral, Default.sky, Default.graphite], default_theme: "Pastoral", deck: [Default.developer.name, Default.rooms.name, Default.review.name, Default.board.name] }
}

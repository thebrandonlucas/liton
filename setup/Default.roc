## liton's own setup, which Litonfile.roc evaluates and another setup builds
## on: no remotes, attention derived from chat, the Developer, Inbox and
## Tiling presets, Developer first, and the Pastoral, Hypr and Plain themes,
## Pastoral first. The UI offers these presets and themes when its daemon
## offers none.
import Setup

Default := [].{

	## A Workbench of workspaces and their sessions, the chat following the
	## focus, and the changes of the workspace or session focused.
	developer : Setup.Preset
	developer = {
		name: "Developer",
		snapshot: {
			version: Setup.snapshot_version,
			shell: Workbench,
			columns: [
				{ id: "column-1", size: 1, tabbed: Bool.True, active: "pane-1", panes: [{ id: "pane-1", widget: "workspaces", pinned: "", options: [] }] },
				{ id: "column-2", size: 1, tabbed: Bool.True, active: "pane-2", panes: [{ id: "pane-2", widget: "chat", pinned: "", options: [] }] },
				{ id: "column-3", size: 1, tabbed: Bool.True, active: "pane-3", panes: [{ id: "pane-3", widget: "changes", pinned: "", options: [] }] },
			],
			collapsed: [],
			theme: "",
		},
	}

	## A Workbench of what needs you, the chat following the item opened, and
	## the Developer preset's right drawer, collapsed.
	inbox : Setup.Preset
	inbox = {
		name: "Inbox",
		snapshot: { ..Default.developer.snapshot, columns: Default.developer.snapshot.columns.map(|column| if (column.id == "column-1") { ..column, panes: [{ id: "pane-1", widget: "inbox", pinned: "", options: [] }] } else column), collapsed: [Right] },
	}

	## Sessions, a wider chat and what the daemon advertises, each in a column.
	tiling : Setup.Preset
	tiling = {
		name: "Tiling",
		snapshot: {
			version: Setup.snapshot_version,
			shell: Tiling,
			columns: [
				{ id: "column-1", size: 1, tabbed: Bool.False, active: "pane-1", panes: [{ id: "pane-1", widget: "sessions", pinned: "", options: [] }] },
				{ id: "column-2", size: 2, tabbed: Bool.False, active: "pane-2", panes: [{ id: "pane-2", widget: "chat", pinned: "", options: [] }] },
				{ id: "column-3", size: 1, tabbed: Bool.False, active: "pane-3", panes: [{ id: "pane-3", widget: "capabilities", pinned: "", options: [] }] },
			],
			collapsed: [],
			theme: "",
		},
	}

	## Gold on a dark gradient with a faint warm glow, glass tiles and a serif
	## display face: the default.
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
		glass: { tint: "#0c0c0c", opacity: 46, blur: 5 },
		background: Gradient({ base: "#0a0907", from: "#282114", to: "#15211b", glow: "#e8c872" }),
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

	## The platform's own faces, so no font is downloaded; JetBrains Mono where
	## it is installed.
	system_font : Str
	system_font = "system-ui, -apple-system, \"Segoe UI\", Roboto, sans-serif"

	mono_font : Str
	mono_font = "\"JetBrains Mono\", \"Iosevka\", ui-monospace, \"SF Mono\", Menlo, Consolas, monospace"

	setup : Setup.Declared
	setup = { remotes: [], transformers: ["attention"], presets: [Default.developer, Default.inbox, Default.tiling], default_preset: "Developer", themes: [Default.pastoral, Default.hypr, Default.plain], default_theme: "Pastoral" }
}

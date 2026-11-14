## liton's own setup, which Litonfile.roc evaluates and another setup builds
## on: no remotes, attention derived from chat, and the Developer, Inbox and
## Tiling presets, Developer first. The UI offers these presets when its
## daemon offers none.
import Setup

Default := [].{

	## A Workbench of sessions, the chat following the focus, and the focused
	## session's changes beside what the daemon advertises.
	developer : Setup.Preset
	developer = {
		name: "Developer",
		snapshot: {
			version: Setup.snapshot_version,
			shell: Workbench,
			columns: [
				{ id: "column-1", size: 1, tabbed: Bool.True, active: "pane-1", panes: [{ id: "pane-1", widget: "sessions", pinned: "", options: [] }] },
				{ id: "column-2", size: 1, tabbed: Bool.True, active: "pane-2", panes: [{ id: "pane-2", widget: "chat", pinned: "", options: [] }] },
				{ id: "column-3", size: 1, tabbed: Bool.True, active: "pane-3", panes: [{ id: "pane-3", widget: "changes", pinned: "", options: [] }, { id: "pane-4", widget: "capabilities", pinned: "", options: [] }] },
			],
			collapsed: [],
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
		},
	}

	setup : Setup.Declared
	setup = { remotes: [], transformers: ["attention"], presets: [Default.developer, Default.inbox, Default.tiling], default_preset: "Developer" }
}

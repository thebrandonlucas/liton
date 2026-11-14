## A team's setup, built on liton's own: the team's daemon as a remote, a
## Review preset to start with, and no attention.v1, nor the Inbox preset
## that shows it. `liton setup examples/litonfile-team/Litonfile.roc`
## evaluates it.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.0/2yhxoR7cZPSYbyUzPWULFw8AA6QEcdsgFNRmzu7pZbst.tar.zst",
	setup: "../../setup/main.roc",
}

import pf.Stdout
import setup.Default
import setup.Setup

## The sessions, a wider chat, and the changes of the one it shows side by side.
review : Setup.Preset
review = {
	name: "Review",
	snapshot: {
		version: Setup.snapshot_version,
		shell: Tiling,
		columns: [
			{ id: "column-1", size: 1, tabbed: Bool.False, active: "pane-1", panes: [{ id: "pane-1", widget: "sessions", pinned: "", options: [] }] },
			{ id: "column-2", size: 2, tabbed: Bool.False, active: "pane-2", panes: [{ id: "pane-2", widget: "chat", pinned: "", options: [] }] },
			{ id: "column-3", size: 2, tabbed: Bool.False, active: "pane-3", panes: [{ id: "pane-3", widget: "changes", pinned: "", options: [{ key: "diff_layout", value: "Split" }] }] },
		],
		collapsed: [],
		theme: "",
	},
}

setup : Setup.Declared
setup = Setup.merge(
	Setup.without_preset(Setup.without_transformer(Default.setup, "attention"), "Inbox"),
	{ ..Setup.empty, remotes: [{ name: "team", url: "http://127.0.0.1:8096" }], presets: [review], default_preset: "Review" },
)

main! = |_arguments| Stdout.line!(Setup.to_json(setup))

expect setup.remotes == [{ name: "team", url: "http://127.0.0.1:8096" }] and setup.transformers == []
expect setup.presets.map(|preset| preset.name) == ["Developer", "Tiling", "Review"] and setup.default_preset == "Review"

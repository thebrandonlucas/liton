## The widgets a layout can hold, declared as data apart from their views:
## its role, the capabilities each needs, the slots it fits and its minimum
## width, the kinds of context it sets the focus to and those it shows,
## following the focus or pinned, its options, and the parts of it that are
## stable hooks for styling. When a widget is relevant (a `when` expression
## over the focus) is still to come.
import cap.Capability
import cap.Context
import setup.Setup

Widgets := [].{

	## Where a column sits (Setup.Slot).
	Slot : Setup.Slot

	## An option's kind, from a closed set, with its default. Text, Int,
	## CapabilityRef, ContextRef and ThemeToken are next.
	Kind : [Bool(Bool), Choice({ default : Str, choices : List(Str) })]

	Option : { key : Str, label : Str, help : Str, kind : Kind }

	## A navigator chooses what is in focus, a view shows it large, and an
	## inspector shows details of it beside the view.
	Role : [Navigator, View, Inspector]

	Widget : { id : Str, title : Str, role : Role, needs : List(Capability.Id), slots : List(Slot), minimum_width : U32, sets : List(Context.Kind), follows : List(Context.Kind), options : List(Option), parts : List(Str) }

	all : List(Widget)
	all = [
		{
			id: "sessions",
			title: "Sessions",
			role: Navigator,
			needs: [Capability.chat_v1],
			slots: [Left, Main],
			minimum_width: 200,
			sets: [Session],
			follows: [],
			options: [{ key: "show_agent", label: "Show agent", help: "Name the agent under each session.", kind: Bool(Bool.True) }, Widgets.order],
			parts: ["header", "list", "session"],
		},
		{
			id: "workspaces",
			title: "Workspaces",
			role: Navigator,
			needs: [Capability.workspaces_v1],
			slots: [Left, Main],
			minimum_width: 220,
			sets: [Workspace, Session],
			follows: [],
			options: [
				{ key: "group_by", label: "Group by", help: "List workspaces under their project, or under what they need from you.", kind: Choice({ default: "Project", choices: ["Project", "Status"] }) },
				{ key: "show_idle", label: "Show idle workspaces", help: "List workspaces whose agents need nothing.", kind: Bool(Bool.True) },
				Widgets.order,
			],
			parts: ["header", "list", "group", "workspace", "session"],
		},
		{
			id: "chat",
			title: "Chat",
			role: View,
			needs: [Capability.chat_v1],
			slots: [Main, Right],
			minimum_width: 300,
			sets: [],
			follows: [Session, Workspace],
			options: [
				{ key: "tool_output", label: "Tool output", help: "How much of a tool call's output its card shows.", kind: Choice({ default: "Folded", choices: ["Full", "Folded", "Hidden"] }) },
				{ key: "show_status", label: "Show status lines", help: "Show when the agent starts, stops or waits.", kind: Bool(Bool.True) },
				{ key: "collapse", label: "Collapse", help: "Show every tool call open, fold tool calls in a row into one line, or also fold each finished turn's work into one.", kind: Choice({ default: "Tools", choices: ["Full", "Tools", "Turns"] }) },
			],
			parts: ["header", "timeline", "bubble", "tool-card", "permission", "composer"],
		},
		{
			id: "inbox",
			title: "Inbox",
			role: Navigator,
			needs: [Capability.attention_v1],
			slots: [Left, Main],
			minimum_width: 240,
			sets: [Session],
			follows: [],
			options: [
				{ key: "show_idle", label: "Show idle sessions", help: "List sessions whose agents sit idle, with the rest.", kind: Bool(Bool.True) },
				{ key: "snooze_length", label: "Snooze length", help: "How long Snooze sets an item aside.", kind: Choice({ default: "1 hour", choices: ["1 hour", "1 day", "1 week"] }) },
			],
			parts: ["header", "section", "item", "actions"],
		},
		{
			id: "changes",
			title: "Changes",
			role: Inspector,
			needs: [Capability.workspace_git_v1],
			slots: [Right, Main],
			minimum_width: 240,
			sets: [],
			follows: [Session, Workspace],
			options: [
				{ key: "diff_layout", label: "Diff layout", help: "Show a file's diff in one column, or old beside new.", kind: Choice({ default: "Unified", choices: ["Unified", "Split"] }) },
				{ key: "show_commits", label: "Show commits", help: "List the branch's commits under its changes.", kind: Bool(Bool.True) },
			],
			parts: ["header", "status", "files", "file", "hunk", "line", "commits"],
		},
		{
			id: "files",
			title: "Files",
			role: Inspector,
			needs: [Capability.files_v1],
			slots: [Right, Main],
			minimum_width: 240,
			sets: [],
			follows: [Session, Workspace],
			options: [],
			parts: ["header", "list", "folder", "file", "line"],
		},
		{
			id: "tickets",
			title: "Tickets",
			role: Navigator,
			needs: [Capability.tickets_v1],
			slots: [Left, Main, Right],
			minimum_width: 260,
			sets: [Ticket],
			follows: [],
			options: [],
			parts: ["header", "filters", "list", "ticket"],
		},
		{
			id: "ticket",
			title: "Ticket",
			role: View,
			needs: [Capability.tickets_v1],
			slots: [Main, Right],
			minimum_width: 300,
			sets: [],
			follows: [Ticket],
			options: [],
			parts: ["header", "ticket", "fields", "sessions", "comment", "composer"],
		},
		{
			id: "ticket-scopes",
			title: "Scopes",
			role: Navigator,
			needs: [Capability.tickets_v1],
			slots: [Left, Main],
			minimum_width: 200,
			sets: [],
			follows: [],
			options: [],
			parts: ["header", "scope"],
		},
		{
			id: "board",
			title: "Board",
			role: View,
			needs: [Capability.tickets_v1],
			slots: [Main],
			minimum_width: 360,
			sets: [Ticket],
			follows: [Ticket],
			options: [],
			parts: ["header", "group", "ticket"],
		},
		{
			id: "ticket-properties",
			title: "Properties",
			role: Inspector,
			needs: [Capability.tickets_v1],
			slots: [Right, Main],
			minimum_width: 240,
			sets: [],
			follows: [Ticket],
			options: [],
			parts: ["header", "fields", "sessions"],
		},
		{
			id: "rooms",
			title: "Rooms",
			role: Navigator,
			needs: [Capability.rooms_v1],
			slots: [Left, Main, Right],
			minimum_width: 200,
			sets: [Room],
			follows: [],
			options: [],
			parts: ["header", "list", "room"],
		},
		{
			id: "room",
			title: "Room",
			role: View,
			needs: [Capability.rooms_v1],
			slots: [Main, Right],
			minimum_width: 260,
			sets: [],
			follows: [Room],
			options: [],
			parts: ["header", "room", "message", "thread", "composer"],
		},
		{ id: "capabilities", title: "Capabilities", role: View, needs: [], slots: [Left, Main, Right], minimum_width: 200, sets: [], follows: [], options: [], parts: ["header", "manifest"] },
		{ id: "ci", title: "CI runs", role: Inspector, needs: [{ name: "ci", version: 1 }], slots: [Main, Right], minimum_width: 240, sets: [], follows: [Session, Workspace], options: [], parts: ["header"] },
	]

	## The order of a list of sessions or workspaces: the latest first, or by name.
	order : Option
	order = { key: "order", label: "Order", help: "List the latest first, or by name.", kind: Choice({ default: "Latest", choices: ["Latest", "Name"] }) }

	find : Str -> Widget
	find = |id| Widgets.all.find_first(|widget| widget.id == id) ?? { id, title: id, role: View, needs: [], slots: [Left, Main, Right], minimum_width: 200, sets: [], follows: [], options: [], parts: [] }

	## Whether a widget in `role` shows the focus when it is of `kind`.
	shows : Widget, Role, Context.Kind -> Bool
	shows = |widget, role, kind| widget.role == role and widget.follows.contains(kind)

	## The capabilities a widget needs that `advertised` lacks.
	missing : Widget, List(Capability.Id) -> List(Capability.Id)
	missing = |widget, advertised| widget.needs.drop_if(|required| Capability.satisfies(advertised, required))

	## Whether a widget fits a slot. Tiling's `Free` columns take any.
	fits : Widget, Slot -> Bool
	fits = |widget, slot| slot == Free or widget.slots.contains(slot)

	## An option's value as a pane saves it: `"true"` or `"false"`, or the choice.
	default : Option -> Str
	default = |option|
		match option.kind {
			Bool(on) => if (on) "true" else "false"
			Choice({ default: chosen, .. }) => chosen
		}

	## The value of option `key` of `widget` among `values`, or its default.
	value : Widget, List({ key : Str, value : Str }), Str -> Str
	value = |widget, values, key|
		match values.find_first(|set| set.key == key) {
			Ok(set) => set.value
			Err(NotFound) => widget.options.find_first(|option| option.key == key).map_ok(Widgets.default) ?? ""
		}
}

expect Widgets.missing(Widgets.find("chat"), [Capability.chat_v1]) == []
expect Widgets.missing(Widgets.find("ci"), [Capability.chat_v1]) == [{ name: "ci", version: 1 }]
expect Widgets.value(Widgets.find("chat"), [], "tool_output") == "Folded" and Widgets.value(Widgets.find("chat"), [{ key: "show_status", value: "false" }], "show_status") == "false"

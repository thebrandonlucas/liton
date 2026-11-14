## The widgets a layout can hold, declared as data apart from their views:
## the capabilities each needs, the slots it fits and its minimum width,
## whether it shows a context (a session) that follows the focus or is pinned,
## its options, and the parts of it that are stable hooks for styling. When a
## widget is relevant (a `when` expression over the focus) is still to come.
import cap.Capability
import setup.Setup

Widgets := [].{

	## Where a column sits (Setup.Slot).
	Slot : Setup.Slot

	## An option's kind, from a closed set, with its default. Text, Int,
	## CapabilityRef, ContextRef and ThemeToken are next.
	Kind : [Bool(Bool), Choice({ default : Str, choices : List(Str) })]

	Option : { key : Str, label : Str, help : Str, kind : Kind }

	Widget : { id : Str, title : Str, needs : List(Capability.Id), slots : List(Slot), minimum_width : U32, follows_session : Bool, options : List(Option), parts : List(Str) }

	all : List(Widget)
	all = [
		{
			id: "sessions",
			title: "Sessions",
			needs: [Capability.chat_v1],
			slots: [Left, Main],
			minimum_width: 200,
			follows_session: Bool.False,
			options: [{ key: "show_agent", label: "Show agent", help: "Name the agent under each session.", kind: Bool(Bool.True) }],
			parts: ["header", "list", "session"],
		},
		{
			id: "workspaces",
			title: "Workspaces",
			needs: [Capability.workspaces_v1],
			slots: [Left, Main],
			minimum_width: 220,
			follows_session: Bool.False,
			options: [
				{ key: "group_by", label: "Group by", help: "List workspaces under their project, or under what they need from you.", kind: Choice({ default: "Project", choices: ["Project", "Status"] }) },
				{ key: "show_idle", label: "Show idle workspaces", help: "List workspaces whose agents need nothing.", kind: Bool(Bool.True) },
			],
			parts: ["header", "list", "group", "workspace", "session"],
		},
		{
			id: "chat",
			title: "Chat",
			needs: [Capability.chat_v1],
			slots: [Main, Right],
			minimum_width: 300,
			follows_session: Bool.True,
			options: [
				{ key: "tool_output", label: "Tool output", help: "How much of a tool call's output its card shows.", kind: Choice({ default: "Folded", choices: ["Full", "Folded", "Hidden"] }) },
				{ key: "show_status", label: "Show status lines", help: "Show when the agent starts, stops or waits.", kind: Bool(Bool.True) },
			],
			parts: ["header", "timeline", "bubble", "tool-card", "permission", "composer"],
		},
		{
			id: "inbox",
			title: "Inbox",
			needs: [Capability.attention_v1],
			slots: [Left, Main],
			minimum_width: 240,
			follows_session: Bool.False,
			options: [
				{ key: "show_idle", label: "Show idle sessions", help: "List sessions that need nothing, last.", kind: Bool(Bool.False) },
				{ key: "snooze_length", label: "Snooze length", help: "How long Snooze sets an item aside.", kind: Choice({ default: "1 hour", choices: ["1 hour", "1 day", "1 week"] }) },
			],
			parts: ["header", "section", "item", "actions"],
		},
		{
			id: "changes",
			title: "Changes",
			needs: [Capability.workspace_git_v1],
			slots: [Right, Main],
			minimum_width: 240,
			follows_session: Bool.True,
			options: [
				{ key: "diff_layout", label: "Diff layout", help: "Show a file's diff in one column, or old beside new.", kind: Choice({ default: "Unified", choices: ["Unified", "Split"] }) },
				{ key: "show_commits", label: "Show commits", help: "List the branch's commits under its changes.", kind: Bool(Bool.True) },
			],
			parts: ["header", "status", "files", "file", "hunk", "line", "commits"],
		},
		{ id: "capabilities", title: "Capabilities", needs: [], slots: [Left, Main, Right], minimum_width: 200, follows_session: Bool.False, options: [], parts: ["header", "manifest"] },
		{ id: "ci", title: "CI runs", needs: [{ name: "ci", version: 1 }], slots: [Main, Right], minimum_width: 240, follows_session: Bool.True, options: [], parts: ["header"] },
	]

	find : Str -> Widget
	find = |id| Widgets.all.find_first(|widget| widget.id == id) ?? { id, title: id, needs: [], slots: [Left, Main, Right], minimum_width: 200, follows_session: Bool.False, options: [], parts: [] }

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
			Choice({ default, .. }) => default
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

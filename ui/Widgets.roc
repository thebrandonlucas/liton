## The widgets a layout can hold. Each needs capabilities, and says
## whether it shows a context (a session) that follows the focus or is pinned.
import cap.Capability

Widgets := [].{
	Widget : { id : Str, title : Str, needs : List(Capability.Id), follows_session : Bool }

	all : List(Widget)
	all = [
		{ id: "sessions", title: "Sessions", needs: [Capability.chat_v1], follows_session: Bool.False },
		{ id: "chat", title: "Chat", needs: [Capability.chat_v1], follows_session: Bool.True },
		{ id: "changes", title: "Changes", needs: [{ name: "workspace.git", version: 1 }], follows_session: Bool.True },
		{ id: "capabilities", title: "Capabilities", needs: [], follows_session: Bool.False },
		{ id: "ci", title: "CI runs", needs: [{ name: "ci", version: 1 }], follows_session: Bool.True },
	]

	find : Str -> Widget
	find = |id| Widgets.all.find_first(|widget| widget.id == id) ?? { id, title: id, needs: [], follows_session: Bool.False }

	## The capabilities a widget needs that `advertised` lacks.
	missing : Widget, List(Capability.Id) -> List(Capability.Id)
	missing = |widget, advertised| widget.needs.drop_if(|required| Capability.satisfies(advertised, required))
}

expect Widgets.missing(Widgets.find("chat"), [Capability.chat_v1]) == []
expect Widgets.missing(Widgets.find("ci"), [Capability.chat_v1]) == [{ name: "ci", version: 1 }]

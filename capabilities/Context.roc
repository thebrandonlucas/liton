## What a pane is pointed at (see docs/design.md, Context): a session, a
## workspace, a room or a ticket. A pane following the focus derives what it
## shows from it, such as a session's workspace.
Context := [].{

	## A context: a session, a workspace, a room or a ticket, by its id.
	Id : [Session(Str), Workspace(Str), Room(Str), Ticket(Str)]

	## What kind of context one is, which parts declare they set or follow.
	Kind : [Session, Workspace, Room, Ticket]

	## What kind of context `context` is.
	kind : Id -> Kind
	kind = |context|
		match context {
			Session(_) => Session
			Workspace(_) => Workspace
			Room(_) => Room
			Ticket(_) => Ticket
		}

	## A context as topics and pinned panes name it: a session by its id, the
	## others as `workspace:<id>`, `room:<id>` and `ticket:<id>`.
	to_str : Id -> Str
	to_str = |context|
		match context {
			Session(session_id) => session_id
			Workspace(workspace_id) => "workspace:${workspace_id}"
			Room(room_id) => "room:${room_id}"
			Ticket(ticket_id) => "ticket:${ticket_id}"
		}

	## The context `name` names, a session unless it starts with
	## `workspace:`, `room:` or `ticket:`.
	from_str : Str -> Try(Id, [NoContext])
	from_str = |name|
		if name == "" or name == "workspace:" or name == "room:" or name == "ticket:" {
			Err(NoContext)
		} else if name.starts_with("workspace:") {
			Ok(Workspace(name.drop_prefix("workspace:")))
		} else if name.starts_with("room:") {
			Ok(Room(name.drop_prefix("room:")))
		} else if name.starts_with("ticket:") {
			Ok(Ticket(name.drop_prefix("ticket:")))
		} else {
			Ok(Session(name))
		}
}

expect [Session("import:a/b"), Workspace("w1"), Room("general"), Ticket("gh#4")].all(|context| Context.from_str(Context.to_str(context)) == Ok(context))
expect Context.from_str("") == Err(NoContext) and Context.from_str("workspace:") == Err(NoContext) and Context.from_str("room:") == Err(NoContext) and Context.from_str("ticket:") == Err(NoContext)
expect Context.kind(Room("general")) == Room and Context.kind(Session("a")) == Session

## What a pane is pointed at (see docs/design.md, Context): a session or a
## workspace so far. A pane following the focus derives what it shows from
## it, such as a session's workspace.
Context := [].{
	Id : [Session(Str), Workspace(Str)]

	## A context as topics and pinned panes name it: a session by its id, a
	## workspace as `workspace:<id>`.
	to_str : Id -> Str
	to_str = |context|
		match context {
			Session(session_id) => session_id
			Workspace(workspace_id) => "workspace:${workspace_id}"
		}

	## The context `name` names, a session unless it starts with `workspace:`.
	from_str : Str -> Try(Id, [NoContext])
	from_str = |name|
		if name == "" or name == "workspace:" {
			Err(NoContext)
		} else if name.starts_with("workspace:") {
			Ok(Workspace(name.drop_prefix("workspace:")))
		} else {
			Ok(Session(name))
		}
}

expect [Session("import:a/b"), Workspace("w1")].all(|context| Context.from_str(Context.to_str(context)) == Ok(context))
expect Context.from_str("") == Err(NoContext) and Context.from_str("workspace:") == Err(NoContext)

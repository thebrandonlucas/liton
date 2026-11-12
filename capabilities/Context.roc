## What a pane is pointed at (see docs/design.md, Context): a session or a
## workspace so far. A pane following the focus derives what it shows from
## it, such as a session's workspace.
Context := [].{
	Id : [Session(Str), Workspace(Str)]
}

## `workspaces.v1`: the projects agents work in and their workspaces, each a
## directory: a checkout, a worktree or a plain directory. Each workspace
## lists its sessions, and is as urgent as the most urgent of them. Only
## listing so far; Create, Archive, Rename and Pin are the commands to come.
import Attention
import Chat

Workspaces := [].{
	Project : { id : Str, provider : Str, name : Str, directory : Str }

	## `changes` counts the lines of the uncommitted changes, when the provider
	## does. `state` is the most urgent of its sessions' (see `state`).
	Workspace : {
		id : Str,
		provider : Str,
		project_id : Str,
		name : Str,
		directory : Str,
		kind : [Checkout, Worktree, Directory],
		branch : [Branch(Str), Detached, NotGit],
		state : Attention.State,
		dirty : Bool,
		changes : [Counted({ additions : U32, deletions : U32 }), Uncounted],
		pinned : Bool,
		labels : List(Str),
		session_ids : List(Str),
	}

	Listed : { projects : List(Project), workspaces : List(Workspace) }

	Request : [ListWorkspaces]

	Response : [Listed(Listed), Rejected(Str)]

	## The most urgent state of the sessions of `session_ids`, as attention
	## ranks them, Idle for none.
	state : List(Chat.Session), List(Str) -> Attention.State
	state = |sessions, session_ids| {
		states = sessions.keep_if(|session| session_ids.contains(session.id)).map(|session| Attention.item(session, []).state)
		Attention.ranks.find_first(|ranked| states.contains(ranked)) ?? Idle
	}
}

with_status : Str, Chat.Status -> Chat.Session
with_status = |id, status| { id, provider: "mock", agent: "claude", title: "", status }

expect Workspaces.state([with_status("s1", Finished), with_status("s2", Failed("")), with_status("s3", AwaitingPermission)], ["s1", "s2"]) == Failed
expect Workspaces.state([with_status("s1", Finished)], []) == Idle

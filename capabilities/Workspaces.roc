## `workspaces.v1`: the projects agents work in and their workspaces, each a
## directory: a checkout, a worktree or a plain directory. Each workspace
## lists its sessions, and is as urgent as the most urgent of them. Only
## listing so far; Create, Archive, Rename and Pin are the commands to come.
import Attention

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

	## The most urgent state of the items of `session_ids`, Idle for none.
	state : List(Attention.Item), List(Str) -> Attention.State
	state = |items, session_ids| {
		states = items.keep_if(|shown| session_ids.contains(shown.session_id)).map(|shown| shown.state)
		Attention.ranks.find_first(|ranked| states.contains(ranked)) ?? Idle
	}
}

item : Str, Attention.State -> Attention.Item
item = |session_id, state| { session_id, provider: "mock", title: "", agent: "claude", state, summary: "", permissions: [], signature: "", set_aside: No }

expect Workspaces.state([item("s1", Done), item("s2", Failed), item("s3", NeedsYou)], ["s1", "s2"]) == Failed
expect Workspaces.state([item("s1", Done)], []) == Idle

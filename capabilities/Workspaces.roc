## `workspaces.v1`: the projects agents work in and their workspaces, each a
## directory: a checkout, a worktree or a plain directory. Each workspace
## lists its sessions, and is as urgent as the most urgent of them. Listed,
## created, renamed, pinned and archived; projects renamed.
import Attention
import Chat

Workspaces := [].{

	## A project: a directory its provider makes workspaces of.
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

	## The projects and workspaces a provider lists.
	Listed : { projects : List(Project), workspaces : List(Workspace) }

	## `Create` makes a workspace of a project: a checkout of its directory,
	## or a worktree on a new branch, named `branch` or by the provider. It
	## answers `Created` with the workspace's id. `Rename` gives a workspace,
	## or `RenameProject` a project, a name, or with "" the one its provider
	## derives; `Pin` pins or unpins a workspace, and `Archive` lists it no
	## more. Each answers `Accepted`.
	Request : [
		ListWorkspaces,
		Create(Create),
		Rename({ workspace_id : Str, name : Str }),
		Pin({ workspace_id : Str, pinned : Bool }),
		Archive({ workspace_id : Str }),
		RenameProject({ project_id : Str, name : Str }),
	]

	## A workspace to make of a project: a checkout, or a worktree on a new
	## branch, named `branch` or by the provider.
	Create : { project_id : Str, kind : [Checkout, Worktree], branch : Try(Str, [Missing]) }

	## What a request answers: the listing, the id of a workspace created,
	## that the provider took it, or why it refused.
	Response : [Listed(Listed), Rejected(Str), Created({ workspace_id : Str }), Accepted]

	## The most urgent state of the sessions of `session_ids`, as attention
	## ranks them, Idle for none.
	state : List(Chat.Session), List(Str) -> Attention.State
	state = |sessions, session_ids| {
		states = sessions.keep_if(|session| session_ids.contains(session.id)).map(|session| Attention.item(session, []).state)
		Attention.ranks.find_first(|ranked| states.contains(ranked)) ?? Idle
	}
}

with_status : Str, Chat.Status -> Chat.Session
with_status = |id, status| Chat.session({ id, provider: "mock", agent: "claude", title: "", status })

expect Workspaces.state([with_status("s1", Finished), with_status("s2", Failed("")), with_status("s3", AwaitingPermission)], ["s1", "s2"]) == Failed
expect Workspaces.state([with_status("s1", Finished)], []) == Idle

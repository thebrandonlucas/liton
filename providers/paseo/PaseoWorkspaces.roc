import cap.Workspaces
import Paseo

## Paseo's projects and workspaces as workspaces.v1's, from its WebSocket. Only
## reads: liton calls none of Paseo's workspace writes (create, archive,
## rename, pin...).
PaseoWorkspaces := [].{

	## A workspace as `fetch_workspaces_response` describes it. Paseo leaves
	## out its git (`git_runtime`) until it has looked, so the branch falls
	## back to the one Paseo placed it on (`project`).
	Descriptor : {
		id : Str,
		project_id : Str,
		project_display_name : Str,
		project_root_path : Str,
		workspace_directory : Try(Str, [Missing]),
		project_kind : Str,
		workspace_kind : Str,
		name : Str,
		pinned_at : Try(Try(Str, [Null]), [Missing]),
		labels : Try(List(Str), [Missing]),
		diff_stat : Try(Try({ additions : U32, deletions : U32 }, [Null]), [Missing]),
		git_runtime : Try(Try({ current_branch : Try(Try(Str, [Null]), [Missing]), is_dirty : Try(Try(Bool, [Null]), [Missing]) }, [Null]), [Missing]),
		project : Try({ checkout : { current_branch : Try(Try(Str, [Null]), [Missing]) } }, [Missing]),
	}

	## A project none of whose workspaces is open.
	EmptyProject : { project_id : Str, project_display_name : Str, project_root_path : Str }

	## As many as Paseo lists at once.
	request : Str -> Str
	request = |request_id| Json.to_str({ type: "session", message: { type: "fetch_workspaces_request", requestId: request_id, page: { limit: 200.U16 } } })

	## The projects and workspaces in a `fetch_workspaces_response`, each
	## workspace Idle and without sessions: the daemon places its agents in
	## them.
	answer : Str, Str -> Try(Workspaces.Listed, [OtherMessage, InvalidJson(Str), MissingRequiredField(Str)])
	answer = |text, request_id| {
		answered : Try({ message : { payload : { entries : List(Descriptor), empty_projects : Try(List(EmptyProject), [Missing]) } } }, _)
		answered = Json.parser_camel()(Paseo.answer_to(text, "fetch_workspaces_response", request_id)?)
		payload = answered?.message.payload
		projects = payload.entries.map(|shown| { project_id: shown.project_id, project_display_name: shown.project_display_name, project_root_path: shown.project_root_path }).concat(payload.empty_projects ?? []).fold(
			[],
			|so_far, project| if (so_far.any(|known| known.id == project.project_id)) so_far else so_far.append({ id: project.project_id, provider: "paseo", name: project.project_display_name, directory: project.project_root_path }),
		)
		Ok({ projects, workspaces: payload.entries.map(workspace) })
	}
}

workspace : PaseoWorkspaces.Descriptor -> Workspaces.Workspace
workspace = |shown| {
	is_git = shown.project_kind == "git"
	runtime_branch = shown.git_runtime.map_ok(|runtime| runtime.map_ok(|known| known.current_branch ?? Err(Null)) ?? Err(Null)) ?? Err(Null)
	placed_branch = shown.project.map_ok(|placed| placed.checkout.current_branch ?? Err(Null)) ?? Err(Null)
	branch =
		match (is_git, runtime_branch, placed_branch) {
			(Bool.False, _, _) => NotGit
			(_, Ok(name), _) => Branch(name)
			(_, _, Ok(name)) => Branch(name)
			_ => Detached
		}
	kind =
		match shown.workspace_kind {
			"worktree" => Worktree
			"directory" => Directory
			_ => if (is_git) Checkout else Directory
		}
	{
		id: shown.id,
		provider: "paseo",
		project_id: shown.project_id,
		name: shown.name,
		directory: shown.workspace_directory ?? shown.project_root_path,
		kind,
		branch,
		state: Idle,
		dirty: shown.git_runtime.map_ok(|runtime| runtime.map_ok(|known| known.is_dirty.map_ok(|dirty| dirty ?? Bool.False) ?? Bool.False) ?? Bool.False) ?? Bool.False,
		changes: shown.diff_stat.map_ok(|stat| stat.map_ok(|counts| Counted(counts)) ?? Uncounted) ?? Uncounted,
		pinned: shown.pinned_at.map_ok(|pinned| pinned.is_ok()) ?? Bool.False,
		labels: shown.labels ?? [],
		session_ids: [],
	}
}

# Synthetic fixtures in Paseo's shapes.

descriptor : Str -> Str
descriptor = |fields|
	\\{"projectId":"p1","projectDisplayName":"app","projectRootPath":"/work/app","archivingAt":null,"status":"running","statusEnteredAt":null,"activityAt":null,"scripts":[],"githubRuntime":{"featuresEnabled":true,"pullRequest":null},${fields}}

expect {
	worktree = descriptor(
		\\"id":"w1","workspaceDirectory":"/work/app-fix","worktreeSlug":"app-fix","projectKind":"git","workspaceKind":"worktree","name":"fix-login","title":null,"pinnedAt":"2026-01-01T00:00:00.000Z","labels":["auth"],"diffStat":{"additions":3,"deletions":1},"gitRuntime":{"currentBranch":"fix-login","remoteUrl":null,"isPaseoOwnedWorktree":true,"isDirty":true,"aheadBehind":null}
	)
	looked_at_later = descriptor(
		\\"id":"w2","projectKind":"git","workspaceKind":"local_checkout","name":"main","project":{"projectKey":"p1","projectName":"app","checkout":{"cwd":"/work/app","isGit":true,"currentBranch":"main","remoteUrl":null,"isPaseoOwnedWorktree":false,"mainRepoRoot":null}}
	)
	plain = "{\"id\":\"w3\",\"projectId\":\"p2\",\"projectDisplayName\":\"notes\",\"projectRootPath\":\"/notes\",\"workspaceDirectory\":\"/notes\",\"projectKind\":\"non_git\",\"workspaceKind\":\"local_checkout\",\"name\":\"notes\",\"status\":\"done\",\"activityAt\":null,\"diffStat\":null,\"gitRuntime\":null}"
	empty = "{\"projectId\":\"p3\",\"projectDisplayName\":\"old\",\"projectRootPath\":\"/old\",\"projectKind\":\"git\"}"
	text = "{\"type\":\"session\",\"message\":{\"type\":\"fetch_workspaces_response\",\"payload\":{\"requestId\":\"r1\",\"entries\":[${worktree},${looked_at_later},${plain}],\"emptyProjects\":[${empty}],\"pageInfo\":{\"nextCursor\":null,\"prevCursor\":null,\"hasMore\":false}}}}"
	none = { id: "", provider: "paseo", project_id: "p1", name: "", directory: "/work/app", kind: Checkout, branch: Detached, state: Idle, dirty: Bool.False, changes: Uncounted, pinned: Bool.False, labels: [], session_ids: [] }
	PaseoWorkspaces.answer(text, "r1")
		== Ok({
			projects: [{ id: "p1", provider: "paseo", name: "app", directory: "/work/app" }, { id: "p2", provider: "paseo", name: "notes", directory: "/notes" }, { id: "p3", provider: "paseo", name: "old", directory: "/old" }],
			workspaces: [
				{ ..none, id: "w1", name: "fix-login", directory: "/work/app-fix", kind: Worktree, branch: Branch("fix-login"), dirty: Bool.True, changes: Counted({ additions: 3, deletions: 1 }), pinned: Bool.True, labels: ["auth"] },
				{ ..none, id: "w2", name: "main", branch: Branch("main") },
				{ ..none, id: "w3", project_id: "p2", name: "notes", directory: "/notes", kind: Directory, branch: NotGit },
			],
		})
}

expect PaseoWorkspaces.answer("{\"type\":\"session\",\"message\":{\"type\":\"rpc_error\",\"payload\":{\"requestId\":\"r1\",\"requestType\":\"fetch_workspaces_request\",\"error\":\"boom\"}}}", "r1").map_ok(|_| {}) == Err(OtherMessage)

import cap.Capability
import cap.Chat
import cap.Manifest
import cap.WorkspaceGit
import cap.Workspaces

Mock := [].{
	provider : Manifest.Provider
	provider = { id: "mock", name: "Mock agents", capabilities: [Capability.chat_v1, Capability.workspace_git_v1, Capability.workspaces_v1] }

	## An event and how long after the request that caused it it happens.
	Scheduled : { delay_ms : U64, event : Chat.Event }

	Seed : { id : Str, agent : Str, title : Str, events : List(Chat.Event) }

	## The sessions a fresh daemon starts with.
	seeds : List(Seed)
	seeds = [
		{
			id: "fix-auth",
			agent: "claude",
			title: "Fix the login redirect",
			events: [
				UserMessage({ text: "Logging in sends me back to /login. Can you fix it?" }),
				StatusChanged(Running),
				ToolCall({ call_id: "seed-1", tool: "bash", input: "rg -n redirect src/Auth.roc" }),
				ToolResult({ call_id: "seed-1", output: "src/Auth.roc:41:\tredirect_to = \"/login\"", failed: Bool.False }),
				AgentMessage({ text: "The redirect target is hard-coded to /login. I changed it to the page you came from." }),
				StatusChanged(Idle),
			],
		},
		{
			id: "flaky-ci",
			agent: "codex",
			title: "Find the flaky CI test",
			events: [
				UserMessage({ text: "CI fails about one run in five. Find out why." }),
				StatusChanged(Running),
				ToolCall({ call_id: "seed-2", tool: "bash", input: "zig build test --summary all" }),
				ToolResult({ call_id: "seed-2", output: "test.timeline_order... FAIL (expected 3, got 2)", failed: Bool.True }),
				PermissionRequested({ request_id: "seed-3", tool: "edit", description: "Sort entries by sequence in tests/timeline.roc" }),
				StatusChanged(AwaitingPermission),
			],
		},
		{ id: "notes", agent: "claude", title: "Scratch", events: [StatusChanged(Idle)] },
	]

	## What follows a message. `next` is the timeline's next sequence number,
	## which makes the ids of the calls and requests unique.
	on_message : Str, U64 -> List(Scheduled)
	on_message = |text, next| {
		call_id = "call-${next.to_str()}"
		[
			{ delay_ms: 0, event: UserMessage({ text: text }) },
			{ delay_ms: 400, event: StatusChanged(Running) },
			{ delay_ms: 1200, event: AgentMessage({ text: "Looking into it: \"${text}\"" }) },
			{ delay_ms: 2000, event: ToolCall({ call_id, tool: "bash", input: "rg -n TODO src" }) },
			{ delay_ms: 3200, event: ToolResult({ call_id, output: "src/Main.roc:12: # TODO handle the empty case", failed: Bool.False }) },
			{ delay_ms: 4000, event: PermissionRequested({ request_id: "permission-${next.to_str()}", tool: "edit", description: "Edit src/Main.roc to handle the empty case" }) },
			{ delay_ms: 4000, event: StatusChanged(AwaitingPermission) },
		]
	}

	## What follows an answer to a pending permission request.
	on_answer : Str, Bool, U64 -> List(Scheduled)
	on_answer = |request_id, allowed, next| {
		answered = { delay_ms: 0, event: PermissionAnswered({ request_id, allowed }) }
		if allowed {
			call_id = "call-${next.to_str()}"
			[
				answered,
				{ delay_ms: 300, event: StatusChanged(Running) },
				{ delay_ms: 1500, event: ToolCall({ call_id, tool: "edit", input: "src/Main.roc" }) },
				{ delay_ms: 2200, event: ToolResult({ call_id, output: "1 file changed, 3 insertions(+)", failed: Bool.False }) },
				{ delay_ms: 3000, event: AgentMessage({ text: "Done: src/Main.roc handles the empty case now." }) },
				{ delay_ms: 3000, event: StatusChanged(Idle) },
			]
		} else {
			[
				answered,
				{ delay_ms: 500, event: AgentMessage({ text: "Okay, I left src/Main.roc alone." }) },
				{ delay_ms: 500, event: StatusChanged(Idle) },
			]
		}
	}

	## A session's status: the last status its timeline reports.
	status : List(Chat.Entry) -> Chat.Status
	status = |timeline|
		timeline.fold(
			Idle,
			|current, entry|
				match entry.event {
					StatusChanged(next) => next
					_ => current
				},
		)

	## The seed sessions' project, liton, in two workspaces: fix-auth's
	## worktree, and the checkout of main the others work in.
	projects : List(Workspaces.Project)
	projects = [{ id: "liton", provider: "mock", name: "liton", directory: "/mock/liton" }]

	## Each Idle: the daemon rolls up its sessions' states (see `Workspaces.state`).
	workspaces : List(Workspaces.Workspace)
	workspaces = [
		{ id: "fix-auth", provider: "mock", project_id: "liton", name: "fix-auth", directory: "/mock/liton-fix-auth", kind: Worktree, branch: Branch("fix-auth"), state: Idle, dirty: Bool.True, changes: Counted({ additions: 1, deletions: 1 }), pinned: Bool.True, labels: ["auth"], session_ids: ["fix-auth"] },
		{ id: "main", provider: "mock", project_id: "liton", name: "main", directory: "/mock/liton", kind: Checkout, branch: Branch("main"), state: Idle, dirty: Bool.False, changes: Counted({ additions: 0, deletions: 0 }), pinned: Bool.False, labels: [], session_ids: ["flaky-ci", "notes"] },
	]

	## A workspace's git. fix-auth's has the login fix uncommitted and one
	## commit ahead of main; main is clean.
	git : Str, WorkspaceGit.Scope, [Selected(Str), NoFile] -> WorkspaceGit.Found
	git = |workspace_id, scope, file| {
		directory = Mock.workspaces.find_first(|shown| shown.id == workspace_id).map_ok(|shown| shown.directory) ?? "/mock/${workspace_id}"
		workspace = { id: directory, provider: "mock", name: "liton", directory, repository_root: directory, kind: if (workspace_id == "fix-auth") Worktree else Checkout }
		clean = { branch: Branch("main"), base: Base("main"), dirty: Bool.False, ahead: 0, behind: 0, upstream: NoUpstream }
		if workspace_id != "fix-auth" {
			{ workspace, status: Status(clean), fingerprint: WorkspaceGit.fingerprint(scope, []), diff: [], commits: [] }
		} else {
			commit = { sha: "4f2a9c1e7b3d5a6f8e0c2b4d6a8f0e1c3b5d7a9f", short_sha: "4f2a9c1", subject: "Test the login redirect", author: "Mock Agent", date: "2026-01-01T09:00:00Z", pushed: Bool.False, on_base: Bool.False, files: [login_test.file] }
			diff =
				match scope {
					Uncommitted => [login_fix]
					AgainstBase => [login_fix, login_test]
					Commit(sha) => if (sha == commit.sha) [{ file: login_test.file, hunks: if (file == Selected(login_test.file.path)) login_test.hunks else [] }] else []
				}
			{ workspace, status: Status({ ..clean, branch: Branch("fix-auth"), dirty: Bool.True, ahead: 1 }), fingerprint: WorkspaceGit.fingerprint(scope, diff), diff, commits: [commit] }
		}
	}
}

login_fix : WorkspaceGit.FileDiff
login_fix = {
	file: { path: "src/Auth.roc", change: Modified, additions: 1, deletions: 1, body: Text },
	hunks: [WorkspaceGit.hunk({ old_start: 40, old_count: 3, new_start: 40, new_count: 3 }, [{ kind: Context, text: "login = |request|" }, { kind: Removed, text: "\tredirect_to = \"/login\"" }, { kind: Added, text: "\tredirect_to = request.came_from" }, { kind: Context, text: "\tSession.start(redirect_to)" }])],
}

login_test : WorkspaceGit.FileDiff
login_test = {
	file: { path: "tests/Auth.roc", change: Added, additions: 3, deletions: 0, body: Text },
	hunks: [WorkspaceGit.hunk({ old_start: 0, old_count: 0, new_start: 1, new_count: 3 }, [{ kind: Added, text: "import Auth" }, { kind: Added, text: "" }, { kind: Added, text: "expect Auth.login({ came_from: \"/inbox\" }).redirect_to == \"/inbox\"" }])],
}

expect Mock.on_message("hi", 7).len() == 7
expect Mock.on_answer("p", Bool.False, 3).len() == 3
expect Mock.status([{ sequence: 1, event: StatusChanged(Running) }, { sequence: 2, event: AgentMessage({ text: "x" }) }]) == Running
expect Mock.status([]) == Idle
expect Mock.git("main", Uncommitted, NoFile).diff == []
expect Mock.git("fix-auth", Commit("4f2a9c1e7b3d5a6f8e0c2b4d6a8f0e1c3b5d7a9f"), Selected("tests/Auth.roc")).diff.map(|shown| shown.hunks.len()) == [1]

# Each seed session works in one workspace, of a listed project.
expect Mock.seeds.all(|seed| Mock.workspaces.keep_if(|shown| shown.session_ids.contains(seed.id)).len() == 1)
expect Mock.workspaces.all(|shown| Mock.projects.any(|project| project.id == shown.project_id))

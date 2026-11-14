import cap.Capability
import cap.Chat
import cap.Files
import cap.Manifest
import cap.WorkspaceGit
import cap.Workspaces

Mock := [].{
	provider : Manifest.Provider
	provider = { id: "mock", name: "Mock agents", capabilities: [Capability.chat_v1, Capability.workspace_git_v1, Capability.workspaces_v1, Capability.files_v1] }

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
				AgentMessage({ text: "The redirect target is hard-coded to `/login`. I changed it to **the page you came from**:\n\n```roc\n# src/Auth.roc\nredirect_to = request.came_from ?? \"/\"\n```\n\n- Logging in now returns you where you were.\n- With no page to go back to, you land on `/`." }),
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

	## What follows stopping a session whose timeline so far is `timeline`,
	## once the rest of its script is dropped: its pending requests denied,
	## and it idle. Nothing when it isn't running.
	on_cancel : List(Chat.Entry) -> List(Scheduled)
	on_cancel = |timeline|
		if [Running, AwaitingPermission].contains(Mock.status(timeline)) {
			Chat.pending_permissions(timeline).map(|request_id| { delay_ms: 0, event: PermissionAnswered({ request_id, allowed: Bool.False }) }).concat([{ delay_ms: 0, event: AgentMessage({ text: "Stopped." }) }, { delay_ms: 0, event: StatusChanged(Idle) }])
		} else {
			[]
		}

	## A session from its timeline's visible events, each with when it became
	## visible (ms since the epoch): its status, its agent's model, the
	## workspace it works in and its branch, when its running turn started and
	## when it last changed.
	session : { id : Str, agent : Str, title : Str }, List({ visible_at : I64, event : Chat.Event }) -> Chat.Session
	session = |{ id, agent, title }, timed| {
		current = Mock.status(timed.map(|shown| { sequence: 0, event: shown.event }))
		placed = Mock.workspaces.find_first(|shown| shown.session_ids.contains(id))
		last_status = timed.keep_if(
			|shown| match shown.event {
				StatusChanged(_) => Bool.True
				_ => Bool.False
			},
		).last()
		{
			..Chat.session({ id, provider: "mock", agent, title, status: current }),
			model: Ok(if (agent == "codex") "gpt-5-codex" else "claude-sonnet-4-5"),
			workspace: placed.map_ok(|shown| { id: Ok(shown.id), directory: shown.directory }).map_err(|_| Missing),
			branch: placed.map_ok(
				|shown| match shown.branch {
					Branch(name) => Ok(name)
					_ => Err(Missing)
				},
			) ?? Err(Missing),
			running_since: if (current == Running) last_status.map_ok(|shown| timestamp(shown.visible_at)).map_err(|_| Missing) else Err(Missing),
			updated: timed.last().map_ok(|shown| timestamp(shown.visible_at)).map_err(|_| Missing),
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

	## The files of each mock workspace: a README and a link to it, the login
	## code, a generated file longer than a client is sent, and a logo,
	## binary.
	files : List({ path : Str, body : [Text(Str), Binary(U64), LinkTo(Str)] })
	files = [
		{ path: "README.md", body: Text("# liton\n\nThe mock provider's project, to try liton without a real one.\n") },
		{ path: "AGENTS.md", body: LinkTo("README.md") },
		{ path: "src/Auth.roc", body: Text("login = |request|\n\tredirect_to = request.came_from\n\tSession.start(redirect_to)\n") },
		{ path: "src/Generated.roc", body: Text(Str.repeat("# A generated line, of a file too long to send whole.\n", 6_000)) },
		{ path: "assets/logo.png", body: Binary(4_096) },
	]

	## A mock workspace's directory at `path`, "." for its own.
	tree : Str -> Files.Tree
	tree = |path| {
		inside = if (path == ".") "" else "${path}/"
		entries = Mock.files.keep_if(|file| file.path.starts_with(inside)).fold(
			[],
			|so_far, file| {
				rest = file.path.drop_prefix(inside).split_on("/")
				name = rest.first() ?? ""
				kind = match file.body {
					_ if rest.len() > 1 => Directory
					LinkTo(_) => Symlink
					_ => File
				}
				if (so_far.any(|known| known.name == name)) so_far else so_far.append({ name, kind, size: if (kind == Directory) 0 else size_of(file.body), modified: changed_at })
			},
		)
		{ path, listing: if (entries.is_empty()) Unreadable("no directory ${path}") else Listed(entries) }
	}

	## A mock workspace's file at `path`, a link's target's.
	contents : Str -> Files.Contents
	contents = |path| {
		read =
			match Mock.files.find_first(|file| file.path == path).map_ok(|file| file.body) {
				Ok(LinkTo(target)) => Mock.contents(target).read
				Ok(Text(text)) => {
					capped = Files.capped(text)
					Text({ text: capped.text, truncated: capped.truncated, size: text.count_utf8_bytes(), modified: changed_at })
				}
				Ok(Binary(size)) => Binary({ size, modified: changed_at })
				Err(_) => Unreadable("no file ${path}")
			}
		{ path, read }
	}
}

changed_at : Str
changed_at = "2026-01-01T09:00:00.000Z"

size_of : [Text(Str), Binary(U64), LinkTo(Str)] -> U64
size_of = |body|
	match body {
		Text(text) => text.count_utf8_bytes()
		Binary(size) => size
		LinkTo(target) => target.count_utf8_bytes()
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

## Milliseconds since the epoch as a time such as 2026-01-01T09:00:00.000Z,
## by the days-to-civil-date algorithm of Howard Hinnant's chrono notes.
timestamp : I64 -> Str
timestamp = |ms| {
	days = ms // 86_400_000 + 719_468
	era = days // 146_097
	day_of_era = days - era * 146_097
	year_of_era = (day_of_era - day_of_era // 1_460 + day_of_era // 36_524 - day_of_era // 146_096) // 365
	day_of_year = day_of_era - (365 * year_of_era + year_of_era // 4 - year_of_era // 100)
	month_index = (5 * day_of_year + 2) // 153
	month = if (month_index < 10) month_index + 3 else month_index - 9
	year = year_of_era + era * 400 + (if (month <= 2) 1 else 0)
	padded = |number, width| {
		digits = number.to_str()
		"${Str.repeat("0", width - digits.count_utf8_bytes())}${digits}"
	}
	of_day = ms % 86_400_000
	"${year.to_str()}-${padded(month, 2)}-${padded(day_of_year - (153 * month_index + 2) // 5 + 1, 2)}T${padded(of_day // 3_600_000, 2)}:${padded(of_day // 60_000 % 60, 2)}:${padded(of_day // 1_000 % 60, 2)}.${padded(of_day % 1_000, 3)}Z"
}

expect [0, 951_782_400_000, 1_767_258_000_123, 1_709_210_096_789].map(timestamp) == ["1970-01-01T00:00:00.000Z", "2000-02-29T00:00:00.000Z", "2026-01-01T09:00:00.123Z", "2024-02-29T12:34:56.789Z"]

expect {
	running = Mock.session({ id: "flaky-ci", agent: "codex", title: "CI" }, [{ visible_at: 0, event: StatusChanged(Idle) }, { visible_at: 1_767_258_000_000, event: StatusChanged(Running) }, { visible_at: 1_767_258_060_000, event: AgentMessage({ text: "x" }) }])
	running.status == Running
		and running.workspace == Ok({ id: Ok("main"), directory: "/mock/liton" })
		and running.branch == Ok("main")
		and running.running_since == Ok("2026-01-01T09:00:00.000Z")
		and running.updated == Ok("2026-01-01T09:01:00.000Z")
		and Mock.session({ id: "notes", agent: "claude", title: "" }, [{ visible_at: 0, event: StatusChanged(Idle) }]).running_since == Err(Missing)
}

expect Mock.on_message("hi", 7).len() == 7
expect Mock.on_answer("p", Bool.False, 3).len() == 3
expect Mock.status([{ sequence: 1, event: StatusChanged(Running) }, { sequence: 2, event: AgentMessage({ text: "x" }) }]) == Running
expect Mock.status([]) == Idle

expect {
	asked = [{ sequence: 1, event: StatusChanged(Running) }, { sequence: 2, event: PermissionRequested({ request_id: "p1", tool: "edit", description: "" }) }, { sequence: 3, event: StatusChanged(AwaitingPermission) }]
	Mock.on_cancel(asked).map(|scheduled| scheduled.event) == [PermissionAnswered({ request_id: "p1", allowed: Bool.False }), AgentMessage({ text: "Stopped." }), StatusChanged(Idle)]
		and Mock.on_cancel([{ sequence: 1, event: StatusChanged(Idle) }]) == []
}
expect Mock.git("main", Uncommitted, NoFile).diff == []
expect Mock.git("fix-auth", Commit("4f2a9c1e7b3d5a6f8e0c2b4d6a8f0e1c3b5d7a9f"), Selected("tests/Auth.roc")).diff.map(|shown| shown.hunks.len()) == [1]

# Each seed session works in one workspace, of a listed project.
expect Mock.seeds.all(|seed| Mock.workspaces.keep_if(|shown| shown.session_ids.contains(seed.id)).len() == 1)
expect Mock.workspaces.all(|shown| Mock.projects.any(|project| project.id == shown.project_id))

expect {
	names = |listing|
		match listing {
			Listed(entries) => entries.map(|entry| (entry.name, entry.kind))
			_ => []
		}
	names(Mock.tree(".").listing) == [("README.md", File), ("AGENTS.md", Symlink), ("src", Directory), ("assets", Directory)]
		and names(Mock.tree("src").listing) == [("Auth.roc", File), ("Generated.roc", File)]
		and Mock.tree("README.md").listing == Unreadable("no directory README.md")
}

expect {
	read = |path| Mock.contents(path).read
	cut_short =
		match read("src/Generated.roc") {
			Text({ text, truncated, size, .. }) => truncated and text.count_utf8_bytes() == Files.text_limit and size > Files.text_limit
			_ => Bool.False
		}
	cut_short and read("AGENTS.md") == read("README.md") and read("assets/logo.png") == Binary({ size: 4_096, modified: changed_at }) and read("src") == Unreadable("no file src")
}

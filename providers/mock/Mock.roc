import cap.Capability
import cap.Chat
import cap.Files
import cap.Manifest
import cap.WorkspaceGit
import cap.Workspaces

Mock := [].{

	## The mock provider, with every capability it can offer.
	provider : Manifest.Provider
	provider = { id: "mock", name: "Mock agents", capabilities: [Capability.chat_v1, Capability.workspace_git_v1, Capability.workspaces_v1, Capability.files_v1, Capability.rooms_v1, Capability.tickets_v1, Capability.schedules_v1] }

	## The parts of the mock a daemon offers: its scripted agents (chat,
	## workspaces, workspace.git, files and schedules), its rooms and its
	## tickets.
	Parts : { agents : Bool, rooms : Bool, tickets : Bool }

	## The mock provider offering only the capabilities of `parts`.
	offering : Parts -> Manifest.Provider
	offering = |parts| {
		..Mock.provider,
		capabilities: Mock.provider.capabilities.keep_if(
			|capability|
				if (capability == Capability.rooms_v1) parts.rooms else if (capability == Capability.tickets_v1) parts.tickets else parts.agents,
		),
	}

	## An event and how long after the request that caused it it happens.
	Scheduled : { delay_ms : U64, event : Chat.Event }

	## A session a fresh daemon starts with: its id, agent, title and timeline.
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
				PermissionRequested(Chat.permission({ request_id: "seed-3", tool: "edit", description: "Sort entries by sequence in tests/timeline.roc" })),
				StatusChanged(AwaitingPermission),
			],
		},
		{ id: "notes", agent: "claude", title: "Scratch", events: [StatusChanged(Idle)] },
	]

	## The sessions a fresh daemon starts with archived, for its history.
	archived_seeds : List(Seed)
	archived_seeds = [
		{
			id: "old-readme",
			agent: "claude",
			title: "Tidy the README",
			events: [
				UserMessage({ text: "The README repeats itself. Tidy it." }),
				StatusChanged(Running),
				AgentMessage({ text: "I merged the two install sections and cut the repeated usage notes." }),
				StatusChanged(Idle),
			],
		},
	]

	## A page of `sessions`, the history `ListHistory` asks for: those whose
	## title, agent or directory holds `search`, whatever its case, the
	## latest first, `limit` of them from the `offset`th on, and whether more
	## follow.
	history : List(Chat.Session), { search : Str, offset : U64, limit : U64 } -> { sessions : List(Chat.Session), more : Bool }
	history = |sessions, { search, offset, limit }| {
		wanted = search.trim().with_ascii_lowercased()
		held = |shown| "${shown.title} ${shown.agent} ${shown.workspace.map_ok(|placed| placed.directory) ?? ""}".with_ascii_lowercased().contains(wanted)
		# A time as its digits, which order as it does.
		moment = |shown| (shown.updated ?? "").to_utf8().keep_if(|byte| byte >= '0' and byte <= '9').fold(0, |number, digit| number * 10 + (digit - '0').to_u64())
		latest = sessions.keep_if(held).sort_with(|left, right| if (moment(left) > moment(right)) Before else if (moment(left) < moment(right)) After else Same)
		{ sessions: latest.drop_first(offset).take_first(limit), more: latest.len() > offset + limit }
	}

	## The plan a message asking for one gets, and its choices, as Claude's
	## in Paseo.
	plan : Str
	plan =
		\\## Plan
		\\
		\\1. Find where an empty list reaches `first` in `src/Main.roc`.
		\\2. Return **an empty result** there instead of crashing.
		\\3. Add a test for the empty case, and run `zig build test`.

	## The choices the plan's permission request offers: Reject, Implement, and
	## Implement with Auto.
	plan_choices : List(Chat.Choice)
	plan_choices = [
		{ id: "reject", label: "Reject", allows: Bool.False, style: Danger },
		{ id: "implement", label: "Implement", allows: Bool.True, style: Primary },
		{ id: "implement_resume", label: "Implement with Auto", allows: Bool.True, style: Secondary },
	]

	## What follows a message. `next` is the timeline's next sequence number,
	## which makes the ids of the calls and requests unique. A message that
	## asks for a plan gets one to approve, in Markdown with its own choices.
	on_message : Str, U64 -> List(Scheduled)
	on_message = |text, next| {
		call_id = "call-${next.to_str()}"
		request_id = "permission-${next.to_str()}"
		asked : Chat.Permission
		asked =
			if text.with_ascii_lowercased().contains("plan") {
				{ ..Chat.permission({ request_id, tool: "ExitPlanMode", description: "Plan: handle the empty case" }), body: Ok(Mock.plan), choices: Ok(Mock.plan_choices) }
			} else {
				Chat.permission({ request_id, tool: "edit", description: "Edit src/Main.roc to handle the empty case" })
			}
		[
			{ delay_ms: 0, event: UserMessage({ text: text }) },
			{ delay_ms: 400, event: StatusChanged(Running) },
			{ delay_ms: 1200, event: AgentMessage({ text: "Looking into it: \"${text}\"" }) },
			{ delay_ms: 2000, event: ToolCall({ call_id, tool: "bash", input: "rg -n TODO src" }) },
			{ delay_ms: 3200, event: ToolResult({ call_id, output: "src/Main.roc:12: # TODO handle the empty case", failed: Bool.False }) },
			{ delay_ms: 4000, event: PermissionRequested(asked) },
			{ delay_ms: 4000, event: StatusChanged(AwaitingPermission) },
		]
	}

	## What follows a message that steers the turn the agent works on: the
	## message, and a word that it takes it into account, the rest of its
	## script going on.
	on_steer : Str, U64 -> List(Scheduled)
	on_steer = |text, _| [{ delay_ms: 0, event: UserMessage({ text: text }) }, { delay_ms: 600, event: AgentMessage({ text: "Noted, I'll take that into account: \"${text}\"" }) }]

	## What follows an answer to a pending permission request, with the
	## choice taken, if it offered its own.
	on_answer : Str, Bool, Try(Str, [Missing]), U64 -> List(Scheduled)
	on_answer = |request_id, allowed, choice, next| {
		answered = { delay_ms: 0, event: PermissionAnswered({ request_id, allowed, choice }) }
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
			Chat.pending_permissions(timeline).map(|request_id| { delay_ms: 0, event: PermissionAnswered({ request_id, allowed: Bool.False, choice: Err(Missing) }) }).concat([{ delay_ms: 0, event: AgentMessage({ text: "Stopped." }) }, { delay_ms: 0, event: StatusChanged(Idle) }])
		} else {
			[]
		}

	## What follows starting an agent with a first prompt: it runs at once,
	## as `on_message` goes on. Without a prompt it waits, idle.
	on_create : Str -> List(Scheduled)
	on_create = |prompt|
		if (prompt.is_empty()) [{ delay_ms: 0, event: StatusChanged(Idle) }] else Mock.on_message(prompt, 1).map(|scheduled| if (scheduled.event == StatusChanged(Running)) { ..scheduled, delay_ms: 0 } else scheduled)

	## `scheduled`, run from `at` (ms since the epoch), with each turn's end
	## before the status that ends it: a turn starts when the agent runs, or
	## at `started` if it was already working, and ends when it is idle,
	## finished or failed.
	ended : Try(I64, [Missing]), I64, List(Scheduled) -> List(Scheduled)
	ended = |started, at, scheduled| {
		walked = scheduled.fold(
			{ open: started, so_far: [] },
			|{ open, so_far }, item|
				match (item.event, open) {
					(StatusChanged(Running), Err(Missing)) => { open: Ok(at + item.delay_ms.to_i64_wrap()), so_far: so_far.append(item) }
					(StatusChanged(Idle), Ok(since)) | (StatusChanged(Finished), Ok(since)) | (StatusChanged(Failed(_)), Ok(since)) => {
						turn_ended = { delay_ms: item.delay_ms, event: TurnEnded({ started: Ok(Chat.timestamp(since)), ended: Chat.timestamp(at + item.delay_ms.to_i64_wrap()) }) }
						{ open: Err(Missing), so_far: so_far.append(turn_ended).append(item) }
					}
					_ => { open, so_far: so_far.append(item) }
				},
		)
		walked.so_far
	}

	## When the turn a timeline is working on started: its last run, unless
	## it went idle, finished or failed since.
	turn_started : List({ visible_at : I64, event : Chat.Event }) -> Try(I64, [Missing])
	turn_started = |timed|
		timed.fold(
			Err(Missing),
			|open, shown|
				match (shown.event, open) {
					(StatusChanged(Running), Err(Missing)) => Ok(shown.visible_at)
					(StatusChanged(Idle), _) | (StatusChanged(Finished), _) | (StatusChanged(Failed(_)), _) => Err(Missing)
					_ => open
				},
		)

	## The kinds of agent the mock provider starts, each with two models of
	## three thinking levels and three modes, as Claude's and Codex's in Paseo.
	agents : List(Chat.Agent)
	agents = {
		levels = |default| [{ id: "low", label: "Low", default: Bool.False }, { id: "medium", label: "Medium", default: Bool.False }, { id: "high", label: "High", default: Bool.False }].map(|level| { ..level, default: level.id == default })
		[
			{
				..Chat.agent_kind({ provider: "mock", agent: "claude" }),
				models: Ok([{ id: "claude-sonnet-4-5", label: "Sonnet 4.5", default: Bool.True, context_max: Ok(200_000), thinking: levels("medium") }, { id: "claude-opus-4-1", label: "Opus 4.1", default: Bool.False, context_max: Ok(200_000), thinking: levels("high") }]),
				modes: Ok([{ id: "default", label: "Always ask" }, { id: "acceptEdits", label: "Accept edits" }, { id: "plan", label: "Plan" }, { id: "bypassPermissions", label: "Bypass" }]),
				default_mode: Ok("default"),
			},
			{
				..Chat.agent_kind({ provider: "mock", agent: "codex" }),
				models: Ok([{ id: "gpt-5-codex", label: "GPT-5 Codex", default: Bool.True, context_max: Ok(272_000), thinking: levels("medium") }, { id: "gpt-5", label: "GPT-5", default: Bool.False, context_max: Ok(272_000), thinking: levels("medium") }]),
				modes: Ok([{ id: "read-only", label: "Read only" }, { id: "auto", label: "Auto" }, { id: "full-access", label: "Full access" }]),
				default_mode: Ok("auto"),
			},
		]
	}

	## A mock session's model, mode and thinking level, as the daemon keeps
	## them: each "" for its agent's default.
	Settings : { model : Str, mode : Str, thinking : Str }

	## The settings a `Configure` leaves a session of `agent` with, each it
	## names one its agent offers, or why not. A model whose levels lack the
	## thinking level kept goes back to its default one.
	configured : Str, Settings, { model : Try(Str, [Missing]), mode : Try(Str, [Missing]), thinking : Try(Str, [Missing]) } -> Try(Settings, Str)
	configured = |agent, settings, { model, mode, thinking }| {
		kind = Mock.agents.find_first(|offered| offered.agent == agent) ?? Chat.agent_kind({ provider: "mock", agent })
		models = kind.models ?? []
		next_model = model ?? settings.model
		levels = models.find_first(|offered| offered.id == Mock.or_default(next_model, Mock.default_model(models))).map_ok(|offered| offered.thinking) ?? []
		kept_thinking = if (levels.any(|level| level.id == settings.thinking)) settings.thinking else ""
		next = { model: next_model, mode: mode ?? settings.mode, thinking: thinking ?? kept_thinking }
		if !(next.model == "" or models.any(|offered| offered.id == next.model)) {
			Err("the mock's ${agent} runs no model ${next.model}")
		} else if !(next.mode == "" or (kind.modes ?? []).any(|offered| offered.id == next.mode)) {
			Err("the mock's ${agent} has no mode ${next.mode}")
		} else if !(next.thinking == "" or levels.any(|level| level.id == next.thinking)) {
			Err("the model has no thinking level ${next.thinking}")
		} else {
			Ok(next)
		}
	}

	default_model : List(Chat.Model) -> Str
	default_model = |models| models.find_first(|offered| offered.default).map_ok(|offered| offered.id) ?? ""

	or_default : Str, Str -> Str
	or_default = |chosen, default| if (chosen.is_empty()) default else chosen

	## A workspace made of a project: a checkout of its directory, on main, or
	## a worktree beside it on `branch`.
	made_workspace : Workspaces.Project, Str, [Checkout, Worktree], Str -> Workspaces.Workspace
	made_workspace = |project, id, made_kind, branch| {
		worktree = made_kind == Worktree
		directory = if (worktree) "${project.directory}-${branch}" else project.directory
		{ id, provider: "mock", project_id: project.id, name: if (worktree) branch else "${project.name} checkout", directory, kind: if (worktree) Worktree else Checkout, branch: Branch(if (worktree) branch else "main"), state: Idle, dirty: Bool.False, changes: Counted({ additions: 0, deletions: 0 }), pinned: Bool.False, labels: [], session_ids: [] }
	}

	## A session from its timeline's visible events, each with when it became
	## visible (ms since the epoch): its status, its agent's model, the
	## workspace of `listed_workspaces` it works in and its branch, when the turn it
	## is working on started, waiting for you or not, and when it last
	## changed.
	## Its model, mode and thinking level are those of `settings`, or else its
	## agent's defaults, what its last turn used grows with each message, and
	## its summary is `Mock.summary`'s.
	session : { id : Str, agent : Str, title : Str, settings : Settings }, List(Workspaces.Workspace), List({ visible_at : I64, event : Chat.Event }) -> Chat.Session
	session = |{ id, agent, title, settings }, listed_workspaces, timed| {
		current = Mock.status(timed.map(|shown| { sequence: 0, event: shown.event }))
		placed = listed_workspaces.find_first(|shown| shown.session_ids.contains(id))
		kind = Mock.agents.find_first(|offered| offered.agent == agent) ?? Chat.agent_kind({ provider: "mock", agent })
		model = Mock.or_default(settings.model, Mock.default_model(kind.models ?? []))
		running = (kind.models ?? []).find_first(|offered| offered.id == model)
		default_thinking = running.map_ok(|offered| offered.thinking.find_first(|level| level.default).map_ok(|level| level.id) ?? "") ?? ""
		told = |chosen| if (chosen.is_empty()) Err(Missing) else Ok(chosen)
		{
			..Chat.session({ id, provider: "mock", agent, title, status: current }),
			model: told(model),
			workspace: placed.map_ok(|shown| { id: Ok(shown.id), directory: shown.directory }).map_err(|_| Missing),
			branch: placed.map_ok(
				|shown| match shown.branch {
					Branch(name) => Ok(name)
					_ => Err(Missing)
				},
			) ?? Err(Missing),
			running_since: Mock.turn_started(timed).map_ok(Chat.timestamp),
			updated: timed.last().map_ok(|shown| Chat.timestamp(shown.visible_at)).map_err(|_| Missing),
			mode: told(Mock.or_default(settings.mode, kind.default_mode ?? "")),
			thinking: told(Mock.or_default(settings.thinking, default_thinking)),
			modes: kind.modes,
			usage: Mock.usage(timed.count_if(|shown| Mock.asks(shown.event)), running.map_ok(|offered| offered.context_max ?? 0) ?? 0),
			summary: Mock.summary(timed.map(|shown| shown.event), current),
		}
	}

	## A summary as a model might write after each turn, from the turns that
	## ended alone: the first message as the goal, the last reply as what was
	## done, and what the session waits on now. None before a turn ended.
	summary : List(Chat.Event), Chat.Status -> Try(Chat.Summary, [Missing])
	summary = |events, current| {
		last_end = events.keep_oks(
			|event| match event {
				TurnEnded({ ended: at, .. }) => Ok(at)
				_ => Err(Other)
			},
		).last()
		said = |pick| events.keep_oks(pick).last().map_ok(Mock.sentence) ?? ""
		asked = events.keep_oks(
			|event| match event {
				UserMessage({ text }) => Ok(text)
				_ => Err(Other)
			},
		)
		now =
			match current {
				Running => "Working on: ${asked.last().map_ok(Mock.sentence) ?? ""}"
				AwaitingPermission => "Waiting for you to answer a permission request."
				Failed(why) => "Stopped: ${why}"
				_ => "Waiting for your next message."
			}
		last_end.map_err(|_| Missing).map_ok(
			|at| {
				goal: asked.first().map_ok(Mock.sentence) ?? "",
				done: said(
					|event| match event {
						AgentMessage({ text }) => Ok(text)
						_ => Err(Other)
					},
				),
				now,
				at,
			},
		)
	}

	## A message's first sentence, as plain text: its first line that says
	## something, without Markdown's emphasis and code marks, up to its
	## first full stop.
	sentence : Str -> Str
	sentence = |text| {
		line : Str
		line = text.split_on("\n").map(|each| each.trim()).find_first(|each| !each.is_empty()) ?? ""
		plain = line.replace_each("**", "").replace_each("`", "").drop_prefix("#").trim().drop_prefix("- ")
		match plain.split_first(". ") {
			Ok({ before, .. }) => "${before}."
			Err(_) => plain
		}
	}

	## What a session's last turn used after `turns` messages, in a context
	## window of `context_max` tokens: none before the first.
	usage : U64, U64 -> Try(Chat.Usage, [Missing])
	usage = |turns, context_max|
		if turns == 0 {
			Err(Missing)
		} else {
			input = 9_000 * turns
			Ok({ context_used: Ok(U64.min(8_000 + 11_500 * turns, context_max)), context_max: Ok(context_max), input_tokens: Ok(input), cached_input_tokens: Ok(input - 9_000), output_tokens: Ok(1_200 * turns), cost_usd: Ok(0.06 * turns.to_dec()) })
		}

	asks : Chat.Event -> Bool
	asks = |event|
		match event {
			UserMessage(_) => Bool.True
			_ => Bool.False
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

	## The mock's workspaces as the daemon keeps their changes: each seeded
	## one as it was changed last, if it was, then those made since, without
	## those archived.
	with_changes : List({ id : Str, workspace : Try(Workspaces.Workspace, [Archived]) }) -> List(Workspaces.Workspace)
	with_changes = |stored| {
		seeded = Mock.workspaces.map(|shown| shown.id)
		Mock.workspaces
			.map(|shown| stored.find_first(|changed| changed.id == shown.id).map_ok(|changed| changed.workspace) ?? Ok(shown))
			.concat(stored.drop_if(|changed| seeded.contains(changed.id)).map(|changed| changed.workspace))
			.keep_oks(|shown| shown)
	}

	## A workspace's git. fix-auth's has the login fix uncommitted and one
	## commit ahead of main, and against main a long diff too
	## (`long_diff`); main is clean.
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
					AgainstBase => [login_fix, login_test].concat(long_diff)
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

defaults : Mock.Settings
defaults = { model: "", mode: "", thinking: "" }

login_fix : WorkspaceGit.FileDiff
login_fix = {
	file: { path: "src/Auth.roc", change: Modified, additions: 1, deletions: 1, body: Text },
	hunks: [WorkspaceGit.hunk({ old_start: 40, old_count: 3, new_start: 40, new_count: 3 }, [{ kind: Context, text: "login = |request|" }, { kind: Removed, text: "\tredirect_to = \"/login\"" }, { kind: Added, text: "\tredirect_to = request.came_from" }, { kind: Context, text: "\tSession.start(redirect_to)" }])],
}

## Six files of about 330 lines each, mostly added, which fix-auth's
## branch has against main: a diff long enough to try the Review surface
## on.
long_diff : List(WorkspaceGit.FileDiff)
long_diff = ["Parser", "Lexer", "Render", "Store", "Router", "Format"].map(
	|name| {
		lines = List.repeat(0, 330).map_with_index(
			|_, at| {
				text = "\t${name.with_ascii_lowercased()}_step_${at.to_str()} = |input| input.map(|value| value + ${at.to_str()})"
				if (at % 40 == 7) { kind: Removed, text } else if (at % 10 == 3) { kind: Context, text } else { kind: Added, text }
			},
		)
		added = lines.keep_if(|line| line.kind != Removed).len().to_u32_wrap()
		removed = lines.keep_if(|line| line.kind != Added).len().to_u32_wrap()
		{
			file: { path: "src/long/${name}.roc", change: Modified, additions: lines.keep_if(|line| line.kind == Added).len().to_u32_wrap(), deletions: lines.keep_if(|line| line.kind == Removed).len().to_u32_wrap(), body: Text },
			hunks: [WorkspaceGit.hunk({ old_start: 1, old_count: removed, new_start: 1, new_count: added }, lines)],
		}
	},
)

login_test : WorkspaceGit.FileDiff
login_test = {
	file: { path: "tests/Auth.roc", change: Added, additions: 3, deletions: 0, body: Text },
	hunks: [WorkspaceGit.hunk({ old_start: 0, old_count: 0, new_start: 1, new_count: 3 }, [{ kind: Added, text: "import Auth" }, { kind: Added, text: "" }, { kind: Added, text: "expect Auth.login({ came_from: \"/inbox\" }).redirect_to == \"/inbox\"" }])],
}

expect {
	running = Mock.session({ id: "flaky-ci", agent: "codex", title: "CI", settings: defaults }, Mock.workspaces, [{ visible_at: 0, event: StatusChanged(Idle) }, { visible_at: 1_767_258_000_000, event: StatusChanged(Running) }, { visible_at: 1_767_258_060_000, event: AgentMessage({ text: "x" }) }])
	running.status == Running
		and running.workspace == Ok({ id: Ok("main"), directory: "/mock/liton" })
		and running.branch == Ok("main")
		and running.running_since == Ok("2026-01-01T09:00:00.000Z")
		and running.updated == Ok("2026-01-01T09:01:00.000Z")
		and Mock.session({ id: "notes", agent: "claude", title: "", settings: defaults }, Mock.workspaces, [{ visible_at: 0, event: StatusChanged(Idle) }]).running_since == Err(Missing)
}

expect Mock.on_message("hi", 7).len() == 7
expect Mock.on_answer("p", Bool.False, Err(Missing), 3).len() == 3
expect {
	asked = |text| Mock.on_message(text, 7).keep_oks(
		|scheduled| match scheduled.event {
			PermissionRequested(question) => Ok(question)
			_ => Err(NotAsked)
		},
	)
	asked("Plan the fix").map(|question| (question.tool, question.body, question.choices.map_ok(|choices| choices.map(|choice| choice.id)))) == [("ExitPlanMode", Ok(Mock.plan), Ok(["reject", "implement", "implement_resume"]))]
		and asked("Fix it").map(|question| (question.body, question.choices)) == [(Err(Missing), Err(Missing))]
		and Mock.on_answer("permission-7", Bool.True, Ok("implement"), 9).first().map_ok(|scheduled| scheduled.event) == Ok(PermissionAnswered({ request_id: "permission-7", allowed: Bool.True, choice: Ok("implement") }))
}
expect Mock.status([{ sequence: 1, event: StatusChanged(Running) }, { sequence: 2, event: AgentMessage({ text: "x" }) }]) == Running
expect Mock.status([]) == Idle

expect {
	events = Mock.seeds.first().map_ok(|seed| Mock.ended(Err(Missing), 0, seed.events.map(|event| { delay_ms: 0, event })).map(|item| item.event)) ?? []
	Mock.summary(events, Idle) == Ok({ goal: "Logging in sends me back to /login.", done: "The redirect target is hard-coded to /login.", now: "Waiting for your next message.", at: "1970-01-01T00:00:00.000Z" })
		and Mock.summary([UserMessage({ text: "hi" })], Running) == Err(Missing)
}

expect {
	asked = [{ sequence: 1, event: StatusChanged(Running) }, { sequence: 2, event: PermissionRequested(Chat.permission({ request_id: "p1", tool: "edit", description: "" })) }, { sequence: 3, event: StatusChanged(AwaitingPermission) }]
	Mock.on_cancel(asked).map(|scheduled| scheduled.event) == [PermissionAnswered({ request_id: "p1", allowed: Bool.False, choice: Err(Missing) }), AgentMessage({ text: "Stopped." }), StatusChanged(Idle)]
		and Mock.on_cancel([{ sequence: 1, event: StatusChanged(Idle) }]) == []
}
expect Mock.git("main", Uncommitted, NoFile).diff == []
expect Mock.git("fix-auth", Commit("4f2a9c1e7b3d5a6f8e0c2b4d6a8f0e1c3b5d7a9f"), Selected("tests/Auth.roc")).diff.map(|shown| shown.hunks.len()) == [1]

# Each seed session works in one workspace, of a listed project.
expect Mock.seeds.all(|seed| Mock.workspaces.keep_if(|shown| shown.session_ids.contains(seed.id)).len() == 1)
expect Mock.workspaces.all(|shown| Mock.projects.any(|project| project.id == shown.project_id))

expect {
	at = |id, title, updated| { ..Chat.session({ id, provider: "mock", agent: "claude", title, status: Idle }), updated: Ok(updated) }
	sessions = [at("a", "Fix the login", "2026-01-01T09:00:00.000Z"), at("b", "Tidy the README", "2026-01-02T09:00:00.000Z"), at("c", "Log in faster", "2026-01-03T09:00:00.000Z")]
	first = Mock.history(sessions, { search: "", offset: 0, limit: 2 })
	found = Mock.history(sessions, { search: "LOG", offset: 1, limit: 2 })
	first.sessions.map(|shown| shown.id) == ["c", "b"] and first.more and found.sessions.map(|shown| shown.id) == ["a"] and !found.more
}

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

expect Mock.on_create("").map(|scheduled| scheduled.event) == [StatusChanged(Idle)] and Mock.on_create("Hi").take_first(2) == [{ delay_ms: 0, event: UserMessage({ text: "Hi" }) }, { delay_ms: 0, event: StatusChanged(Running) }]
expect {
	project = Mock.projects.first() ?? { id: "", provider: "", name: "", directory: "" }
	(Mock.made_workspace(project, "w1", Worktree, "docs").directory, Mock.made_workspace(project, "w2", Checkout, "docs").branch) == ("/mock/liton-docs", Branch("main"))
}

# A turn runs from the agent's run, through a wait for you, to its idle.
expect {
	timed = [{ visible_at: 1_000, event: StatusChanged(Running) }, { visible_at: 2_000, event: StatusChanged(AwaitingPermission) }]
	answered = Mock.ended(Mock.turn_started(timed), 1_767_258_000_000, Mock.on_answer("p", Bool.False, Err(Missing), 3))
	Mock.turn_started(timed) == Ok(1_000)
		and Mock.turn_started(timed.append({ visible_at: 3_000, event: StatusChanged(Idle) })) == Err(Missing)
		and Mock.session({ id: "notes", agent: "claude", title: "", settings: defaults }, Mock.workspaces, timed).running_since == Ok("1970-01-01T00:00:01.000Z")
		and answered.map(|scheduled| scheduled.event).take_last(2) == [TurnEnded({ started: Ok("1970-01-01T00:00:01.000Z"), ended: "2026-01-01T09:00:00.500Z" }), StatusChanged(Idle)]
}

expect {
	seeded = Mock.ended(Err(Missing), 0, [UserMessage({ text: "Hi" }), StatusChanged(Running), AgentMessage({ text: "Hello" }), StatusChanged(Idle)].map(|event| { delay_ms: 0, event }))
	seeded.map(|scheduled| scheduled.event).take_last(2) == [TurnEnded({ started: Ok("1970-01-01T00:00:00.000Z"), ended: "1970-01-01T00:00:00.000Z" }), StatusChanged(Idle)]
		and Mock.ended(Err(Missing), 0, Mock.on_create("")) == Mock.on_create("")
}

expect {
	made = { ..Mock.workspaces.first() ?? Mock.made_workspace({ id: "", provider: "", name: "", directory: "" }, "", Checkout, ""), id: "workspace-1", name: "docs" }
	renamed = { ..(Mock.workspaces.first() ?? made), name: "login", pinned: Bool.False }
	Mock.with_changes([]) == Mock.workspaces
		and Mock.with_changes([{ id: "main", workspace: Err(Archived) }, { id: "fix-auth", workspace: Ok(renamed) }, { id: "workspace-1", workspace: Ok(made) }]).map(|shown| (shown.id, shown.name)) == [("fix-auth", "login"), ("workspace-1", "docs")]
}

expect Mock.offering({ agents: Bool.False, rooms: Bool.True, tickets: Bool.True }).capabilities == [Capability.rooms_v1, Capability.tickets_v1]
expect Mock.offering({ agents: Bool.True, rooms: Bool.True, tickets: Bool.True }) == Mock.provider

# A session runs its agent's defaults until configured, and its usage grows with each message.
expect {
	asked = |count| List.repeat({ visible_at: 0, event: UserMessage({ text: "Hi" }) }, count)
	fresh = Mock.session({ id: "notes", agent: "claude", title: "", settings: defaults }, [], [])
	planned = Mock.session({ id: "notes", agent: "claude", title: "", settings: { model: "claude-opus-4-1", mode: "plan", thinking: "" } }, [], asked(2))
	(fresh.model, fresh.mode, fresh.thinking, fresh.usage) == (Ok("claude-sonnet-4-5"), Ok("default"), Ok("medium"), Err(Missing))
		and (planned.model, planned.mode, planned.thinking) == (Ok("claude-opus-4-1"), Ok("plan"), Ok("high"))
		and planned.usage.map_ok(|used| (used.context_used, used.context_max, used.cost_usd)) == Ok((Ok(31_000), Ok(200_000), Ok(0.12)))
}

expect {
	set = |settings, model, mode, thinking| Mock.configured("claude", settings, { model, mode, thinking })
	set(defaults, Ok("claude-opus-4-1"), Err(Missing), Ok("low")) == Ok({ model: "claude-opus-4-1", mode: "", thinking: "low" })
		and set(defaults, Err(Missing), Ok("plan"), Err(Missing)) == Ok({ ..defaults, mode: "plan" })
		and set(defaults, Ok("gpt-5"), Err(Missing), Err(Missing)) == Err("the mock's claude runs no model gpt-5")
		and set(defaults, Err(Missing), Ok("auto"), Err(Missing)) == Err("the mock's claude has no mode auto")
		and set(defaults, Err(Missing), Err(Missing), Ok("max")) == Err("the model has no thinking level max")
}

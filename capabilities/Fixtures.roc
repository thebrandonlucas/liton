## Values the golden JSON files in tests/ hold.
import Chat
import Hosts
import Limits
import Manifest
import Schedules
import Tickets
import Usage

Fixtures := [].{
	manifest : Manifest.Advertised
	manifest = {
		protocol: Manifest.protocol,
		providers: [{ id: "mock", name: "Mock", capabilities: [{ name: "chat", version: 1 }] }],
	}

	requests : List(Chat.Request)
	requests = [
		ListSessions,
		WatchSession({ session_id: "s1", after: 0 }),
		SendMessage({ session_id: "s1", text: "Fix the failing test", while_running: Err(Missing) }),
		SendMessage({ session_id: "s1", text: "Check the docs too", while_running: Ok(Steer) }),
		AnswerPermission({ session_id: "s1", request_id: "p1", allowed: Bool.True, choice: Err(Missing) }),
		AnswerPermission({ session_id: "s1", request_id: "p2", allowed: Bool.True, choice: Ok("implement") }),
		Rename({ session_id: "s1", title: "Fix the tests" }),
		Archive({ session_id: "s1" }),
		Configure({ session_id: "s1", model: Ok("claude-opus-4"), mode: Err(Missing), thinking: Ok("high") }),
		Create({ place: Workspace("main"), agent: "claude", model: Err(Missing), mode: Ok("plan"), thinking: Ok("low"), prompt: "" }),
		ListHistory({ search: "", cursor: Err(Missing), limit: 50 }),
		ListHistory({ search: "login", cursor: Ok("c2"), limit: 50 }),
		Unarchive({ session_id: "s1" }),
	]

	responses : List(Chat.Response)
	responses = [
		Sessions([Chat.session({ id: "s1", provider: "mock", agent: "claude", title: "Fix tests", status: AwaitingPermission }), Fixtures.configured]),
		Accepted,
		Rejected("no session s2"),
		History({ sessions: [{ ..Chat.session({ id: "s3", provider: "mock", agent: "claude", title: "Fix the login", status: Finished }), archived: Ok("2026-01-01T09:00:00.000Z") }], next: Ok("c2") }),
		History({ sessions: [], next: Err(Missing) }),
	]

	## A session telling its mode, thinking level, modes, usage and summary.
	configured : Chat.Session
	configured = {
		..Chat.session({ id: "s2", provider: "mock", agent: "claude", title: "Plan the docs", status: Idle }),
		mode: Ok("plan"),
		thinking: Ok("high"),
		modes: Ok([{ id: "default", label: "Default" }, { id: "plan", label: "Plan" }]),
		usage: Ok({ context_used: Ok(41_000), context_max: Ok(200_000), input_tokens: Ok(52_000), cached_input_tokens: Ok(40_000), output_tokens: Ok(3_100), cost_usd: Ok(0.42) }),
		summary: Ok({ goal: "Document the planner.", done: "Outlined the guide.", now: "Waiting for your review.", at: "2026-01-01T09:00:09.000Z" }),
	}

	timeline : List(Chat.Entry)
	timeline = [
		{ sequence: 1, event: UserMessage({ text: "Fix the failing test" }) },
		{ sequence: 2, event: StatusChanged(Running) },
		{ sequence: 3, event: ToolCall({ call_id: "c1", tool: "bash", input: "zig build test" }) },
		{ sequence: 4, event: ToolResult({ call_id: "c1", output: "1 failed", failed: Bool.True }) },
		{ sequence: 5, event: PermissionRequested(Chat.permission({ request_id: "p1", tool: "edit", description: "src/Main.roc" })) },
		{ sequence: 6, event: PermissionAnswered({ request_id: "p1", allowed: Bool.True, choice: Err(Missing) }) },
		{ sequence: 7, event: AgentMessage({ text: "Fixed: the test expected UTC." }) },
		{ sequence: 8, event: StatusChanged(Failed("context limit")) },
		{ sequence: 9, event: PermissionRequested({ ..Chat.permission({ request_id: "p2", tool: "ExitPlanMode", description: "Plan" }), body: Ok("1. Sort the entries"), choices: Ok([{ id: "reject", label: "Reject", allows: Bool.False, style: Danger }, { id: "implement", label: "Implement", allows: Bool.True, style: Primary }]) }) },
		{ sequence: 10, event: PermissionAnswered({ request_id: "p2", allowed: Bool.True, choice: Ok("implement") }) },
		{ sequence: 11, event: TurnEnded({ started: Ok("2026-01-01T09:00:00.000Z"), ended: "2026-01-01T09:00:09.000Z" }) },
		{ sequence: 12, event: TurnEnded({ started: Err(Missing), ended: "2026-01-01T09:01:00.000Z" }) },
	]

	## A GitHub-like ticket with a comment, its source, a call of each
	## request and each answer.
	ticket : Tickets.Ticket
	ticket = {
		summary: {
			id: "liton#3",
			provider: "github",
			source: "thebrandonlucas/liton",
			key: "#3",
			title: "Track issues and tickets",
			url: "https://github.com/thebrandonlucas/liton/issues/3",
			status: { id: "open", name: "Open", kind: Open },
			assignees: [{ id: "ada", name: "Ada" }],
			labels: ["enhancement"],
			waiting_on: [],
			branch: Err(Missing),
			updated: "2026-01-01T09:00:00.000Z",
		},
		body: "List and filter tickets.",
		comments: [{ id: "c1", author: { id: "bo", name: "Bo" }, body: "Linear next?", created: "2026-01-01T09:00:00.000Z" }],
	}

	ticket_requests : List(Tickets.Request)
	ticket_requests = [
		ListTickets({ ..Tickets.open, assignee: Me, text: "login" }),
		GetTicket({ ticket_id: "liton#3" }),
		Comment({ ticket_id: "liton#3", body: "On it." }),
		SetStatus({ ticket_id: "liton#3", status_id: "closed" }),
		SetAssignees({ ticket_id: "liton#3", person_ids: ["ada"] }),
		Link({ session_id: "fix-auth", ticket_id: "liton#3" }),
		Unlink({ session_id: "fix-auth" }),
	]

	ticket_responses : List(Tickets.Response)
	ticket_responses = [
		Listed({ sources: [{ id: "thebrandonlucas/liton", provider: "github", name: "thebrandonlucas/liton", url: "https://github.com/thebrandonlucas/liton", me: Ok({ id: "ada", name: "Ada" }), people: [{ id: "ada", name: "Ada" }], statuses: [{ id: "open", name: "Open", kind: Open }, { id: "closed", name: "Closed", kind: Done }], repo: Err(Missing) }], tickets: [Fixtures.ticket.summary] }),
		Ticket(Fixtures.ticket),
		Accepted,
	]

	## A heartbeat and a schedule of new sessions, a call of each request
	## and each answer.
	schedule_requests : List(Schedules.Request)
	schedule_requests = [
		ListSchedules,
		Inspect({ schedule_id: "h1" }),
		Create(Fixtures.heartbeat_draft),
		Update({ schedule_id: "h1", draft: { ..Fixtures.heartbeat_draft, cadence: Cron({ expression: "0 9 * * 1-5", timezone: Ok("Europe/Berlin") }) } }),
		Pause({ schedule_id: "h1" }),
		Resume({ schedule_id: "h1" }),
		RunOnce({ schedule_id: "h1" }),
		Delete({ schedule_id: "h1" }),
	]

	heartbeat_draft : Schedules.Draft
	heartbeat_draft = { name: "Check CI", prompt: "Is CI green?", cadence: Every(1_800_000), target: Session("fix-auth"), max_runs: Err(Missing), expires: Err(Missing) }

	schedule_responses : List(Schedules.Response)
	schedule_responses = {
		nightly = { ..Schedules.drafted({ id: "n1", provider: "mock" }, { name: "", prompt: "Update the deps", cadence: Cron({ expression: "0 3 * * *", timezone: Err(Missing) }), target: NewSession({ place: Workspace("main"), agent: "claude", model: Ok("opus"), mode: Err(Missing), thinking: Err(Missing), isolation: Worktree, archive_on_finish: Bool.True }), max_runs: Ok(10), expires: Ok("2026-02-01T00:00:00.000Z") }), next_run: Ok("2026-01-02T03:00:00.000Z") }
		[
			Schedules([Schedules.drafted({ id: "h1", provider: "mock" }, Fixtures.heartbeat_draft), nightly]),
			Inspected({ schedule: { ..nightly, status: Paused, last_run: Ok("2026-01-01T03:00:00.000Z") }, runs: [{ id: "r1", scheduled_for: "2026-01-01T03:00:00.000Z", started: "2026-01-01T03:00:01.000Z", ended: Ok("2026-01-01T03:04:00.000Z"), status: Succeeded, session_id: Ok("claude-1"), output: Ok("Updated 3 deps."), error: Err(Missing) }, { id: "r2", scheduled_for: "2026-01-01T04:00:00.000Z", started: "2026-01-01T04:00:00.000Z", ended: Err(Missing), status: Running, session_id: Err(Missing), output: Err(Missing), error: Err(Missing) }] }),
			Created({ schedule_id: "h2" }),
			Accepted,
			Rejected("no schedule h9"),
		]
	}

	## A Paseo host the environment set and a liton host a client added,
	## a call of each request and each answer: no password in any.
	host_requests : List(Hosts.Request)
	host_requests = [
		ListHosts,
		AddHost({ name: "team", kind: Liton, target: "https://liton.example", label: "Team", password: "t0ken" }),
		UpdateHost({ name: "team", target: Err(Missing), label: Ok("The team"), password: Err(Missing) }),
		SetEnabled({ name: "paseo", enabled: Bool.False }),
		RemoveHost({ name: "team" }),
	]

	host_responses : List(Hosts.Response)
	host_responses = [
		Hosts([
			{ name: "paseo", kind: Paseo, target: "127.0.0.1:6767", label: "", enabled: Bool.True, status: Online, version: Ok("0.15.3"), last_online: Ok("2026-01-01T09:00:00.000Z"), origin: Environment },
			{ name: "team", kind: Liton, target: "https://liton.example", label: "Team", enabled: Bool.True, status: Error("the token was refused"), version: Err(Missing), last_online: Err(Missing), origin: Added },
			{ name: "box", kind: Paseo, target: "box.local:6767", label: "", enabled: Bool.False, status: Disabled, version: Err(Missing), last_online: Err(Missing), origin: Added },
		]),
		Accepted,
		Rejected("there is a host called team already"),
	]

	## A Claude account's report with its 5-hour and weekly windows and a
	## balance, and one whose login expired, as usage.v1's `reports` holds
	## them.
	usage_reports : List(Usage.Report)
	usage_reports = [
		{
			provider: "paseo",
			source: "claude",
			account: "me@example.com",
			plan: "Max",
			status: Available,
			windows: [
				{ id: "five_hour", label: "Session", short: "5h", used_pct: Ok(12.5), resets_at: Ok("2026-01-01T14:00:00.000Z") },
				{ id: "weekly", label: "Weekly", short: "wk", used_pct: Ok(41), resets_at: Ok("2026-01-05T09:00:00.000Z") },
			],
			balances: [{ id: "extra_usage", label: "Extra usage", used: Ok(4.2), remaining: Err(Missing), limit: Ok(50), unit: "usd" }],
		},
		{ provider: "paseo", source: "codex", account: "", plan: "", status: Unavailable("the login expired: run codex login"), windows: [], balances: [] },
	]

	## Each request of limits.v1, and its `status`: a session past the
	## default limit, one near its own, and an account under the weekly one.
	limit_requests : List(Limits.Request)
	limit_requests = [
		SetLimit({ scope: Session("fix-auth"), percent: 50 }),
		SetLimit({ scope: Week, percent: 90 }),
		SetLimit({ scope: Default, percent: 80 }),
		ClearLimit({ scope: Session("fix-auth") }),
	]

	limit_status : Limits.Status
	limit_status = {
		limits: [{ scope: Default, percent: 80 }, { scope: Session("notes"), percent: 40 }, { scope: Week, percent: 90 }],
		sessions: [{ session_id: "fix-auth", used_pct: 85, limit_pct: Ok(80), state: Over }, { session_id: "notes", used_pct: 37, limit_pct: Ok(40), state: Near }],
		weeks: [{ provider: "paseo", source: "claude", account: "me@example.com", used_pct: 41, limit_pct: Ok(90), state: Ok, resets_at: Ok("2026-01-05T09:00:00.000Z") }],
	}
}

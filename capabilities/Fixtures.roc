## Values the golden JSON files in tests/ hold.
import Chat
import Manifest
import Tickets

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
		SendMessage({ session_id: "s1", text: "Fix the failing test" }),
		AnswerPermission({ session_id: "s1", request_id: "p1", allowed: Bool.True, choice: Err(Missing) }),
		AnswerPermission({ session_id: "s1", request_id: "p2", allowed: Bool.True, choice: Ok("implement") }),
		Rename({ session_id: "s1", title: "Fix the tests" }),
		Archive({ session_id: "s1" }),
		Configure({ session_id: "s1", model: Ok("claude-opus-4"), mode: Err(Missing), thinking: Ok("high") }),
		Create({ place: Workspace("main"), agent: "claude", model: Err(Missing), mode: Ok("plan"), thinking: Ok("low"), prompt: "" }),
	]

	responses : List(Chat.Response)
	responses = [
		Sessions([Chat.session({ id: "s1", provider: "mock", agent: "claude", title: "Fix tests", status: AwaitingPermission }), Fixtures.configured]),
		Accepted,
		Rejected("no session s2"),
	]

	## A session telling its mode, thinking level, modes and usage.
	configured : Chat.Session
	configured = {
		..Chat.session({ id: "s2", provider: "mock", agent: "claude", title: "Plan the docs", status: Idle }),
		mode: Ok("plan"),
		thinking: Ok("high"),
		modes: Ok([{ id: "default", label: "Default" }, { id: "plan", label: "Plan" }]),
		usage: Ok({ context_used: Ok(41_000), context_max: Ok(200_000), input_tokens: Ok(52_000), cached_input_tokens: Ok(40_000), output_tokens: Ok(3_100), cost_usd: Ok(0.42) }),
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
		Listed({ sources: [{ id: "thebrandonlucas/liton", provider: "github", name: "thebrandonlucas/liton", url: "https://github.com/thebrandonlucas/liton", me: Ok({ id: "ada", name: "Ada" }), people: [{ id: "ada", name: "Ada" }], statuses: [{ id: "open", name: "Open", kind: Open }, { id: "closed", name: "Closed", kind: Done }] }], tickets: [Fixtures.ticket.summary] }),
		Ticket(Fixtures.ticket),
		Accepted,
	]
}

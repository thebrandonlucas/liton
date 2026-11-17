## Values the golden JSON files in tests/ hold.
import Chat
import Manifest

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
	]

	responses : List(Chat.Response)
	responses = [
		Sessions([Chat.session({ id: "s1", provider: "mock", agent: "claude", title: "Fix tests", status: AwaitingPermission })]),
		Accepted,
		Rejected("no session s2"),
	]

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
}

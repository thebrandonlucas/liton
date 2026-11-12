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
		AnswerPermission({ session_id: "s1", request_id: "p1", allowed: Bool.True }),
	]

	responses : List(Chat.Response)
	responses = [
		Sessions([{ id: "s1", provider: "mock", agent: "claude", title: "Fix tests", status: AwaitingPermission }]),
		Accepted,
		Rejected("no session s2"),
	]

	timeline : List(Chat.Entry)
	timeline = [
		{ sequence: 1, event: UserMessage({ text: "Fix the failing test" }) },
		{ sequence: 2, event: StatusChanged(Running) },
		{ sequence: 3, event: ToolCall({ call_id: "c1", tool: "bash", input: "zig build test" }) },
		{ sequence: 4, event: ToolResult({ call_id: "c1", output: "1 failed", failed: Bool.True }) },
		{ sequence: 5, event: PermissionRequested({ request_id: "p1", tool: "edit", description: "src/Main.roc" }) },
		{ sequence: 6, event: PermissionAnswered({ request_id: "p1", allowed: Bool.True }) },
		{ sequence: 7, event: AgentMessage({ text: "Fixed: the test expected UTC." }) },
		{ sequence: 8, event: StatusChanged(Failed("context limit")) },
	]
}

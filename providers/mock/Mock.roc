import cap.Capability
import cap.Chat
import cap.Manifest

Mock := [].{
	provider : Manifest.Provider
	provider = { id: "mock", name: "Mock agents", capabilities: [Capability.chat_v1] }

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
}

expect Mock.on_message("hi", 7).len() == 7
expect Mock.on_answer("p", Bool.False, 3).len() == 3
expect Mock.status([{ sequence: 1, event: StatusChanged(Running) }, { sequence: 2, event: AgentMessage({ text: "x" }) }]) == Running
expect Mock.status([]) == Idle

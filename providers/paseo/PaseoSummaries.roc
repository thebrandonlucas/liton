import cap.Chat
import Paseo

## Goal / Done / Now summaries of Paseo's sessions, which a hidden agent on a
## small model writes after a turn ends: which sessions are due one, what the
## agent is asked, and what it answers. Paseo runs the agent in the
## background (`background`, from 0.15), archives it once it finished
## (`autoArchive`) and holds it to `schema` (`outputSchema`), so liton needs
## no keys of its own.
PaseoSummaries := [].{

	## What the daemon knows of a Paseo session when it picks those due a
	## summary: its status, the sequence and the time (ms since the epoch)
	## of the last `TurnEnded` in its timeline (0 and 0 for none), the
	## sequence its summary covers, and whether an agent is writing one.
	Candidate : { session_id : Str, status : Chat.Status, ended_through : U64, ended_ms : I64, summarized_through : U64, writing : Bool }

	## How long after a turn ended its summary is asked for, so that a turn
	## followed at once by another costs one summary.
	debounce_ms : I64
	debounce_ms = 30_000

	## How many summaries are written at once at most.
	concurrent : U64
	concurrent = 2

	## How long a summary may take before it is given up.
	given_up_ms : I64
	given_up_ms = 300_000

	## The sessions due a summary, the turn that ended last first, as many as
	## `concurrent` leaves room for beside those being written: a turn ended
	## after the one the summary covers, `debounce_ms` ago or more, and no
	## other has started since.
	due : List(Candidate), I64 -> List(Str)
	due = |candidates, now| {
		writing = candidates.count_if(|candidate| candidate.writing)
		room = if (writing >= PaseoSummaries.concurrent) 0 else PaseoSummaries.concurrent - writing
		candidates
			.keep_if(
				|candidate|
					!candidate.writing
						and candidate.ended_through > candidate.summarized_through
						and now - candidate.ended_ms >= PaseoSummaries.debounce_ms
						and candidate.status != Running
						and candidate.status != AwaitingPermission,
			)
			.sort_with(|left, right| if (left.ended_ms > right.ended_ms) Before else if (left.ended_ms < right.ended_ms) After else Same)
			.take_first(room)
			.map(|candidate| candidate.session_id)
	}

	## The model a session of `agent` is summarized with: the one
	## `configured` names (LITON_SUMMARY_MODEL), as `model` or as
	## `agent:model` for another kind of agent, or else the first of the
	## agent's models whose id or label names it small, such as Claude's
	## Haiku or a `mini`. None when the agent offers no small model, so a
	## summary never runs on a large one unasked.
	model : List(Chat.Agent), Str, Str -> Try({ agent : Str, model : Str }, [Missing])
	model = |kinds, agent, configured| {
		if !configured.is_empty() {
			return match configured.split_first(":") {
				Ok({ before, after }) => Ok({ agent: before, model: after })
				Err(_) => Ok({ agent, model: configured })
			}
		}
		small = ["haiku", "mini", "nano", "flash", "lite", "small"]
		named_small = |offered| small.any(|word| offered.id.with_ascii_lowercased().contains(word) or offered.label.with_ascii_lowercased().contains(word))
		models = kinds.find_first(|kind| kind.agent == agent).map_ok(|kind| kind.models ?? []) ?? []
		models.find_first(named_small).map_ok(|offered| { agent, model: offered.id }).map_err(|_| Missing)
	}

	## The prompt that asks for a summary: the summary so far, if any, and
	## what happened since, as `digest` tells it.
	prompt : Try(Chat.Summary, [Missing]), List(Chat.Entry) -> Str
	prompt = |previous, entries| {
		before =
			match previous {
				Ok({ goal, done, now, .. }) => "The summary so far:\nGoal: ${goal}\nDone: ${done}\nNow: ${now}\n\n"
				Err(Missing) => ""
			}
		instructions =
			\\You summarize a coding agent's session for a list of sessions. Use no tools.
			\\Answer with JSON alone: {"goal": "...", "done": "...", "now": "..."}, one plain sentence of at most 25 words each:
			\\goal, what the session is for as a whole; done, what the agent has achieved so far; now, what it is doing or waits on.
		"${instructions}\n\n${before}What happened since:\n${PaseoSummaries.digest(entries)}"
	}

	## What `entries` hold, a line each, its last 6000 bytes at most: the
	## messages, each tool call's first line and whether it failed, and the
	## permission requests.
	digest : List(Chat.Entry) -> Str
	digest = |entries| {
		first_line = |text, limit| {
			line = text.split_on("\n").first() ?? ""
			if (line.count_utf8_bytes() > limit) "${Str.from_utf8(line.to_utf8().take_first(limit)) ?? ""}…" else line
		}
		lines = entries.keep_oks(
			|entry| match entry.event {
				UserMessage({ text }) => Ok("User: ${first_line(text, 600)}")
				AgentMessage({ text }) => Ok("Agent: ${first_line(text, 600)}")
				ToolCall({ tool, input, .. }) => Ok("Tool ${tool}: ${first_line(input, 160)}")
				ToolResult({ failed: Bool.True, output, .. }) => Ok("  failed: ${first_line(output, 160)}")
				PermissionRequested({ tool, description, .. }) => Ok("Asked permission: ${tool} ${first_line(description, 160)}")
				_ => Err(Other)
			},
		)
		text = Str.join_with(lines, "\n")
		bytes = text.to_utf8()
		if (bytes.len() > 6000) Str.from_utf8(bytes.drop_first(bytes.len() - 6000)) ?? "" else text
	}

	## Starts the summary's agent as `agent_id` (see `Paseo.uuid`), `asked`
	## for one (see `prompt`), in the
	## session's directory and workspace: a background agent, which no list
	## shows, that Paseo archives once it finished, labelled
	## `liton_summary` with the session it summarizes.
	create_request : { agent_id : Str, session_id : Str, chosen : { agent : Str, model : Str }, cwd : Str, workspace_id : Try(Str, [Missing]), asked : Str, request_id : Str } -> Str
	create_request = |{ agent_id, session_id, chosen, cwd, workspace_id, asked, request_id }|
		Json.to_str({
			type: "session",
			message: {
				type: "agent.create.request",
				requestId: request_id,
				agentId: agent_id,
				idempotencyKey: agent_id,
				workspaceId: workspace_id,
				initialPrompt: asked,
				background: Bool.True,
				autoArchive: Bool.True,
				outputSchema: PaseoSummaries.schema,
				labels: { liton_summary: session_id },
				config: { provider: chosen.agent, cwd, model: chosen.model, title: "liton summary" },
			},
		})

	## The JSON schema of a summary's answer.
	schema : { type : Str, properties : { goal : { type : Str }, done : { type : Str }, now : { type : Str } }, required : List(Str), additionalProperties : Bool }
	schema = { type: "object", properties: { goal: { type: "string" }, done: { type: "string" }, now: { type: "string" } }, required: ["goal", "done", "now"], additionalProperties: Bool.False }

	## Asks whether the summary's agent finished, without waiting.
	finished_request : Str, Str -> Str
	finished_request = |agent_id, request_id| Json.to_str({ type: "session", message: { type: "wait_for_finish_request", requestId: request_id, agentId: agent_id, timeoutMs: 1.U32 } })

	## What a `wait_for_finish_response` answering `request_id` says of the
	## summary: still being written, written, or why there is none.
	finished : Str, Str -> Try([Writing, Written({ goal : Str, done : Str, now : Str }), Failed(Str)], [OtherMessage, InvalidJson(Str), MissingRequiredField(Str)])
	finished = |text, request_id| {
		answered : Try({ message : { payload : { status : Str, last_message : Try(Str, [Null]), error : Try(Str, [Null]) } } }, _)
		answered = Json.parser_camel()(Paseo.answer_to(text, "wait_for_finish_response", request_id)?)
		payload = answered?.message.payload
		match (payload.status, payload.last_message) {
			("timeout", _) => Ok(Writing)
			("idle", Ok(message)) => Ok(PaseoSummaries.written(message).map_ok(|summary| Written(summary)) ?? Failed("the answer is no summary: ${message}"))
			(status, _) => Ok(Failed(payload.error ?? "the agent ended ${status}"))
		}
	}

	## The summary in an agent's answer: the JSON object in it, which a model
	## may have put in a code block.
	written : Str -> Try({ goal : Str, done : Str, now : Str }, [NoSummary])
	written = |message| {
		after_brace = message.split_first("{").map_ok(|{ after, .. }| after) ?? ""
		object = after_brace.split_last("}").map_ok(|{ before, .. }| "{${before}}") ?? ""
		parsed : Try({ goal : Str, done : Str, now : Str }, _)
		parsed = Json.parse(object)
		parsed.map_err(|_| NoSummary)
	}
}

expect {
	candidate = |session_id, ended_ms| { session_id, status: Idle, ended_through: 5, ended_ms, summarized_through: 0, writing: Bool.False }
	now = 100_000
	PaseoSummaries.due([candidate("old", 10_000), candidate("new", 60_000), candidate("recent", 90_000), { ..candidate("covered", 0), summarized_through: 5 }, { ..candidate("busy", 0), status: Running }], now) == ["new", "old"]
		and PaseoSummaries.due([{ ..candidate("a", 0), writing: Bool.True }, { ..candidate("b", 0), writing: Bool.True }, candidate("c", 0)], now) == []
}

expect {
	kinds = [{ ..Chat.agent_kind({ provider: "paseo", agent: "claude" }), models: Ok([{ id: "opus", label: "Opus 4.5", default: Bool.True, context_max: Err(Missing), thinking: [] }, { id: "claude-haiku-4-5", label: "Haiku 4.5", default: Bool.False, context_max: Err(Missing), thinking: [] }]) }]
	PaseoSummaries.model(kinds, "claude", "") == Ok({ agent: "claude", model: "claude-haiku-4-5" })
		and PaseoSummaries.model(kinds, "codex", "") == Err(Missing)
		and PaseoSummaries.model(kinds, "codex", "claude:haiku") == Ok({ agent: "claude", model: "haiku" })
		and PaseoSummaries.model(kinds, "codex", "gpt-5-mini") == Ok({ agent: "codex", model: "gpt-5-mini" })
}

expect PaseoSummaries.written("```json\n{\"goal\":\"g\",\"done\":\"d\",\"now\":\"n\"}\n```") == Ok({ goal: "g", done: "d", now: "n" })

expect {
	answer = |payload| "{\"type\":\"session\",\"message\":{\"type\":\"wait_for_finish_response\",\"payload\":{\"requestId\":\"r\",${payload}}}}"
	PaseoSummaries.finished(answer("\"status\":\"timeout\",\"final\":null,\"error\":null,\"lastMessage\":null"), "r") == Ok(Writing)
		and PaseoSummaries.finished(answer("\"status\":\"idle\",\"final\":null,\"error\":null,\"lastMessage\":\"{\\\"goal\\\":\\\"g\\\",\\\"done\\\":\\\"d\\\",\\\"now\\\":\\\"n\\\"}\""), "r") == Ok(Written({ goal: "g", done: "d", now: "n" }))
		and PaseoSummaries.finished(answer("\"status\":\"permission\",\"final\":null,\"error\":null,\"lastMessage\":null"), "r") == Ok(Failed("the agent ended permission"))
}

expect PaseoSummaries.digest([{ sequence: 1, event: UserMessage({ text: "Fix it\nplease" }) }, { sequence: 2, event: ToolCall({ call_id: "c", tool: "bash", input: "zig build" }) }, { sequence: 3, event: ToolResult({ call_id: "c", output: "1 failed", failed: Bool.True }) }]) == "User: Fix it\nTool bash: zig build\n  failed: 1 failed"

expect PaseoSummaries.prompt(Ok({ goal: "g", done: "d", now: "n", at: "" }), [{ sequence: 1, event: AgentMessage({ text: "Done." }) }]).ends_with("Use no tools.\nAnswer with JSON alone: {\"goal\": \"...\", \"done\": \"...\", \"now\": \"...\"}, one plain sentence of at most 25 words each:\ngoal, what the session is for as a whole; done, what the agent has achieved so far; now, what it is doing or waits on.\n\nThe summary so far:\nGoal: g\nDone: d\nNow: n\n\nWhat happened since:\nAgent: Done.")

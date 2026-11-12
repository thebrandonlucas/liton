import cap.Capability
import cap.Chat
import cap.Manifest

## Paseo's agents as chat.v1 sessions. Agents are listed and prompted, and
## permissions answered, over Paseo's MCP endpoint; timelines are fetched over
## its WebSocket. Paseo's own JSON is camelCase, which `Json.parser_camel`
## reads into the snake_case fields below; liton reads only these fields.
Paseo := [].{
	provider : Manifest.Provider
	provider = { id: "paseo", name: "Paseo", capabilities: [Capability.chat_v1] }

	## How many timeline entries a fetch asks for: a session's first fetch
	## takes its last ones, later fetches follow on while a page `has_newer`.
	page_limit : U64
	page_limit = 200

	## Declared before `Loose`, whose parser uses it: declared after, its
	## derived parser_for "does not exist" (Roc nightly-2026-11-07; repro in
	## roc-issues BUG-026, not filed yet).
	LooseObject := { message : Try(Str, [Missing]), content : Try(Str, [Missing]) }.{
		parser_for : _
	}

	## A JSON value Paseo leaves open, such as a tool's output or error: liton
	## shows a string, or an object's `message` or `content` string.
	Loose := [Text(Str), NotText].{
		parser_for = |encoding| {
			parse_str = Str.parser_for(encoding)
			parse_object = LooseObject.parser_for(encoding)
			|state|
				match (parse_str(state), parse_object(state)) {
					(Ok(parsed), _) => Ok({ value: Text(parsed.value), rest: parsed.rest })
					(_, Ok(parsed)) => Ok({ value: Text(parsed.value.message ?? (parsed.value.content ?? "")), rest: parsed.rest })
					_ => Ok({ value: NotText, rest: encoding.skip_record_field(state)? })
				}
		}
	}

	Agent : { id : Str, short_id : Str, title : Try(Str, [Null]), provider : Str, status : Str, archived_at : Try(Try(Str, [Null]), [Missing]), attention_reason : Try(Try(Str, [Null]), [Missing]) }

	Permission : { id : Str, name : Str, title : Try(Str, [Missing]), description : Try(Str, [Missing]) }

	## An agent's state, from `get_agent_status` or a timeline page's `agent`.
	## `status` is initializing, idle, running, error or closed.
	Snapshot : { status : Str, pending_permissions : List(Permission), last_error : Try(Str, [Missing]) }

	Detail : {
		type : Str,
		command : Try(Str, [Missing]),
		output : Try(Loose, [Missing]),
		file_path : Try(Str, [Missing]),
		unified_diff : Try(Str, [Missing]),
		query : Try(Str, [Missing]),
		url : Try(Str, [Missing]),
		description : Try(Str, [Missing]),
		label : Try(Str, [Missing]),
		text : Try(Str, [Missing]),
		input : Try(Loose, [Missing]),
	}

	## One of Paseo's timeline items, by `type`: user_message, assistant_message,
	## tool_call, error and others liton skips (reasoning, todo, notification...).
	Item : {
		type : Str,
		text : Try(Str, [Missing]),
		message : Try(Str, [Missing]),
		call_id : Try(Str, [Missing]),
		name : Try(Str, [Missing]),
		status : Try(Str, [Missing]),
		detail : Try(Detail, [Missing]),
		error : Try(Loose, [Missing]),
	}

	## Paseo merges an assistant message's chunks, and a tool call's updates,
	## into one entry that keeps its `seq_start`.
	Entry : { seq_start : U64, item : Item }

	## A `fetch_agent_timeline_response`. `reset` means Paseo ignored a cursor
	## from another epoch (Paseo restarted or rebuilt the timeline) or past
	## what it keeps, and sent the tail instead.
	Page : {
		request_id : Str,
		epoch : Str,
		reset : Bool,
		end_cursor : Try({ seq : U64 }, [Null]),
		has_newer : Bool,
		entries : List(Entry),
		agent : Try(Snapshot, [Null]),
		error : Try(Str, [Null]),
	}

	## What a session has emitted, which the daemon keeps between fetches (it
	## encodes to JSON). The next fetch starts after `cursor` in `epoch` ("" until
	## the first). `emitted_through` is the `seq_start` of the last entry turned
	## into events, `open_calls` the tool calls emitted without a result yet,
	## `permissions` the requests emitted without an answer.
	State : { epoch : Str, cursor : U64, emitted_through : U64, open_calls : List(Str), permissions : List(Str), status : Chat.Status }

	initial : State
	initial = { epoch: "", cursor: 0, emitted_through: 0, open_calls: [], permissions: [], status: Idle }

	mcp_path : Str
	mcp_path = "/mcp/agents"

	## Paseo refuses (406) an MCP client that doesn't accept server-sent events.
	mcp_headers : Str -> List({ name : Str, value : Str })
	mcp_headers = |password| [
		{ name: "Content-Type", value: "application/json" },
		{ name: "Accept", value: "application/json, text/event-stream" },
		{ name: "Authorization", value: "Bearer ${password}" },
	]

	## As many as Paseo lists at once.
	list_agents : Str
	list_agents = tool_call("list_agents", Json.to_str({ limit: 200.U16 }))

	agent_status : Str -> Str
	agent_status = |agent_id| tool_call("get_agent_status", Json.to_str({ agentId: agent_id }))

	## In the background: otherwise Paseo answers only once the agent is done.
	send_prompt : Str, Str -> Str
	send_prompt = |agent_id, prompt| tool_call("send_agent_prompt", Json.to_str({ agentId: agent_id, prompt: prompt, background: Bool.True }))

	answer_permission : Str, Str, Bool -> Str
	answer_permission = |agent_id, request_id, allowed|
		tool_call("respond_to_permission", Json.to_str({ agentId: agent_id, requestId: request_id, response: { behavior: if (allowed) "allow" else "deny" } }))

	## The agents `list_agents` answered, without archived ones. An agent whose
	## attention Paseo wants for a permission awaits it, and an idle one whose
	## attention it wants because it finished, until you look, is finished.
	sessions : Str -> Try(List(Chat.Session), [ToolFailed(Str), InvalidJson(Str), MissingRequiredField(Str)])
	sessions = |body| {
		listed : Try({ result : { structured_content : { agents : List(Agent) } } }, _)
		listed = Json.parser_camel()(tool_answer(body)?)
		Ok(
			listed?.result.structured_content.agents
				.drop_if(|agent| agent.archived_at.map_ok(|archived| archived.is_ok()) ?? Bool.False)
				.map(|agent| { id: agent.id, provider: "paseo", agent: agent.provider, title: agent.title ?? agent.short_id, status: Paseo.listed_status(agent) }),
		)
	}

	listed_status : Agent -> Chat.Status
	listed_status = |agent|
		match (agent.attention_reason, Paseo.chat_status({ status: agent.status, pending_permissions: [], last_error: Err(Missing) })) {
			(Ok(Ok("permission")), _) => AwaitingPermission
			(Ok(Ok("finished")), Idle) => Finished
			(_, status) => status
		}

	status_snapshot : Str -> Try(Snapshot, [ToolFailed(Str), InvalidJson(Str), MissingRequiredField(Str)])
	status_snapshot = |body| {
		answered : Try({ result : { structured_content : { snapshot : Snapshot } } }, _)
		answered = Json.parser_camel()(tool_answer(body)?)
		Ok(answered?.result.structured_content.snapshot)
	}

	## Whether `send_prompt` or `answer_permission` succeeded.
	succeeded : Str -> Try({}, [ToolFailed(Str), InvalidJson(Str), MissingRequiredField(Str)])
	succeeded = |body| tool_answer(body).map_ok(|_| {})

	chat_status : Snapshot -> Chat.Status
	chat_status = |{ status: paseo_status, pending_permissions, last_error }|
		if !pending_permissions.is_empty() {
			AwaitingPermission
		} else {
			match paseo_status {
				"running" => Running
				"initializing" => Running
				"error" => Failed(last_error ?? "error")
				"closed" => Finished
				_ => Idle
			}
		}

	## The first message on Paseo's WebSocket. With these capabilities Paseo
	## sends a client only what it asks for, not every agent's stream.
	hello : Str -> Str
	hello = |client_id|
		Json.to_str({ type: "hello", clientId: client_id, clientType: "cli", protocolVersion: 1.U8, capabilities: { explicit_event_subscriptions: Bool.True, selective_agent_timeline: Bool.True } })

	## Fetches the entries after the state's cursor, or the last `page_limit`
	## on a session's first fetch.
	timeline_request : State, Str, Str -> Str
	timeline_request = |state, agent_id, request_id|
		if state.epoch == "" {
			Json.to_str({ type: "session", message: { type: "fetch_agent_timeline_request", agentId: agent_id, requestId: request_id, direction: "tail", limit: Paseo.page_limit } })
		} else {
			Json.to_str({ type: "session", message: { type: "fetch_agent_timeline_request", agentId: agent_id, requestId: request_id, direction: "after", cursor: { epoch: state.epoch, seq: state.cursor }, limit: Paseo.page_limit } })
		}

	## The page in a WebSocket message that answers `request_id`. Paseo sends
	## other messages too, such as its status after `hello`.
	timeline_page : Str, Str -> Try(Page, [OtherMessage, TimelineFailed(Str), InvalidJson(Str), MissingRequiredField(Str)])
	timeline_page = |text, request_id| {
		envelope : Try({ message : Try({ type : Str }, [Missing]) }, _)
		envelope = Json.parser_camel()(text)
		if envelope?.message.map_ok(|message| message.type) != Ok("fetch_agent_timeline_response") {
			return Err(OtherMessage)
		}
		response : Try({ message : { payload : Page } }, _)
		response = Json.parser_camel()(text)
		page = response?.message.payload
		if page.request_id != request_id {
			Err(OtherMessage)
		} else {
			match page.error {
				Ok(error) => Err(TimelineFailed(error))
				Err(Null) => Ok(page)
			}
		}
	}

	## The chat.v1 events a page and the agent's snapshot add, in timeline
	## order, then permission and status changes:
	##
	## - a user message, once;
	## - an assistant message, once it is final: when a later entry exists or
	##   the agent is not running (idle, done, failed or awaiting permission).
	##   Until then nothing after it is emitted, and the next fetch starts at it;
	## - a tool call when it first appears, its result once it completed,
	##   failed or was canceled;
	## - Paseo's error items, as agent messages;
	## - a permission request when it appears in the snapshot, and an answer
	##   when it disappears. Paseo doesn't say how a request was answered, so
	##   an answer liton didn't give counts as allowed (see `answered`);
	## - the status, when it changes.
	##
	## After a `reset` the page's entries count as emitted, so nothing repeats,
	## except open tool calls (their ids outlive epochs) and a last assistant
	## message not final yet. What happened in the reset's window is lost.
	update : State, Page, Snapshot -> { state : State, events : List(Chat.Event) }
	update = |state, page, snapshot| {
		status = Paseo.chat_status(snapshot)
		count = page.entries.len()
		final = |index| status != Running or index + 1 < count
		replayed = page.reset or (state.epoch != "" and page.epoch != state.epoch)
		start =
			if replayed {
				page.entries.map_with_index(|entry, index| if (entry.item.type == "assistant_message" and !final(index)) entry.seq_start - 1 else entry.seq_start).last() ?? 0
			} else {
				state.emitted_through
			}
		walked = page.entries.map_with_index(|entry, index| (entry, final(index))).fold_until(
			{ through: start, open_calls: state.open_calls, events: [], holding: Err(NotHolding) },
			|walk, (entry, is_final)| step(walk, entry, is_final),
		)
		cursor =
			match walked.holding {
				Ok(seq_start) => seq_start - 1
				Err(NotHolding) => page.end_cursor.map_ok(|end| end.seq) ?? (if (replayed) 0 else state.cursor)
			}
		ids = snapshot.pending_permissions.map(|permission| permission.id)
		answers = state.permissions.drop_if(|id| ids.contains(id)).map(|id| PermissionAnswered({ request_id: id, allowed: Bool.True }))
		requests =
			snapshot.pending_permissions
				.drop_if(|permission| state.permissions.contains(permission.id))
				.map(|permission| PermissionRequested({ request_id: permission.id, tool: permission.name, description: permission.title ?? (permission.description ?? permission.name) }))
		{
			state: { epoch: page.epoch, cursor, emitted_through: walked.through, open_calls: walked.open_calls, permissions: ids, status },
			events: walked.events.concat(answers).concat(requests).concat(if (status == state.status) [] else [StatusChanged(status)]),
		}
	}

	## Forgets a permission request liton answered itself, once Paseo took the
	## answer (`succeeded`), so `update` doesn't
	## emit an answer for it; the daemon records the real one.
	answered : State, Str -> State
	answered = |state, request_id| { ..state, permissions: state.permissions.drop_if(|id| id == request_id) }
}

Walk : { through : U64, open_calls : List(Str), events : List(Chat.Event), holding : Try(U64, [NotHolding]) }

step : Walk, Paseo.Entry, Bool -> [Continue(Walk), Break(Walk)]
step = |walk, entry, is_final| {
	item = entry.item
	fresh = entry.seq_start > walk.through
	seen = { ..walk, through: if (fresh) entry.seq_start else walk.through }
	if item.type == "tool_call" {
		call_id = item.call_id ?? ""
		done = ["completed", "failed", "canceled"].contains(item.status ?? "")
		result = ToolResult({ call_id, output: tool_output(item), failed: item.status != Ok("completed") })
		if fresh and done {
			Continue({ ..seen, events: walk.events.concat([ToolCall({ call_id, tool: item.name ?? "tool", input: tool_input(item) }), result]) })
		} else if fresh {
			Continue({ ..seen, open_calls: walk.open_calls.append(call_id), events: walk.events.append(ToolCall({ call_id, tool: item.name ?? "tool", input: tool_input(item) })) })
		} else if done and walk.open_calls.contains(call_id) {
			Continue({ ..walk, open_calls: walk.open_calls.drop_if(|id| id == call_id), events: walk.events.append(result) })
		} else {
			Continue(walk)
		}
	} else if !fresh {
		Continue(walk)
	} else {
		match item.type {
			"user_message" => Continue({ ..seen, events: walk.events.append(UserMessage({ text: item.text ?? "" })) })
			"assistant_message" =>
				if is_final {
					Continue({ ..seen, events: walk.events.append(AgentMessage({ text: item.text ?? "" })) })
				} else {
					Break({ ..walk, holding: Ok(entry.seq_start) })
				}
			"error" => Continue({ ..seen, events: walk.events.append(AgentMessage({ text: item.message ?? "" })) })
			_ => Continue(seen)
		}
	}
}

## What a tool call works on: a shell command, a file, a query... or its name.
tool_input : Paseo.Item -> Str
tool_input = |item| {
	name = item.name ?? "tool"
	match item.detail {
		Err(Missing) => name
		Ok(detail) =>
			match detail.type {
				"shell" => detail.command ?? name
				"read" => detail.file_path ?? name
				"edit" => detail.file_path ?? name
				"write" => detail.file_path ?? name
				"search" => detail.query ?? name
				"fetch" => detail.url ?? name
				"sub_agent" => detail.description ?? name
				"plain_text" => detail.label ?? name
				"plan" => detail.text ?? name
				"unknown" => if (loose_text(detail.input) == "") name else loose_text(detail.input)
				_ => name
			}
	}
}

## A shell command's output, an edit's diff, a plain tool's text, an unknown tool's
## output when it
## is text, or a failed call's error.
tool_output : Paseo.Item -> Str
tool_output = |item| {
	output =
		match item.detail {
			Err(Missing) => ""
			Ok(detail) =>
				match detail.type {
					"shell" => loose_text(detail.output)
					"unknown" => loose_text(detail.output)
					"edit" => detail.unified_diff ?? ""
					"plain_text" => detail.text ?? ""
					_ => ""
				}
		}
	if (output == "") loose_text(item.error) else output
}

loose_text : Try(Paseo.Loose, [Missing]) -> Str
loose_text = |value|
	match value {
		Ok(Text(text)) => text
		_ => ""
	}

tool_call : Str, Str -> Str
tool_call = |name, arguments| "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":${Json.to_str(name)},\"arguments\":${arguments}}}"

## The JSON of a tool's answer. Paseo sends it as one server-sent event,
## whose `data:` lines hold it.
tool_answer : Str -> Try(Str, [ToolFailed(Str), InvalidJson(Str), MissingRequiredField(Str)])
tool_answer = |body| {
	data = body.split_on("\n").keep_if(|line| line.starts_with("data:")).map(|line| line.drop_prefix("data:").trim())
	json = if (data.is_empty()) body else Str.join_with(data, "\n")
	answer : Try({ result : Try({ is_error : Try(Bool, [Missing]), content : List({ text : Try(Str, [Missing]) }) }, [Missing]), error : Try({ message : Str }, [Missing]) }, _)
	answer = Json.parser_camel()(json)
	match answer? {
		{ error: Ok({ message }), .. } => Err(ToolFailed(message))
		{ result: Ok(result), .. } =>
			if result.is_error == Ok(Bool.True) {
				Err(ToolFailed(Str.join_with(result.content.map(|content| content.text ?? ""), "\n")))
			} else {
				Ok(json)
			}
		_ => Err(ToolFailed("no result"))
	}
}

# Synthetic fixtures in Paseo's shapes.

entry : U64, Str -> Str
entry = |seq_start, item|
	\\{"provider":"claude","item":${item},"timestamp":"2026-01-01T00:00:00.000Z","seqStart":${seq_start.to_str()},"seqEnd":${seq_start.to_str()},"sourceSeqRanges":[],"collapsed":[]}

shell : Str, Str, Str -> Str
shell = |call_id, status, output|
	\\{"type":"tool_call","callId":"${call_id}","name":"Bash","status":"${status}","error":null,"detail":{"type":"shell","command":"rg -n load_config","exitCode":null${output}}}

response : { epoch : Str, reset : Str, end : Str, status : Str, permissions : Str, entries : List(Str) } -> Str
response = |{ epoch, reset, end, status, permissions, entries }|
	\\{"type":"session","message":{"type":"fetch_agent_timeline_response","payload":{"requestId":"r1","agentId":"a1",
	\\"agent":{"id":"a1","provider":"claude","status":"${status}","pendingPermissions":[${permissions}],"capabilities":{"supportsStreaming":true},"title":null,"labels":{}},
	\\"direction":"after","projection":"projected","epoch":"${epoch}","reset":${reset},"staleCursor":${reset},"gap":false,"window":{"minSeq":1,"maxSeq":9,"nextSeq":10},
	\\"startCursor":null,"endCursor":${end},"hasOlder":false,"hasNewer":false,"entries":[${Str.join_with(entries, ",")}],"error":null}}}

## Fetches a page and updates with its agent, as the daemon would.
fetched : Paseo.State, Str -> { state : Paseo.State, events : List(Chat.Event) }
fetched = |state, text|
	match Paseo.timeline_page(text, "r1") {
		Ok(page) => Paseo.update(state, page, page.agent ?? { status: "", pending_permissions: [], last_error: Err(Missing) })
		Err(_) => { state, events: [UserMessage({ text: "unparsed" })] }
	}

first : { state : Paseo.State, events : List(Chat.Event) }
first = fetched(
	Paseo.initial,
	response({
		epoch: "e1",
		reset: "false",
		end: "{\"epoch\":\"e1\",\"seq\":4}",
		status: "running",
		permissions: "",
		entries: [entry(1, "{\"type\":\"user_message\",\"text\":\"Rename load_config\"}"), entry(2, shell("c1", "running", "")), entry(4, "{\"type\":\"assistant_message\",\"text\":\"Renaming\"}")],
	}),
)

second : { state : Paseo.State, events : List(Chat.Event) }
second = fetched(
	first.state,
	response({
		epoch: "e1",
		reset: "false",
		end: "{\"epoch\":\"e1\",\"seq\":6}",
		status: "idle",
		permissions: "",
		entries: [entry(2, shell("c1", "completed", ",\"output\":\"src/Config.roc:3\"")), entry(4, "{\"type\":\"assistant_message\",\"text\":\"Renaming it: done.\"}")],
	}),
)

asked : { state : Paseo.State, events : List(Chat.Event) }
asked = fetched(second.state, response({ epoch: "e1", reset: "false", end: "null", status: "running", permissions: "{\"id\":\"p1\",\"provider\":\"claude\",\"name\":\"Edit\",\"kind\":\"tool\",\"title\":\"Edit src/Config.roc\"}", entries: [] }))

answered_elsewhere : List(Str) -> { state : Paseo.State, events : List(Chat.Event) }
answered_elsewhere = |permissions| fetched(asked.state, response({ epoch: "e1", reset: "false", end: "null", status: "running", permissions: Str.join_with(permissions, ","), entries: [] }))

expect first.events == [UserMessage({ text: "Rename load_config" }), ToolCall({ call_id: "c1", tool: "Bash", input: "rg -n load_config" }), StatusChanged(Running)]
expect first.state == { epoch: "e1", cursor: 3, emitted_through: 2, open_calls: ["c1"], permissions: [], status: Running }
expect second.events == [ToolResult({ call_id: "c1", output: "src/Config.roc:3", failed: Bool.False }), AgentMessage({ text: "Renaming it: done." }), StatusChanged(Idle)]
expect second.state == { epoch: "e1", cursor: 6, emitted_through: 4, open_calls: [], permissions: [], status: Idle }
expect asked.events == [PermissionRequested({ request_id: "p1", tool: "Edit", description: "Edit src/Config.roc" }), StatusChanged(AwaitingPermission)]
expect asked.state.cursor == 6
expect answered_elsewhere([]).events == [PermissionAnswered({ request_id: "p1", allowed: Bool.True }), StatusChanged(Running)]
expect fetched(Paseo.answered(asked.state, "p1"), response({ epoch: "e1", reset: "false", end: "null", status: "running", permissions: "", entries: [] })).events == [StatusChanged(Running)]

# Paseo restarted: the same timeline in a new epoch repeats nothing, but closes the open call.
expect {
	replayed = fetched(
		first.state,
		response({
			epoch: "e2",
			reset: "true",
			end: "{\"epoch\":\"e2\",\"seq\":3}",
			status: "idle",
			permissions: "",
			entries: [entry(1, "{\"type\":\"user_message\",\"text\":\"Rename load_config\"}"), entry(2, shell("c1", "failed", "")), entry(3, "{\"type\":\"assistant_message\",\"text\":\"Renaming\"}")],
		}),
	)
	replayed.events == [ToolResult({ call_id: "c1", output: "", failed: Bool.True }), StatusChanged(Idle)] and replayed.state.cursor == 3 and replayed.state.epoch == "e2"
}

expect Paseo.timeline_page("{\"type\":\"session\",\"message\":{\"type\":\"status\",\"payload\":{\"status\":\"server_info\"}}}", "r1").map_ok(|_| {}) == Err(OtherMessage)
expect Paseo.timeline_page("{\"type\":\"pong\"}", "r1").map_ok(|_| {}) == Err(OtherMessage)

expect {
	body =
		\\event: message
		\\data: {"result":{"content":[],"structuredContent":{"agents":[{"id":"a1","shortId":"a1s","title":null,"provider":"codex","model":null,"status":"running","cwd":"/work","createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z","lastUserMessageAt":null,"archivedAt":null,"labels":{}},{"id":"a3","shortId":"a3s","title":"Done","provider":"claude","model":null,"status":"idle","cwd":"/work","createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z","lastUserMessageAt":null,"archivedAt":null,"requiresAttention":true,"attentionReason":"finished","labels":{}},{"id":"a2","shortId":"a2s","title":"Old work","provider":"claude","model":null,"status":"closed","cwd":"/work","createdAt":"2026-01-01T00:00:00.000Z","updatedAt":"2026-01-01T00:00:00.000Z","lastUserMessageAt":null,"archivedAt":"2026-01-02T00:00:00.000Z","labels":{}}]}},"jsonrpc":"2.0","id":1}
		\\
		\\
	Paseo.sessions(body) == Ok([{ id: "a1", provider: "paseo", agent: "codex", title: "a1s", status: Running }, { id: "a3", provider: "paseo", agent: "claude", title: "Done", status: Finished }])
}

expect Paseo.succeeded("event: message\ndata: {\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"Agent a9 not found\"}],\"isError\":true},\"jsonrpc\":\"2.0\",\"id\":1}\n\n") == Err(ToolFailed("Agent a9 not found"))

expect {
	body = "data: {\"result\":{\"content\":[],\"structuredContent\":{\"status\":\"error\",\"snapshot\":{\"id\":\"a1\",\"status\":\"error\",\"pendingPermissions\":[],\"lastError\":\"rate limited\"}}},\"jsonrpc\":\"2.0\",\"id\":1}"
	Paseo.status_snapshot(body).map_ok(Paseo.chat_status) == Ok(Failed("rate limited"))
}

expect Paseo.answer_permission("a1", "p1", Bool.False) == "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"respond_to_permission\",\"arguments\":{\"agentId\":\"a1\",\"requestId\":\"p1\",\"response\":{\"behavior\":\"deny\"}}}}"

expect {
	decoded : Try(Paseo.State, _)
	decoded = Json.parse(Json.to_str(first.state))
	decoded == Ok(first.state)
}

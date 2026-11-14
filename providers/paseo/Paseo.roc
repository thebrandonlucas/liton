import cap.Capability
import cap.Chat
import cap.Manifest

## Paseo's agents as chat.v1 sessions, all over Paseo's WebSocket, the one
## thing a relay carries: agents are listed, timelines fetched, agents
## prompted and permissions answered there. Speaks Paseo 0.9.2 to 0.15.3.
## Paseo's own JSON is camelCase, which `Json.parser_camel` reads into the
## snake_case fields below; liton reads only these fields.
Paseo := [].{
	provider : Manifest.Provider
	provider = { id: "paseo", name: "Paseo", capabilities: [Capability.chat_v1, Capability.workspace_git_v1, Capability.workspaces_v1, Capability.files_v1] }

	## How many timeline entries a fetch asks for: a session's first fetch
	## takes its last ones, later fetches follow on while a page `has_newer`.
	page_limit : U64
	page_limit = 200

	## Declared before `Loose`, whose parser uses it: declared after, its
	## derived parser_for "does not exist" (Roc nightly-2026-11-07;
	## https://github.com/roc-lang/roc/issues/12994, repro in roc-issues
	## archive/BUG-028-derived-parser-for-before-declaration).
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

	## Prompts an agent, interrupting it if it is running, as Paseo's own app
	## does. Paseo answers once the agent took the prompt (see `sent`).
	send_request : Str, Str, Str -> Str
	send_request = |agent_id, text, request_id|
		Json.to_str({ type: "session", message: { type: "send_agent_message_request", requestId: request_id, agentId: agent_id, text } })

	## Whether a `send_agent_message_response` says the agent took the prompt.
	sent : Str, Str -> Try({}, [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str)])
	sent = |text, request_id| {
		answered : Try({ message : { payload : { accepted : Bool, error : Try(Str, [Null]) } } }, _)
		answered = Json.parser_camel()(Paseo.write_answer(text, "send_agent_message_response", request_id)?)
		payload = answered?.message.payload
		if (payload.accepted) Ok({}) else Err(Refused(payload.error ?? "Paseo did not take the message"))
	}

	## Answers a permission request. Paseo answers with the request's id: an
	## `agent_permission_resolved` once it took the answer (see `resolved`).
	permission_answer : Str, Str, Bool -> Str
	permission_answer = |agent_id, request_id, allowed|
		Json.to_str({ type: "session", message: { type: "agent_permission_response", agentId: agent_id, requestId: request_id, response: { behavior: if (allowed) "allow" else "deny" } } })

	resolved : Str, Str -> Try({}, [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str)])
	resolved = |text, request_id| Paseo.write_answer(text, "agent_permission_resolved", request_id).map_ok(|_| {})

	## Stops an agent's running turn, if any. Paseo answers with a
	## `cancel_agent_response` once it stopped, or why it couldn't (see
	## `canceled`).
	cancel_request : Str, Str -> Str
	cancel_request = |agent_id, request_id| Json.to_str({ type: "session", message: { type: "cancel_agent_request", agentId: agent_id, requestId: request_id } })

	canceled : Str, Str -> Try({}, [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str)])
	canceled = |text, request_id| {
		answered : Try({ message : { payload : { error : Try(Try(Str, [Null]), [Missing]) } } }, _)
		answered = Json.parser_camel()(Paseo.write_answer(text, "cancel_agent_response", request_id)?)
		match answered?.message.payload.error {
			Ok(Ok(reason)) => Err(Refused(reason))
			_ => Ok({})
		}
	}

	## Asks for one agent, for its state when a timeline page lacks it.
	agent_request : Str, Str -> Str
	agent_request = |agent_id, request_id| Json.to_str({ type: "session", message: { type: "fetch_agent_request", agentId: agent_id, requestId: request_id } })

	agent_snapshot : Str, Str -> Try(Snapshot, [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str)])
	agent_snapshot = |text, request_id| {
		answered : Try({ message : { payload : { agent : Try(Snapshot, [Null]), error : Try(Str, [Null]) } } }, _)
		answered = Json.parser_camel()(Paseo.write_answer(text, "fetch_agent_response", request_id)?)
		payload = answered?.message.payload
		match payload.agent {
			Ok(agent) => Ok(agent)
			Err(Null) => Err(Refused(payload.error ?? "no agent"))
		}
	}

	## `text` when it is the `type` message answering `request_id`, or the
	## reason of the `rpc_error` Paseo answers it with instead.
	write_answer : Str, Str, Str -> Try(Str, [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str)])
	write_answer = |text, type, request_id| {
		failed : Try({ message : { type : Str, payload : { request_id : Str, error : Str } } }, _)
		failed = Json.parser_camel()(text)
		match failed {
			Ok({ message }) if message.type == "rpc_error" and message.payload.request_id == request_id => Err(Refused(message.payload.error))
			_ =>
				match Paseo.answer_to(text, type, request_id) {
					Ok(answer) => Ok(answer)
					Err(OtherMessage) => Err(OtherMessage)
					Err(InvalidJson(problem)) => Err(InvalidJson(problem))
					Err(MissingRequiredField(field)) => Err(MissingRequiredField(field))
				}
		}
	}

	## Sessions Paseo's providers keep that Paseo doesn't run yet, such as a
	## sandboxed agent's: all of them, not those of one directory, since a
	## remote one reports the directory "/".
	importable_request : Str -> Str
	importable_request = |request_id| Json.to_str({ type: "session", message: { type: "fetch_recent_provider_sessions_request", requestId: request_id, limit: 200.U16 } })

	## The sessions a `fetch_recent_provider_sessions_response` lists, read
	## only: each id is "import:<provider>:<its id>", a session's agent is its
	## provider's label, and its title the session's, or its first prompt.
	## Importing one (`import_agent_request`) would make it an agent.
	Importable : { provider_id : Str, provider_label : Str, provider_handle_id : Str, cwd : Str, title : Try(Str, [Null]), first_prompt_preview : Try(Str, [Null]) }

	importable_answer : Str, Str -> Try(List({ session : Chat.Session, directory : Str }), [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str)])
	importable_answer = |text, request_id| {
		answered : Try({ message : { payload : { entries : List(Importable) } } }, _)
		answered = Json.parser_camel()(Paseo.write_answer(text, "fetch_recent_provider_sessions_response", request_id)?)
		Ok(
			answered?.message.payload.entries.map(
				|entry| {
					title = entry.title ?? (entry.first_prompt_preview ?? entry.provider_handle_id)
					{ session: Chat.session({ id: "import:${entry.provider_id}:${entry.provider_handle_id}", provider: "paseo", agent: entry.provider_label, title, status: Idle }), directory: entry.cwd }
				},
			),
		)
	}

	## An agent as `fetch_agents_response` lists it, with the workspace it works
	## in.
	ListedAgent : {
		id : Str,
		provider : Str,
		cwd : Str,
		workspace_id : Try(Str, [Missing]),
		title : Try(Str, [Null]),
		model : Try(Str, [Null]),
		status : Str,
		active_turn : Try(Try({ started_at : Try(Str, [Null]) }, [Null]), [Missing]),
		pending_permissions : List(Permission),
		last_error : Try(Str, [Missing]),
		attention_reason : Try(Try(Str, [Null]), [Missing]),
		requires_attention : Try(Bool, [Missing]),
		created_at : Str,
		updated_at : Str,
		last_user_message_at : Try(Str, [Null]),
		attention_timestamp : Try(Try(Str, [Null]), [Missing]),
	}

	## Asks for as many agents as Paseo lists at once, without archived ones.
	agents_request : Str -> Str
	agents_request = |request_id|
		Json.to_str({ type: "session", message: { type: "fetch_agents_request", requestId: request_id, page: { limit: 200.U16 } } })

	## The agents a `fetch_agents_response` lists, each with the directory and
	## the workspace it works in ("" for none). An agent whose attention Paseo
	## wants for a permission awaits it, and an idle one whose attention it
	## wants because it finished, until you look, is finished. An untitled one
	## goes by its id's first 7 characters, as Paseo's short id. Each session
	## tells its model, workspace, the branch Paseo placed it on, when its
	## running turn started and when it last changed, as far as Paseo does.
	## They are in the order of Paseo's MCP `list_agents` (see `listed_order`).
	agents_answer : Str, Str -> Try(List({ session : Chat.Session, directory : Str, workspace_id : Str }), [OtherMessage, InvalidJson(Str), MissingRequiredField(Str)])
	agents_answer = |text, request_id| {
		answered : Try({ message : { payload : { entries : List({ agent : ListedAgent, project : Try({ checkout : { current_branch : Try(Try(Str, [Null]), [Missing]) } }, [Missing]) }) } } }, _)
		answered = Json.parser_camel()(Paseo.answer_to(text, "fetch_agents_response", request_id)?)
		Ok(
			answered?.message.payload.entries.sort_with(|left, right| listed_order(left.agent, right.agent)).map(
				|{ agent, project }| {
					title = agent.title ?? (Str.from_utf8(agent.id.to_utf8().take_first(7)) ?? agent.id)
					optional = |value| value.map_err(|_| Missing)
					session = {
						..Chat.session({ id: agent.id, provider: "paseo", agent: agent.provider, title, status: Paseo.listed_status(agent) }),
						model: optional(agent.model),
						workspace: Ok({ id: agent.workspace_id, directory: agent.cwd }),
						branch: optional(project.map_ok(|placed| placed.checkout.current_branch ?? Err(Null)) ?? Err(Null)),
						running_since: optional(agent.active_turn.map_ok(|turn| turn.map_ok(|active| active.started_at) ?? Err(Null)) ?? Err(Null)),
						updated: Ok(agent.updated_at),
					}
					{ session, directory: agent.cwd, workspace_id: agent.workspace_id ?? "" }
				},
			),
		)
	}

	listed_status : ListedAgent -> Chat.Status
	listed_status = |agent|
		match (agent.attention_reason, Paseo.chat_status({ status: agent.status, pending_permissions: agent.pending_permissions, last_error: agent.last_error })) {
			(Ok(Ok("permission")), _) => AwaitingPermission
			(Ok(Ok("finished")), Idle) => Finished
			(_, status) => status
		}

	## `text` when it is the `type` message answering `request_id`.
	answer_to : Str, Str, Str -> Try(Str, [OtherMessage, InvalidJson(Str), MissingRequiredField(Str)])
	answer_to = |text, type, request_id| {
		envelope : Try({ message : Try({ type : Str }, [Missing]) }, _)
		envelope = Json.parser_camel()(text)
		if envelope?.message.map_ok(|message| message.type) != Ok(type) {
			return Err(OtherMessage)
		}
		answered : Try({ message : { payload : { request_id : Str } } }, _)
		answered = Json.parser_camel()(text)
		if (answered?.message.payload.request_id == request_id) Ok(text) else Err(OtherMessage)
	}

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
	## sends a client only what it asks for, not every agent's stream, lists
	## the agents of every provider, not only Claude, Codex and OpenCode (a
	## sandboxed agent's provider is an ACP one), answers a permission answer
	## (`owned_subscriptions`), and says why it refuses a hello (see
	## `greeting`). The password in `auth` is
	## what a relay carries: from 0.15 Paseo checks it when the connection
	## brought none in its headers; Paseo 0.9 ignores it and wants the
	## WebSocket protocol `paseo.bearer.<password>` (see `protocol`).
	hello : Str, Str -> Str
	hello = |client_id, password|
		Json.to_str({ type: "hello", clientId: client_id, clientType: "cli", protocolVersion: 1.U8, auth: { kind: "password", password }, capabilities: { explicit_event_subscriptions: Bool.True, selective_agent_timeline: Bool.True, hello_rejection: Bool.True, all_providers: Bool.True, owned_subscriptions: Bool.True } })

	## The WebSocket protocol that carries the password when Paseo is reached
	## directly. Paseo 0.15 still takes it there, until 2027-03.
	protocol : Str -> Str
	protocol = |password| "paseo.bearer.${password}"

	## What a message after `hello` says of it: Paseo welcomes a client with
	## its `server_info`, or refuses it with `hello.rejected` and a reason.
	greeting : Str -> [Welcomed, Rejected(Str), NotGreeting]
	greeting = |text| {
		parsed : Try({ type : Str, reason : Try(Str, [Missing]), message : Try({ type : Str, payload : Try({ status : Try(Str, [Missing]) }, [Missing]) }, [Missing]) }, _)
		parsed = Json.parser_camel()(text)
		match parsed {
			Ok({ type: "hello.rejected", reason, .. }) => Rejected(reason ?? "")
			Ok({ message: Ok({ type: "status", payload: Ok({ status: Ok("server_info") }) }), .. }) => Welcomed
			_ => NotGreeting
		}
	}

	## Why Paseo refused liton, from a `hello.rejected` reason or, as Paseo 0.9
	## and a wrong `protocol` say it, the reason it closed the connection with.
	refusal : Str -> Str
	refusal = |reason|
		match reason {
			"password_required" | "Password required" => "Paseo wants a password: set PASEO_PASSWORD to its password"
			"incorrect_password" | "Incorrect password" => "Paseo refused the password in PASEO_PASSWORD"
			"incompatible_protocol" | "Incompatible protocol version" => "Paseo doesn't speak liton's protocol version"
			_ => "Paseo refused liton: ${reason}"
		}

	## A session that stands for Paseo refusing liton, listed first so the
	## refusal shows where Paseo's sessions do.
	refused_session : Str -> Chat.Session
	refused_session = |reason| Chat.session({ id: "paseo-refused", provider: "paseo", agent: "paseo", title: Paseo.refusal(reason), status: Failed(Paseo.refusal(reason)) })

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

	## Whether a WebSocket message answers the request `request_id`, as a
	## timeline page or a checkout answer does in its payload.
	answers_request : Str, Str -> Bool
	answers_request = |text, request_id| {
		envelope : Try({ message : Try({ payload : Try({ request_id : Try(Str, [Missing]) }, [Missing]) }, [Missing]) }, _)
		envelope = Json.parser_camel()(text)
		envelope.map_ok(|{ message }| message.map_ok(|{ payload }| payload.map_ok(|{ request_id: answered }| answered == Ok(request_id)) ?? Bool.False) ?? Bool.False) ?? Bool.False
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
	## answer (`resolved`), so `update` doesn't
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

## Paseo's MCP `list_agents` order: those that want your attention first,
## then running, initializing, idle, failed and closed ones, each the latest
## active first.
listed_order : Paseo.ListedAgent, Paseo.ListedAgent -> [Before, After, Same]
listed_order = |left, right| {
	compared = |earlier, later| if (earlier < later) Before else if (earlier > later) After else Same
	wants = |agent| if (agent.requires_attention ?? Bool.False) 0 else 1
	rank = |agent| ["running", "initializing", "idle", "error", "closed"].find_first_index(|status| status == agent.status) ?? 5
	[compared(wants(left), wants(right)), compared(rank(left), rank(right)), compared(active_at(right), active_at(left))].find_first(|order| order != Same) ?? Same
}

## When an agent was last active, as the digits of the latest of its
## timestamps: Paseo writes them all as `2026-01-01T00:00:00.000Z`.
active_at : Paseo.ListedAgent -> U64
active_at = |agent|
	[Ok(agent.created_at), Ok(agent.updated_at), agent.last_user_message_at, agent.attention_timestamp ?? Err(Null)]
		.keep_oks(|timestamp| timestamp)
		.map(|timestamp| timestamp.to_utf8().keep_if(|byte| byte >= '0' and byte <= '9').fold(0, |number, digit| number * 10 + (digit - '0').to_u64()))
		.fold(0, |latest, at| if (at > latest) at else latest)

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
expect Paseo.answers_request(response({ epoch: "e1", reset: "false", end: "null", status: "idle", permissions: "", entries: [] }), "r1")
expect !Paseo.answers_request(response({ epoch: "e1", reset: "false", end: "null", status: "idle", permissions: "", entries: [] }), "r2")
expect !Paseo.answers_request("{\"type\":\"session\",\"message\":{\"type\":\"status\",\"payload\":{\"status\":\"server_info\"}}}", "r1")
expect !Paseo.answers_request("{\"type\":\"pong\"}", "r1")

expect {
	not_git = "\"cwd\":\"/work\",\"isGit\":false,\"currentBranch\":null,\"remoteUrl\":null,\"isPaseoOwnedWorktree\":false,\"mainRepoRoot\":null"
	agent = |fields, checkout| "{\"agent\":{\"provider\":\"claude\",\"cwd\":\"/work\",\"createdAt\":\"2026-01-01T00:00:00.000Z\",\"lastUserMessageAt\":null,\"capabilities\":{},\"currentModeId\":null,\"availableModes\":[],\"persistence\":null,\"labels\":{},${fields}},\"project\":{\"projectKey\":\"p1\",\"projectName\":\"app\",\"checkout\":{${checkout}}}}"
	entries = [
		agent("\"id\":\"a1b2c3d4e5\",\"model\":\"opus\",\"activeTurn\":{\"turnId\":\"t1\",\"startedAt\":\"2026-01-01T00:01:00.000Z\"},\"updatedAt\":\"2026-01-01T00:00:00.000Z\",\"workspaceId\":\"w1\",\"title\":null,\"status\":\"running\",\"pendingPermissions\":[]", "\"cwd\":\"/work\",\"isGit\":true,\"currentBranch\":\"fix-login\",\"remoteUrl\":null,\"isPaseoOwnedWorktree\":false,\"mainRepoRoot\":null"),
		agent("\"id\":\"a3\",\"model\":null,\"activeTurn\":null,\"updatedAt\":\"2026-01-01T00:00:00.000Z\",\"workspaceId\":\"w1\",\"title\":\"Done\",\"status\":\"idle\",\"pendingPermissions\":[],\"requiresAttention\":true,\"attentionReason\":\"finished\"", not_git),
		agent("\"id\":\"a4\",\"model\":null,\"updatedAt\":\"2026-01-02T00:00:00.000Z\",\"title\":\"Asks\",\"status\":\"running\",\"pendingPermissions\":[{\"id\":\"p1\",\"provider\":\"claude\",\"name\":\"Edit\",\"kind\":\"tool\"}]", not_git),
	]
	text = "{\"type\":\"session\",\"message\":{\"type\":\"fetch_agents_response\",\"payload\":{\"requestId\":\"r1\",\"entries\":[${Str.join_with(entries, ",")}],\"pageInfo\":{\"nextCursor\":null,\"prevCursor\":null,\"hasMore\":false}}}}"
	listed = |id, title, status, workspace_id, updated| { ..Chat.session({ id, provider: "paseo", agent: "claude", title, status }), workspace: Ok({ id: workspace_id, directory: "/work" }), updated: Ok(updated) }
	Paseo.agents_answer(text, "r1")
		== Ok([
			{ session: listed("a3", "Done", Finished, Ok("w1"), "2026-01-01T00:00:00.000Z"), directory: "/work", workspace_id: "w1" },
			{ session: listed("a4", "Asks", AwaitingPermission, Err(Missing), "2026-01-02T00:00:00.000Z"), directory: "/work", workspace_id: "" },
			{ session: { ..listed("a1b2c3d4e5", "a1b2c3d", Running, Ok("w1"), "2026-01-01T00:00:00.000Z"), model: Ok("opus"), branch: Ok("fix-login"), running_since: Ok("2026-01-01T00:01:00.000Z") }, directory: "/work", workspace_id: "w1" },
		])
		and Paseo.agents_answer(text, "r2").map_ok(|_| {}) == Err(OtherMessage)
}

session : Str -> Str
session = |message| "{\"type\":\"session\",\"message\":${message}}"

## A request as liton writes it: Json.to_str orders fields by name.
request : Str -> Str
request = |message| "{\"message\":${message},\"type\":\"session\"}"

expect Paseo.permission_answer("a1", "p1", Bool.False) == request("{\"agentId\":\"a1\",\"requestId\":\"p1\",\"response\":{\"behavior\":\"deny\"},\"type\":\"agent_permission_response\"}")
expect Paseo.send_request("a1", "Go on", "w1") == request("{\"agentId\":\"a1\",\"requestId\":\"w1\",\"text\":\"Go on\",\"type\":\"send_agent_message_request\"}")

expect {
	answer = |fields| session("{\"type\":\"send_agent_message_response\",\"payload\":{\"requestId\":\"w1\",\"agentId\":\"a1\",${fields}}}")
	Paseo.sent(answer("\"accepted\":true,\"error\":null"), "w1") == Ok({})
		and Paseo.sent(answer("\"accepted\":true,\"deliveryStatus\":\"queued\",\"error\":null"), "w1") == Ok({})
		and Paseo.sent(answer("\"accepted\":false,\"error\":\"Agent a9 not found\""), "w1") == Err(Refused("Agent a9 not found"))
		and Paseo.sent(answer("\"accepted\":true,\"error\":null"), "w2") == Err(OtherMessage)
}

expect {
	resolution = session("{\"type\":\"agent_permission_resolved\",\"payload\":{\"agentId\":\"a1\",\"requestId\":\"p1\",\"resolution\":{\"behavior\":\"allow\"}}}")
	failure = session("{\"type\":\"rpc_error\",\"payload\":{\"requestId\":\"p1\",\"requestType\":\"agent_permission_response\",\"error\":\"Request failed: No pending permission\",\"code\":\"handler_error\"}}")
	Paseo.resolved(resolution, "p1") == Ok({})
		and Paseo.resolved(failure, "p1") == Err(Refused("Request failed: No pending permission"))
		and Paseo.resolved(failure, "p2") == Err(OtherMessage)
		and Paseo.answers_request(resolution, "p1")
		and Paseo.answers_request(failure, "p1")
}

expect Paseo.cancel_request("a1", "c1") == request("{\"agentId\":\"a1\",\"requestId\":\"c1\",\"type\":\"cancel_agent_request\"}")

expect {
	answer = |fields| session("{\"type\":\"cancel_agent_response\",\"payload\":{\"requestId\":\"c1\",\"agentId\":\"a1\",\"agent\":null${fields}}}")
	Paseo.canceled(answer(",\"error\":null"), "c1") == Ok({})
		and Paseo.canceled(answer(""), "c1") == Ok({})
		and Paseo.canceled(answer(",\"error\":\"Agent a1 is still running\""), "c1") == Err(Refused("Agent a1 is still running"))
		and Paseo.canceled(answer(",\"error\":null"), "c2") == Err(OtherMessage)
}

expect {
	answer = |payload| session("{\"type\":\"fetch_agent_response\",\"payload\":{\"requestId\":\"s1\",${payload}}}")
	found = answer("\"agent\":{\"id\":\"a1\",\"status\":\"error\",\"pendingPermissions\":[],\"lastError\":\"rate limited\"},\"project\":null,\"error\":null")
	Paseo.agent_snapshot(found, "s1").map_ok(Paseo.chat_status) == Ok(Failed("rate limited"))
		and Paseo.agent_snapshot(answer("\"agent\":null,\"error\":\"Agent a9 not found\""), "s1").map_ok(|_| {}) == Err(Refused("Agent a9 not found"))
}

expect Paseo.hello("liton-daemon", "secret") == "{\"auth\":{\"kind\":\"password\",\"password\":\"secret\"},\"capabilities\":{\"all_providers\":true,\"explicit_event_subscriptions\":true,\"hello_rejection\":true,\"owned_subscriptions\":true,\"selective_agent_timeline\":true},\"clientId\":\"liton-daemon\",\"clientType\":\"cli\",\"protocolVersion\":1,\"type\":\"hello\"}"

expect Paseo.greeting(session("{\"type\":\"status\",\"payload\":{\"status\":\"server_info\",\"serverId\":\"s1\",\"version\":\"0.15.3\"}}")) == Welcomed
expect Paseo.greeting("{\"type\":\"hello.rejected\",\"reason\":\"incorrect_password\",\"accepts\":[\"password\"]}") == Rejected("incorrect_password")
expect Paseo.greeting(session("{\"type\":\"status\",\"payload\":{\"status\":\"agent_created\"}}")) == NotGreeting
expect Paseo.greeting("{\"type\":\"pong\"}") == NotGreeting
expect Paseo.refusal("incorrect_password") == Paseo.refusal("Incorrect password")
expect Paseo.refused_session("password_required").status == Failed("Paseo wants a password: set PASEO_PASSWORD to its password")

expect {
	entry_of = |fields| "{\"providerId\":\"sandbox\",\"providerLabel\":\"Sandbox\",\"cwd\":\"/\",\"lastPromptPreview\":null,\"lastActivityAt\":\"2026-01-01T00:00:00.000Z\",${fields}}"
	text = session("{\"type\":\"fetch_recent_provider_sessions_response\",\"payload\":{\"requestId\":\"i1\",\"entries\":[${entry_of("\"providerHandleId\":\"h1\",\"title\":\"Fix the build\",\"firstPromptPreview\":\"Fix it\"")},${entry_of("\"providerHandleId\":\"h2\",\"title\":null,\"firstPromptPreview\":null")}],\"providerErrors\":[{\"provider\":\"claude\",\"message\":\"disabled\"}]}}")
	Paseo.importable_answer(text, "i1")
		== Ok([
			{ session: Chat.session({ id: "import:sandbox:h1", provider: "paseo", agent: "Sandbox", title: "Fix the build", status: Idle }), directory: "/" },
			{ session: Chat.session({ id: "import:sandbox:h2", provider: "paseo", agent: "Sandbox", title: "h2", status: Idle }), directory: "/" },
		])
}

expect Paseo.importable_request("i1") == request("{\"limit\":200,\"requestId\":\"i1\",\"type\":\"fetch_recent_provider_sessions_request\"}")

expect {
	decoded : Try(Paseo.State, _)
	decoded = Json.parse(Json.to_str(first.state))
	decoded == Ok(first.state)
}

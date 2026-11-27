import cap.Capability
import cap.Chat
import cap.Manifest

## Paseo's agents as chat.v1 sessions, all over Paseo's WebSocket, the one
## thing a relay carries: agents are listed, timelines fetched, agents
## prompted and permissions answered there. Speaks Paseo 0.9.2 to 0.16.1.
## Paseo's own JSON is camelCase, which `Json.parser_camel` reads into the
## snake_case fields below; liton reads only these fields.
Paseo := [].{

	## The Paseo provider, with the capabilities it offers.
	provider : Manifest.Provider
	provider = { id: "paseo", name: "Paseo", capabilities: [Capability.chat_v1, Capability.workspace_git_v1, Capability.workspaces_v1, Capability.files_v1, Capability.schedules_v1] }

	## How many timeline entries a fetch asks for: a session's first fetch
	## takes its last ones, later fetches follow on while a page `has_newer`.
	page_limit : U64
	page_limit = 200

	## A JSON value Paseo leaves open, such as a tool's output or error: liton
	## shows a string, or an object's `message` or `content` string.
	Loose := [Text(Str), NotText].{

		## How a codec reads a `Loose` value.
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

	## A number Paseo sends, such as a cost, read as a Dec, or none when it
	## is one a Dec can't hold, so an odd number costs the listing nothing.
	Number := [Number(Dec), NotNumber].{
		parser_for = |encoding| {
			parse_number = Dec.parser_for(encoding)
			|state|
				match parse_number(state) {
					Ok(parsed) => Ok({ value: Number(parsed.value), rest: parsed.rest })
					Err(_) => Ok({ value: NotNumber, rest: encoding.skip_record_field(state)? })
				}
		}
	}

	## What an agent's last turn used, as Paseo's `lastUsage` tells it.
	Usage : { input_tokens : Try(Number, [Missing]), cached_input_tokens : Try(Number, [Missing]), output_tokens : Try(Number, [Missing]), total_cost_usd : Try(Number, [Missing]), context_window_max_tokens : Try(Number, [Missing]), context_window_used_tokens : Try(Number, [Missing]) }

	## The object a `Loose` value can be.
	LooseObject := { message : Try(Str, [Missing]), content : Try(Str, [Missing]) }.{

		## How a codec reads a `LooseObject`, derived from its fields.
		parser_for : _
	}

	## A pending permission request. A plan's carries the plan in its
	## `input`, and Paseo's choices for it, such as Implement and Reject, as
	## its `actions`.
	Permission : { id : Str, name : Str, title : Try(Str, [Missing]), description : Try(Str, [Missing]), input : Try({ plan : Try(Loose, [Missing]) }, [Missing]), actions : Try(List(Action), [Missing]) }

	## `behavior` is allow or deny, `variant` primary, secondary or danger.
	Action : { id : Str, label : Str, behavior : Str, variant : Try(Str, [Missing]) }

	## An agent's state, from `get_agent_status` or a timeline page's `agent`.
	## `status` is initializing, idle, running, error or closed. Its
	## `active_turn` is the turn it is working on, if any.
	Snapshot : { status : Str, pending_permissions : List(Permission), last_error : Try(Str, [Missing]), updated_at : Try(Str, [Missing]), active_turn : Try(Try({ started_at : Try(Str, [Null]) }, [Null]), [Missing]) }

	## A tool call's detail, as a timeline entry carries it: its `type`, such
	## as shell or edit, and the fields of that type Paseo fills in.
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
	## into one entry that keeps its `seq_start`, and its `timestamp`.
	Entry : { seq_start : U64, item : Item, timestamp : Try(Str, [Missing]) }

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
	## `permissions` the requests emitted without an answer, `turn` the turn
	## emitted without its end, if any.
	State : { epoch : Str, cursor : U64, emitted_through : U64, open_calls : List(Str), permissions : List(Str), status : Chat.Status, turn : Try(Turn, [Missing]) }

	## A turn: when it started, if liton saw, and its last entry's time.
	Turn : { started : Try(Str, [Missing]), last : Str }

	## A session's state before its first fetch.
	initial : State
	initial = { epoch: "", cursor: 0, emitted_through: 0, open_calls: [], permissions: [], status: Idle, turn: Err(Missing) }

	## Prompts an agent, interrupting it if it is running, as Paseo's own app
	## does, or steering its turn as `while_running` asks (Paseo's
	## `activeTurnBehavior`, from 0.5), with its attachments: images as its
	## `images`, text files as `text` attachments titled by their names.
	## Paseo answers once the agent took the prompt (see `sent`).
	send_request : Str, Str, Try([Interrupt, Steer], [Missing]), List(Chat.Attachment), Str -> Str
	send_request = |agent_id, text, while_running, attachments, request_id| {
		behavior : Try(Str, [Missing])
		behavior = while_running.map_ok(|asked| if (asked == Steer) "steer" else "interrupt")
		images = attachments.keep_oks(
			|attachment|
				match attachment {
					Image({ mime_type, data, .. }) => Ok({ data, mimeType: mime_type })
					Text(_) => Err(NotImage)
				},
		)
		texts = attachments.keep_oks(
			|attachment|
				match attachment {
					Text({ name, text: content }) => Ok({ type: "text", mimeType: "text/plain", title: name, text: content })
					Image(_) => Err(NotText)
				},
		)
		sent_images : Try(List({ data : Str, mimeType : Str }), [Missing])
		sent_images = if (images.is_empty()) Err(Missing) else Ok(images)
		sent_texts : Try(List({ type : Str, mimeType : Str, title : Str, text : Str }), [Missing])
		sent_texts = if (texts.is_empty()) Err(Missing) else Ok(texts)
		asked = { type: "send_agent_message_request", requestId: request_id, agentId: agent_id, text, activeTurnBehavior: behavior, images: sent_images, attachments: sent_texts }
		Json.to_str({ type: "session", message: asked })
	}

	## Whether a `send_agent_message_response` says the agent took the prompt.
	sent : Str, Str -> Try({}, [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str)])
	sent = |text, request_id| {
		answered : Try({ message : { payload : { accepted : Bool, error : Try(Str, [Null]) } } }, _)
		answered = Json.parser_camel()(Paseo.write_answer(text, "send_agent_message_response", request_id)?)
		payload = answered?.message.payload
		if (payload.accepted) Ok({}) else Err(Refused(payload.error ?? "Paseo did not take the message"))
	}

	## Answers a permission request, with the id of the action chosen if it
	## offered its own. Paseo answers with the request's id: an
	## `agent_permission_resolved` once it took the answer (see `resolved`).
	permission_answer : Str, Str, Bool, Try(Str, [Missing]) -> Str
	permission_answer = |agent_id, request_id, allowed, choice|
		Json.to_str({ type: "session", message: { type: "agent_permission_response", agentId: agent_id, requestId: request_id, response: { behavior: if (allowed) "allow" else "deny", selectedActionId: choice } } })

	## A pending request as chat.v1's: its title, or else its description,
	## as its line, a plan as its body, and its actions as its choices.
	requested : Permission -> Chat.Permission
	requested = |asked| {
		plan = loose_text(asked.input.map_ok(|input| input.plan) ?? Err(Missing))
		style = |variant|
			match variant {
				Ok("primary") => Primary
				Ok("danger") => Danger
				_ => Secondary
			}
		{
			..Chat.permission({ request_id: asked.id, tool: asked.name, description: asked.title ?? (asked.description ?? asked.name) }),
			body: if (plan == "") Err(Missing) else Ok(plan),
			choices: asked.actions.map_ok(|actions| actions.map(|action| { id: action.id, label: action.label, allows: action.behavior == "allow", style: style(action.variant) })),
		}
	}

	## Whether the `agent_permission_resolved` answer to `request_id` took the
	## permission's answer.
	resolved : Str, Str -> Try({}, [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str)])
	resolved = |text, request_id| Paseo.write_answer(text, "agent_permission_resolved", request_id).map_ok(|_| {})

	## Stops an agent's running turn, if any. Paseo answers with a
	## `cancel_agent_response` once it stopped, or why it couldn't (see
	## `canceled`).
	cancel_request : Str, Str -> Str
	cancel_request = |agent_id, request_id| Json.to_str({ type: "session", message: { type: "cancel_agent_request", agentId: agent_id, requestId: request_id } })

	## Whether the `cancel_agent_response` to `request_id` says the agent
	## stopped, or why it couldn't.
	canceled : Str, Str -> Try({}, [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str)])
	canceled = |text, request_id| {
		answered : Try({ message : { payload : { error : Try(Try(Str, [Null]), [Missing]) } } }, _)
		answered = Json.parser_camel()(Paseo.write_answer(text, "cancel_agent_response", request_id)?)
		match answered?.message.payload.error {
			Ok(Ok(reason)) => Err(Refused(reason))
			_ => Ok({})
		}
	}

	## Renames an agent, or gives it back the title Paseo derives with "".
	## Paseo answers with an `update_agent_response` (see `accepted`).
	rename_request : Str, Str, Str -> Str
	rename_request = |agent_id, title, request_id| Json.to_str({ type: "session", message: { type: "update_agent_request", agentId: agent_id, name: title, requestId: request_id } })

	## Archives an agent: Paseo stops it if it runs, and lists it no more.
	## Paseo answers with an `agent_archived` (see `archived`).
	archive_request : Str, Str -> Str
	archive_request = |agent_id, request_id| Json.to_str({ type: "session", message: { type: "archive_agent_request", agentId: agent_id, requestId: request_id } })

	## Whether the `agent_archived` answer to `request_id` says the agent was
	## archived.
	archived : Str, Str -> Try({}, [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str)])
	archived = |text, request_id| Paseo.write_answer(text, "agent_archived", request_id).map_ok(|_| {})

	## Whether the `type` answer to `request_id`, one of Paseo's that says
	## whether it took a write, took it.
	accepted : Str, Str, Str -> Try({}, [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str)])
	accepted = |text, type, request_id| {
		answered : Try({ message : { payload : { accepted : Bool, error : Try(Try(Str, [Null]), [Missing]) } } }, _)
		answered = Json.parser_camel()(Paseo.write_answer(text, type, request_id)?)
		payload = answered?.message.payload
		reason = payload.error.map_ok(|error| error ?? "") ?? ""
		if (payload.accepted) Ok({}) else Err(Refused(if (reason == "") "Paseo did not take the change" else reason))
	}

	## Starts an agent of the kind `agent` in `cwd`, in the workspace
	## `workspace_id` if any, as `agent_id`: an id liton picks, which makes
	## the same request sent again start no second agent. Paseo answers once
	## it made the agent (see `created`).
	create_request : { agent_id : Str, agent : Str, cwd : Str, workspace_id : Try(Str, [Missing]), model : Try(Str, [Missing]), mode : Try(Str, [Missing]), thinking : Try(Str, [Missing]), prompt : Str, request_id : Str } -> Str
	create_request = |{ agent_id, agent, cwd, workspace_id, model, mode, thinking, prompt, request_id }| {
		initial_prompt : Try(Str, [Missing])
		initial_prompt = if (prompt.is_empty()) Err(Missing) else Ok(prompt)
		Json.to_str({ type: "session", message: { type: "agent.create.request", requestId: request_id, agentId: agent_id, idempotencyKey: agent_id, workspaceId: workspace_id, initialPrompt: initial_prompt, config: { provider: agent, cwd, model, modeId: mode, thinkingOptionId: thinking } } })
	}

	## The requests that switch an agent's model, mode or thinking level,
	## those named, each with the type Paseo answers it with (see
	## `accepted`): one `agent.config.apply.request` where Paseo has the
	## feature, else one single request for each, the model first, since
	## its thinking levels are the model's.
	configure_requests : Features, Str, { model : Try(Str, [Missing]), mode : Try(Str, [Missing]), thinking : Try(Str, [Missing]) }, Str -> List({ request : Str, answer : Str, request_id : Str })
	configure_requests = |features, agent_id, { model, mode, thinking }, request_id| {
		if features.agent_config_apply {
			[{ request: Json.to_str({ type: "session", message: { type: "agent.config.apply.request", agentId: agent_id, requestId: request_id, config: { modelId: model, modeId: mode, thinkingOptionId: thinking } } }), answer: "agent.config.apply.response", request_id }]
		} else {
			single = |chosen, name, build| chosen.map_ok(|id| [{ request: build(id, "${request_id}-${name}"), answer: "set_agent_${name}_response", request_id: "${request_id}-${name}" }]) ?? []
			[]
				.concat(single(model, "model", |id, asked| Json.to_str({ type: "session", message: { type: "set_agent_model_request", agentId: agent_id, requestId: asked, modelId: id } })))
				.concat(single(mode, "mode", |id, asked| Json.to_str({ type: "session", message: { type: "set_agent_mode_request", agentId: agent_id, requestId: asked, modeId: id } })))
				.concat(single(thinking, "thinking", |id, asked| Json.to_str({ type: "session", message: { type: "set_agent_thinking_request", agentId: agent_id, requestId: asked, thinkingOptionId: id } })))
		}
	}

	## The id of the agent an `agent.create.response` says Paseo made.
	created : Str, Str -> Try(Str, [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str)])
	created = |text, request_id| {
		answered : Try({ message : { payload : { agent : Try({ id : Str }, [Null]), error : Try(Str, [Null]) } } }, _)
		answered = Json.parser_camel()(Paseo.write_answer(text, "agent.create.response", request_id)?)
		payload = answered?.message.payload
		match payload.agent {
			Ok({ id }) => Ok(id)
			Err(Null) => Err(Refused(payload.error ?? "Paseo did not start the agent"))
		}
	}

	## The kinds of agent Paseo can start, from its providers that are
	## available (see `agent_kinds`).
	agent_kinds_request : Str -> Str
	agent_kinds_request = |request_id| Json.to_str({ type: "session", message: { type: "list_available_providers_request", requestId: request_id } })

	## The kinds of agent a `list_available_providers_response` answering
	## `request_id` lists as available.
	agent_kinds : Str, Str -> Try(List(Chat.Agent), [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str)])
	agent_kinds = |text, request_id| {
		answered : Try({ message : { payload : { providers : List({ provider : Str, available : Bool }) } } }, _)
		answered = Json.parser_camel()(Paseo.write_answer(text, "list_available_providers_response", request_id)?)
		Ok(answered?.message.payload.providers.keep_if(|listed| listed.available).map(|listed| Chat.agent_kind({ provider: Paseo.provider.id, agent: listed.provider })))
	}

	## Paseo's providers with their models and modes, as Paseo knows them
	## at the time (see `with_choices`).
	providers_snapshot_request : Str -> Str
	providers_snapshot_request = |request_id| Json.to_str({ type: "session", message: { type: "get_providers_snapshot_request", requestId: request_id } })

	## A provider as a `get_providers_snapshot_response` lists it.
	ProviderChoices : { provider : Str, models : Try(List(ProviderModel), [Missing]), modes : Try(List(Chat.Option), [Missing]), default_mode_id : Try(Try(Str, [Null]), [Missing]) }

	ProviderModel : { id : Str, label : Str, is_default : Try(Bool, [Missing]), is_selectable : Try(Bool, [Missing]), context_window_max_tokens : Try(Number, [Missing]), thinking_options : Try(List({ id : Str, label : Str, is_default : Try(Bool, [Missing]) }), [Missing]), default_thinking_option_id : Try(Str, [Missing]) }

	## The kinds of agent `kinds` with the models, thinking levels and modes
	## of each provider a `get_providers_snapshot_response` lists, those a
	## user can pick. A level is the default where the model's
	## `defaultThinkingOptionId` names it, or it says it is.
	with_choices : List(Chat.Agent), Str, Str -> Try(List(Chat.Agent), [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str)])
	with_choices = |kinds, text, request_id| {
		answered : Try({ message : { payload : { entries : List(ProviderChoices) } } }, _)
		answered = Json.parser_camel()(Paseo.write_answer(text, "get_providers_snapshot_response", request_id)?)
		entries = answered?.message.payload.entries
		model = |offered| {
			default_level = offered.default_thinking_option_id ?? ""
			{
				id: offered.id,
				label: offered.label,
				default: offered.is_default ?? Bool.False,
				context_max: match offered.context_window_max_tokens {
					Ok(Number(tokens)) => tokens.round_to_u64_try().map_err(|_| Missing)
					_ => Err(Missing)
				},
				thinking: (offered.thinking_options ?? []).map(|level| { id: level.id, label: level.label, default: level.is_default ?? (level.id == default_level) }),
			}
		}
		Ok(
			kinds.map(
				|kind| match entries.find_first(|entry| entry.provider == kind.agent) {
					Ok(entry) => { ..kind, models: entry.models.map_ok(|models| models.keep_if(|offered| offered.is_selectable ?? Bool.True).map(model)), modes: entry.modes, default_mode: entry.default_mode_id.map_ok(|mode| mode.map_err(|_| Missing)) ?? Err(Missing) }
					Err(_) => kind
				},
			),
		)
	}

	## A version 4 UUID, as Paseo takes for an agent's id, from `seed`.
	uuid : Str -> Str
	uuid = |seed| {
		digits = "${Paseo.hex(seed)}${Paseo.hex("${seed}.")}".to_utf8()
		at = |from, length| Str.from_utf8(digits.sublist({ start: from, len: length })) ?? ""
		"${at(0, 8)}-${at(8, 4)}-4${at(13, 3)}-8${at(17, 3)}-${at(20, 12)}"
	}

	## Sixteen hex digits of a 64-bit FNV-1a hash of `seed`, as Paseo's
	## workspace ids hold.
	hex : Str -> Str
	hex = |seed| {
		hash = seed.to_utf8().fold(14695981039346656037.U64, |so_far, byte| so_far.bitwise_xor(byte.to_u64()).times_wrap(1099511628211))
		alphabet = "0123456789abcdef".to_utf8()
		(_, digits) = Str.repeat("x", 16).to_utf8().fold((hash, []), |(rest, so_far), _| (rest // 16, so_far.prepend(alphabet.get(rest % 16) ?? 48)))
		Str.from_utf8(digits) ?? ""
	}

	## Asks for one agent, for its state when a timeline page lacks it.
	agent_request : Str, Str -> Str
	agent_request = |agent_id, request_id| Json.to_str({ type: "session", message: { type: "fetch_agent_request", agentId: agent_id, requestId: request_id } })

	## The agent's state a `fetch_agent_response` answering `request_id` holds,
	## or why Paseo has none.
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

	## The importable sessions a `fetch_recent_provider_sessions_response`
	## answering `request_id` lists, each with its directory.
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
		current_mode_id : Try(Try(Str, [Null]), [Missing]),
		available_modes : Try(List(Chat.Option), [Missing]),
		thinking_option_id : Try(Try(Str, [Null]), [Missing]),
		effective_thinking_option_id : Try(Try(Str, [Null]), [Missing]),
		last_usage : Try(Usage, [Missing]),
		archived_at : Try(Try(Str, [Null]), [Missing]),
		background : Try(Bool, [Missing]),
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
	## running turn started and when it last changed, its mode and the modes
	## it has, the thinking level it runs at and what its last turn used, as
	## far as Paseo does. A background agent, such as one writing a summary
	## (see `PaseoSummaries`), isn't listed.
	## They are in the order of Paseo's MCP `list_agents` (see `listed_order`).
	agents_answer : Str, Str -> Try(List({ session : Chat.Session, directory : Str, workspace_id : Str }), [OtherMessage, InvalidJson(Str), MissingRequiredField(Str)])
	agents_answer = |text, request_id| {
		answered : Try({ message : { payload : { entries : List(Listed) } } }, _)
		answered = Json.parser_camel()(Paseo.answer_to(text, "fetch_agents_response", request_id)?)
		Ok(answered?.message.payload.entries.drop_if(|{ agent, .. }| agent.background == Ok(Bool.True)).sort_with(|left, right| listed_order(left.agent, right.agent)).map(Paseo.listed_session))
	}

	## An agent as Paseo's agent lists list it, with its project's checkout.
	Listed : { agent : ListedAgent, project : Try({ checkout : { current_branch : Try(Try(Str, [Null]), [Missing]) } }, [Missing]) }

	## A listed agent as a chat.v1 session (see `agents_answer`), with the
	## directory and the workspace it works in.
	listed_session : Listed -> { session : Chat.Session, directory : Str, workspace_id : Str }
	listed_session = |{ agent, project }| {
		title = agent.title ?? (Str.from_utf8(agent.id.to_utf8().take_first(7)) ?? agent.id)
		optional = |value| value.map_err(|_| Missing)
		session = {
			..Chat.session({ id: agent.id, provider: "paseo", agent: agent.provider, title, status: Paseo.listed_status(agent) }),
			model: optional(agent.model),
			workspace: Ok({ id: agent.workspace_id, directory: agent.cwd }),
			branch: optional(project.map_ok(|placed| placed.checkout.current_branch ?? Err(Null)) ?? Err(Null)),
			running_since: optional(agent.active_turn.map_ok(|turn| turn.map_ok(|active| active.started_at) ?? Err(Null)) ?? Err(Null)),
			updated: Ok(agent.updated_at),
			mode: optional(agent.current_mode_id ?? Err(Null)),
			thinking: match (agent.effective_thinking_option_id, agent.thinking_option_id) {
				(Ok(Ok(effective)), _) => Ok(effective)
				(_, Ok(Ok(chosen))) => Ok(chosen)
				_ => Err(Missing)
			},
			modes: if ((agent.available_modes ?? []).is_empty()) Err(Missing) else agent.available_modes,
			usage: agent.last_usage.map_ok(Paseo.usage),
			archived: optional(agent.archived_at ?? Err(Null)),
		}
		{ session, directory: agent.cwd, workspace_id: agent.workspace_id ?? "" }
	}

	## Asks for a page of Paseo's agent history, archived agents too, the
	## latest first: those matching `search`, `limit` of them after `cursor`
	## ("" for the first page). Paseo lists the features that offer it as
	## `agentHistorySearch` (see `Features`).
	history_request : { search : Str, cursor : Str, limit : U64 }, Str -> Str
	history_request = |{ search, cursor, limit }, request_id| {
		after : Try(Str, [Missing])
		after = if (cursor.is_empty()) Err(Missing) else Ok(cursor)
		Json.to_str({ type: "session", message: { type: "fetch_agent_history_request", requestId: request_id, filter: { includeArchived: Bool.True }, search, sort: [{ key: "updated_at", direction: "desc" }], page: { limit: U64.min(limit, 200), cursor: after } } })
	}

	## The agents a `fetch_agent_history_response` answering `request_id`
	## lists, in its order, each with its directory and workspace and when it
	## was archived, and the cursor of the next page, if there is one.
	history_answer : Str, Str -> Try({ agents : List({ session : Chat.Session, directory : Str, workspace_id : Str }), next : Try(Str, [Missing]) }, [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str)])
	history_answer = |text, request_id| {
		answered : Try({ message : { payload : { entries : List(Listed), page_info : { next_cursor : Try(Str, [Null]), has_more : Bool } } } }, _)
		answered = Json.parser_camel()(Paseo.write_answer(text, "fetch_agent_history_response", request_id)?)
		payload = answered?.message.payload
		Ok({ agents: payload.entries.drop_if(|{ agent, .. }| agent.background == Ok(Bool.True)).map(Paseo.listed_session), next: if (payload.page_info.has_more) payload.page_info.next_cursor.map_err(|_| Missing) else Err(Missing) })
	}

	## Unarchives an agent: Paseo's `refresh_agent_request` lists it again and
	## reloads it, and answers with an `agent_refreshed` status (see
	## `refreshed`).
	unarchive_request : Str, Str -> Str
	unarchive_request = |agent_id, request_id| Json.to_str({ type: "session", message: { type: "refresh_agent_request", agentId: agent_id, requestId: request_id } })

	## Whether the status answering `request_id` says Paseo refreshed the
	## agent, or why not.
	refreshed : Str, Str -> Try({}, [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str)])
	refreshed = |text, request_id| Paseo.write_answer(text, "status", request_id).map_ok(|_| {})

	## An agent's `lastUsage` as chat.v1's, its token counts whole.
	usage : Usage -> Chat.Usage
	usage = |used| {
		amount = |field|
			match field {
				Ok(Number(value)) => Ok(value)
				_ => Err(Missing)
			}
		tokens = |field|
			match amount(field) {
				Ok(value) => value.round_to_u64_try().map_err(|_| Missing)
				Err(Missing) => Err(Missing)
			}
		{ context_used: tokens(used.context_window_used_tokens), context_max: tokens(used.context_window_max_tokens), input_tokens: tokens(used.input_tokens), cached_input_tokens: tokens(used.cached_input_tokens), output_tokens: tokens(used.output_tokens), cost_usd: amount(used.total_cost_usd) }
	}

	## The ids of the `count` sessions that changed last, by `updated`, the
	## latest first: those whose timelines the daemon keeps fresh for
	## attention, though no client watches them.
	newest : List(Chat.Session), U64 -> List(Str)
	newest = |sessions, count| sessions.sort_with(|left, right| compared(moment(right.updated ?? ""), moment(left.updated ?? ""))).take_first(count).map(|session| session.id)

	## A listed agent's status, from its state and what Paseo says it needs
	## attention for.
	listed_status : ListedAgent -> Chat.Status
	listed_status = |agent|
		match (agent.attention_reason, Paseo.chat_status({ status: agent.status, pending_permissions: agent.pending_permissions, last_error: agent.last_error, updated_at: Ok(agent.updated_at), active_turn: agent.active_turn })) {
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

	## An agent's chat.v1 status, from its state: awaiting permission while a
	## request is pending.
	chat_status : Snapshot -> Chat.Status
	chat_status = |{ status: paseo_status, pending_permissions, last_error, .. }|
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

	## Where a Paseo host's target, `host:port`, says Paseo listens: its host,
	## a bracketed IPv6 address unbracketed, and its port.
	address : Str -> Try({ host : Str, port : U16 }, [NotAnAddress])
	address = |target|
		match target.split_last(":") {
			Ok({ before, after }) if before != "" =>
				match U16.from_str(after) {
					Ok(port) if port > 0 => Ok({ host: before.drop_prefix("[").drop_suffix("]"), port })
					_ => Err(NotAnAddress)
				}
			_ => Err(NotAnAddress)
		}

	## The WebSocket protocol that carries the password when Paseo is reached
	## directly. Paseo 0.15 still takes it there, until 2027-03.
	protocol : Str -> Str
	protocol = |password| "paseo.bearer.${password}"

	## What liton uses of the features a Paseo's `server_info` lists:
	## whether it applies an agent's config in one request (from 0.3.2), and
	## whether it searches its agent history (from 0.3.0), and whether it runs
	## agents in the background, hidden from lists (from 0.15.0), as summaries
	## need (see `PaseoSummaries`); and the version it tells, if it does.
	Features : { agent_config_apply : Bool, agent_history_search : Bool, background_agents : Bool, version : Try(Str, [Missing]) }

	## What a message after `hello` says of it: Paseo welcomes a client with
	## its `server_info` and its features, or refuses it with
	## `hello.rejected` and a reason.
	greeting : Str -> [Welcomed(Features), Rejected(Str), NotGreeting]
	greeting = |text| {
		parsed : Try({ type : Str, reason : Try(Str, [Missing]), message : Try({ type : Str, payload : Try({ status : Try(Str, [Missing]), version : Try(Str, [Missing]), features : Try({ agent_config_apply : Try(Bool, [Missing]), agent_history_search : Try(Bool, [Missing]), background_agents : Try(Bool, [Missing]) }, [Missing]) }, [Missing]) }, [Missing]) }, _)
		parsed = Json.parser_camel()(text)
		match parsed {
			Ok({ type: "hello.rejected", reason, .. }) => Rejected(reason ?? "")
			Ok({ message: Ok({ type: "status", payload: Ok({ status: Ok("server_info"), version, features }) }), .. }) => Welcomed({ version, agent_config_apply: features.map_ok(|listed| listed.agent_config_apply ?? Bool.False) ?? Bool.False, agent_history_search: features.map_ok(|listed| listed.agent_history_search ?? Bool.False) ?? Bool.False, background_agents: features.map_ok(|listed| listed.background_agents ?? Bool.False) ?? Bool.False })
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
	##   an answer liton didn't give counts as allowed (see `forget_answered`);
	## - a turn's end before a user message that follows it, and once the
	##   agent stopped working;
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
			{ through: start, open_calls: state.open_calls, events: [], holding: Err(NotHolding), turn: state.turn },
			|walk, (entry, is_final)| timed_step(walk, entry, is_final),
		)
		working = status == Running or status == AwaitingPermission
		active = snapshot.active_turn.map_ok(|turn| turn.map_ok(|active_now| active_now.started_at) ?? Err(Null)) ?? Err(Null)
		turn =
			match (walked.turn, active) {
				(Err(Missing), Ok(started)) if working => Ok({ started: Ok(started), last: started })
				(open, _) => open
			}
		# A turn seen working ended about when the agent last changed; one
		# first seen over, at its last entry.
		was_working = state.status == Running or state.status == AwaitingPermission
		ended =
			match turn {
				Ok(open) if !working => [TurnEnded({ started: open.started, ended: if (was_working) snapshot.updated_at ?? open.last else open.last })]
				_ => []
			}
		cursor =
			match walked.holding {
				Ok(seq_start) => seq_start - 1
				Err(NotHolding) => page.end_cursor.map_ok(|end| end.seq) ?? (if (replayed) 0 else state.cursor)
			}
		ids = snapshot.pending_permissions.map(|permission| permission.id)
		answers = state.permissions.drop_if(|id| ids.contains(id)).map(|id| PermissionAnswered({ request_id: id, allowed: Bool.True, choice: Err(Missing) }))
		requests =
			snapshot.pending_permissions
				.drop_if(|permission| state.permissions.contains(permission.id))
				.map(|permission| PermissionRequested(Paseo.requested(permission)))
		{
			state: { epoch: page.epoch, cursor, emitted_through: walked.through, open_calls: walked.open_calls, permissions: ids, status, turn: if (working) turn else Err(Missing) },
			events: walked.events.concat(answers).concat(requests).concat(ended).concat(if (status == state.status) [] else [StatusChanged(status)]),
		}
	}

	## Forgets a permission request liton answered itself, once Paseo took the
	## answer (`resolved`), so `update` doesn't
	## emit an answer for it; the daemon records the real one.
	forget_answered : State, Str -> State
	forget_answered = |state, request_id| { ..state, permissions: state.permissions.drop_if(|id| id == request_id) }
}

Walk : { through : U64, open_calls : List(Str), events : List(Chat.Event), holding : Try(U64, [NotHolding]), turn : Try(Paseo.Turn, [Missing]) }

## A step that also follows the turns: a new user message ends the turn
## before it, if any, at its last entry, and starts its own; any other new
## entry goes on the turn, or one whose start liton didn't see.
timed_step : Walk, Paseo.Entry, Bool -> [Continue(Walk), Break(Walk)]
timed_step = |walk, entry, is_final| {
	fresh = entry.seq_start > walk.through
	at = entry.timestamp ?? ""
	asked = fresh and entry.item.type == "user_message"
	before =
		match walk.turn {
			Ok(open) if asked => { ..walk, events: walk.events.append(TurnEnded({ started: open.started, ended: open.last })), turn: Err(Missing) }
			_ => walk
		}
	match step(before, entry, is_final) {
		Continue(next) if fresh and at != "" => Continue({ ..next, turn: Ok({ started: next.turn.map_ok(|open| open.started) ?? (if (asked) Ok(at) else Err(Missing)), last: at }) })
		stepped => stepped
	}
}

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
	wants = |agent| if (agent.requires_attention ?? Bool.False) 0 else 1
	rank = |agent| ["running", "initializing", "idle", "error", "closed"].find_first_index(|status| status == agent.status) ?? 5
	[compared(wants(left), wants(right)), compared(rank(left), rank(right)), compared(active_at(right), active_at(left))].find_first(|order| order != Same) ?? Same
}

compared : U64, U64 -> [Before, After, Same]
compared = |earlier, later| if (earlier < later) Before else if (earlier > later) After else Same

## When an agent was last active, the latest of its timestamps.
active_at : Paseo.ListedAgent -> U64
active_at = |agent| [Ok(agent.created_at), Ok(agent.updated_at), agent.last_user_message_at, agent.attention_timestamp ?? Err(Null)].keep_oks(|timestamp| timestamp).map(moment).fold(0, |latest, at| if (at > latest) at else latest)

## A timestamp as its digits, which order as it does: Paseo writes them all
## as `2026-01-01T00:00:00.000Z`. None is 0, the oldest.
moment : Str -> U64
moment = |timestamp| timestamp.to_utf8().keep_if(|byte| byte >= '0' and byte <= '9').fold(0, |number, digit| number * 10 + (digit - '0').to_u64())

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
	\\{"provider":"claude","item":${item},"timestamp":"2026-01-01T00:00:0${seq_start.to_str()}.000Z","seqStart":${seq_start.to_str()},"seqEnd":${seq_start.to_str()},"sourceSeqRanges":[],"collapsed":[]}

shell : Str, Str, Str -> Str
shell = |call_id, status, output|
	\\{"type":"tool_call","callId":"${call_id}","name":"Bash","status":"${status}","error":null,"detail":{"type":"shell","command":"rg -n load_config","exitCode":null${output}}}

response : { epoch : Str, reset : Str, end : Str, status : Str, permissions : Str, entries : List(Str) } -> Str
response = |{ epoch, reset, end, status, permissions, entries }|
	\\{"type":"session","message":{"type":"fetch_agent_timeline_response","payload":{"requestId":"r1","agentId":"a1",
	\\"agent":{"id":"a1","provider":"claude","status":"${status}","updatedAt":"2026-01-01T00:00:30.000Z","pendingPermissions":[${permissions}],"capabilities":{"supportsStreaming":true},"title":null,"labels":{}},
	\\"direction":"after","projection":"projected","epoch":"${epoch}","reset":${reset},"staleCursor":${reset},"gap":false,"window":{"minSeq":1,"maxSeq":9,"nextSeq":10},
	\\"startCursor":null,"endCursor":${end},"hasOlder":false,"hasNewer":false,"entries":[${Str.join_with(entries, ",")}],"error":null}}}

## Fetches a page and updates with its agent, as the daemon would.
fetched : Paseo.State, Str -> { state : Paseo.State, events : List(Chat.Event) }
fetched = |state, text|
	match Paseo.timeline_page(text, "r1") {
		Ok(page) => Paseo.update(state, page, page.agent ?? { status: "", pending_permissions: [], last_error: Err(Missing), updated_at: Err(Missing), active_turn: Err(Missing) })
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
expect first.state == { epoch: "e1", cursor: 3, emitted_through: 2, open_calls: ["c1"], permissions: [], status: Running, turn: Ok({ started: Ok("2026-01-01T00:00:01.000Z"), last: "2026-01-01T00:00:02.000Z" }) }
expect second.events == [ToolResult({ call_id: "c1", output: "src/Config.roc:3", failed: Bool.False }), AgentMessage({ text: "Renaming it: done." }), TurnEnded({ started: Ok("2026-01-01T00:00:01.000Z"), ended: "2026-01-01T00:00:30.000Z" }), StatusChanged(Idle)]
expect second.state == { epoch: "e1", cursor: 6, emitted_through: 4, open_calls: [], permissions: [], status: Idle, turn: Err(Missing) }
expect asked.events == [PermissionRequested(Chat.permission({ request_id: "p1", tool: "Edit", description: "Edit src/Config.roc" })), StatusChanged(AwaitingPermission)]
expect asked.state.cursor == 6
expect answered_elsewhere([]).events == [PermissionAnswered({ request_id: "p1", allowed: Bool.True, choice: Err(Missing) }), StatusChanged(Running)]

# A plan to approve, as Claude asks it in Paseo 0.15: the plan as the body, Paseo's actions as the choices.
expect {
	plan = "{\"id\":\"permission-1\",\"provider\":\"claude\",\"name\":\"ExitPlanMode\",\"kind\":\"plan\",\"title\":\"Plan\",\"input\":{\"plan\":\"## Plan\\n1. Rename it\",\"allowedPrompts\":[{\"tool\":\"Bash\"}]},\"actions\":[{\"id\":\"reject\",\"label\":\"Reject\",\"behavior\":\"deny\",\"variant\":\"danger\",\"intent\":\"dismiss\"},{\"id\":\"implement\",\"label\":\"Implement\",\"behavior\":\"allow\",\"variant\":\"primary\",\"intent\":\"implement\"},{\"id\":\"implement_resume\",\"label\":\"Implement with Auto\",\"behavior\":\"allow\",\"intent\":\"implement_resume\"}],\"metadata\":{\"toolUseId\":\"t1\",\"planText\":\"## Plan\\n1. Rename it\"}}"
	planned = fetched(second.state, response({ epoch: "e1", reset: "false", end: "null", status: "running", permissions: plan, entries: [] }))
	choices = [{ id: "reject", label: "Reject", allows: Bool.False, style: Danger }, { id: "implement", label: "Implement", allows: Bool.True, style: Primary }, { id: "implement_resume", label: "Implement with Auto", allows: Bool.True, style: Secondary }]
	planned.events.first() == Ok(PermissionRequested({ ..Chat.permission({ request_id: "permission-1", tool: "ExitPlanMode", description: "Plan" }), body: Ok("## Plan\n1. Rename it"), choices: Ok(choices) }))
}
expect fetched(Paseo.forget_answered(asked.state, "p1"), response({ epoch: "e1", reset: "false", end: "null", status: "running", permissions: "", entries: [] })).events == [StatusChanged(Running)]

# An idle agent's history: each turn ends before the next one's message, and the last at its last entry.
expect {
	said = |text| "{\"type\":\"assistant_message\",\"text\":\"${text}\"}"
	prompted = |text| "{\"type\":\"user_message\",\"text\":\"${text}\"}"
	history = fetched(Paseo.initial, response({ epoch: "e1", reset: "false", end: "{\"epoch\":\"e1\",\"seq\":4}", status: "idle", permissions: "", entries: [entry(1, prompted("Hi")), entry(2, said("Hello")), entry(3, prompted("Bye")), entry(4, said("Bye"))] }))
	history.events
		== [UserMessage({ text: "Hi" }), AgentMessage({ text: "Hello" }), TurnEnded({ started: Ok("2026-01-01T00:00:01.000Z"), ended: "2026-01-01T00:00:02.000Z" }), UserMessage({ text: "Bye" }), AgentMessage({ text: "Bye" }), TurnEnded({ started: Ok("2026-01-01T00:00:03.000Z"), ended: "2026-01-01T00:00:04.000Z" })]
		and history.state.turn == Err(Missing)
}

# A turn no message started, as Paseo's active turn tells it, ends once the agent stops.
expect {
	working = response({ epoch: "e1", reset: "false", end: "null", status: "running", permissions: "", entries: [] }).replace_first("\"status\":\"running\",", "\"status\":\"running\",\"activeTurn\":{\"turnId\":\"t2\",\"startedAt\":\"2026-01-01T00:00:20.000Z\"},")
	started = fetched(second.state, working)
	stopped = fetched(started.state, response({ epoch: "e1", reset: "false", end: "null", status: "idle", permissions: "", entries: [] }))
	started.events == [StatusChanged(Running)] and stopped.events == [TurnEnded({ started: Ok("2026-01-01T00:00:20.000Z"), ended: "2026-01-01T00:00:30.000Z" }), StatusChanged(Idle)]
}

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
	replayed.events == [ToolResult({ call_id: "c1", output: "", failed: Bool.True }), TurnEnded({ started: Ok("2026-01-01T00:00:01.000Z"), ended: "2026-01-01T00:00:30.000Z" }), StatusChanged(Idle)] and replayed.state.cursor == 3 and replayed.state.epoch == "e2"
}

expect Paseo.timeline_page("{\"type\":\"session\",\"message\":{\"type\":\"status\",\"payload\":{\"status\":\"server_info\"}}}", "r1").map_ok(|_| {}) == Err(OtherMessage)
expect Paseo.timeline_page("{\"type\":\"pong\"}", "r1").map_ok(|_| {}) == Err(OtherMessage)
expect Paseo.answers_request(response({ epoch: "e1", reset: "false", end: "null", status: "idle", permissions: "", entries: [] }), "r1")
expect !Paseo.answers_request(response({ epoch: "e1", reset: "false", end: "null", status: "idle", permissions: "", entries: [] }), "r2")
expect !Paseo.answers_request("{\"type\":\"session\",\"message\":{\"type\":\"status\",\"payload\":{\"status\":\"server_info\"}}}", "r1")
expect !Paseo.answers_request("{\"type\":\"pong\"}", "r1")

expect {
	not_git = "\"cwd\":\"/work\",\"isGit\":false,\"currentBranch\":null,\"remoteUrl\":null,\"isPaseoOwnedWorktree\":false,\"mainRepoRoot\":null"
	agent = |fields, checkout| "{\"agent\":{\"provider\":\"claude\",\"cwd\":\"/work\",\"createdAt\":\"2026-01-01T00:00:00.000Z\",\"lastUserMessageAt\":null,\"capabilities\":{},\"persistence\":null,\"labels\":{},${fields}},\"project\":{\"projectKey\":\"p1\",\"projectName\":\"app\",\"checkout\":{${checkout}}}}"
	entries = [
		agent("\"id\":\"a1b2c3d4e5\",\"model\":\"opus\",\"thinkingOptionId\":null,\"effectiveThinkingOptionId\":\"high\",\"currentModeId\":\"plan\",\"availableModes\":[{\"id\":\"default\",\"label\":\"Default\",\"icon\":\"shield\"},{\"id\":\"plan\",\"label\":\"Plan\"}],\"lastUsage\":{\"inputTokens\":1200,\"outputTokens\":300,\"totalCostUsd\":0.0125,\"contextWindowMaxTokens\":200000,\"contextWindowUsedTokens\":41000.0},\"activeTurn\":{\"turnId\":\"t1\",\"startedAt\":\"2026-01-01T00:01:00.000Z\"},\"updatedAt\":\"2026-01-01T00:00:00.000Z\",\"workspaceId\":\"w1\",\"title\":null,\"status\":\"running\",\"pendingPermissions\":[]", "\"cwd\":\"/work\",\"isGit\":true,\"currentBranch\":\"fix-login\",\"remoteUrl\":null,\"isPaseoOwnedWorktree\":false,\"mainRepoRoot\":null"),
		agent("\"id\":\"a3\",\"model\":null,\"currentModeId\":null,\"availableModes\":[],\"activeTurn\":null,\"updatedAt\":\"2026-01-01T00:00:00.000Z\",\"workspaceId\":\"w1\",\"title\":\"Done\",\"status\":\"idle\",\"pendingPermissions\":[],\"requiresAttention\":true,\"attentionReason\":\"finished\"", not_git),
		agent("\"id\":\"a4\",\"model\":null,\"updatedAt\":\"2026-01-02T00:00:00.000Z\",\"title\":\"Asks\",\"status\":\"running\",\"pendingPermissions\":[{\"id\":\"p1\",\"provider\":\"claude\",\"name\":\"Edit\",\"kind\":\"tool\"}]", not_git),
		agent("\"id\":\"a5\",\"model\":\"haiku\",\"updatedAt\":\"2026-01-02T00:00:00.000Z\",\"title\":\"liton summary\",\"status\":\"idle\",\"pendingPermissions\":[],\"background\":true", not_git),
	]
	text = "{\"type\":\"session\",\"message\":{\"type\":\"fetch_agents_response\",\"payload\":{\"requestId\":\"r1\",\"entries\":[${Str.join_with(entries, ",")}],\"pageInfo\":{\"nextCursor\":null,\"prevCursor\":null,\"hasMore\":false}}}}"
	listed = |id, title, status, workspace_id, updated| { ..Chat.session({ id, provider: "paseo", agent: "claude", title, status }), workspace: Ok({ id: workspace_id, directory: "/work" }), updated: Ok(updated) }
	Paseo.agents_answer(text, "r1")
		== Ok([
			{ session: listed("a3", "Done", Finished, Ok("w1"), "2026-01-01T00:00:00.000Z"), directory: "/work", workspace_id: "w1" },
			{ session: listed("a4", "Asks", AwaitingPermission, Err(Missing), "2026-01-02T00:00:00.000Z"), directory: "/work", workspace_id: "" },
			{ session: { ..listed("a1b2c3d4e5", "a1b2c3d", Running, Ok("w1"), "2026-01-01T00:00:00.000Z"), model: Ok("opus"), branch: Ok("fix-login"), running_since: Ok("2026-01-01T00:01:00.000Z"), mode: Ok("plan"), thinking: Ok("high"), modes: Ok([{ id: "default", label: "Default" }, { id: "plan", label: "Plan" }]), usage: Ok({ context_used: Ok(41_000), context_max: Ok(200_000), input_tokens: Ok(1_200), cached_input_tokens: Err(Missing), output_tokens: Ok(300), cost_usd: Ok(0.0125) }) }, directory: "/work", workspace_id: "w1" },
		])
		and Paseo.agents_answer(text, "r2").map_ok(|_| {}) == Err(OtherMessage)
}

expect {
	history_entry = |id, archived| "{\"agent\":{\"id\":\"${id}\",\"provider\":\"codex\",\"cwd\":\"/work\",\"model\":null,\"createdAt\":\"2026-01-01T00:00:00.000Z\",\"updatedAt\":\"2026-01-02T00:00:00.000Z\",\"lastUserMessageAt\":null,\"title\":\"${id}\",\"status\":\"closed\",\"pendingPermissions\":[],\"archivedAt\":${archived}},\"project\":{\"projectKey\":\"p1\",\"projectName\":\"app\",\"checkout\":{\"cwd\":\"/work\",\"isGit\":false,\"currentBranch\":null}}}"
	page = |more, cursor| session("{\"type\":\"fetch_agent_history_response\",\"payload\":{\"requestId\":\"h1\",\"entries\":[${history_entry("a9", "\"2026-01-03T00:00:00.000Z\"")},${history_entry("a8", "null")}],\"pageInfo\":{\"nextCursor\":${cursor},\"prevCursor\":null,\"hasMore\":${more}}}}")
	shown = |id, archived| { session: { ..Chat.session({ id, provider: "paseo", agent: "codex", title: id, status: Finished }), workspace: Ok({ id: Err(Missing), directory: "/work" }), updated: Ok("2026-01-02T00:00:00.000Z"), archived }, directory: "/work", workspace_id: "" }
	Paseo.history_answer(page("true", "\"c2\""), "h1") == Ok({ agents: [shown("a9", Ok("2026-01-03T00:00:00.000Z")), shown("a8", Err(Missing))], next: Ok("c2") })
		and Paseo.history_answer(page("false", "null"), "h1").map_ok(|answered| answered.next) == Ok(Err(Missing))
		and Paseo.history_request({ search: "login", cursor: "", limit: 500 }, "h1") == request("{\"filter\":{\"includeArchived\":true},\"page\":{\"limit\":200},\"requestId\":\"h1\",\"search\":\"login\",\"sort\":[{\"direction\":\"desc\",\"key\":\"updated_at\"}],\"type\":\"fetch_agent_history_request\"}")
		and Paseo.refreshed(session("{\"type\":\"status\",\"payload\":{\"status\":\"agent_refreshed\",\"agentId\":\"a9\",\"requestId\":\"u1\",\"timelineSize\":4}}"), "u1") == Ok({})
		and Paseo.refreshed(session("{\"type\":\"rpc_error\",\"payload\":{\"requestId\":\"u1\",\"requestType\":\"refresh_agent_request\",\"error\":\"Agent not found: a9\"}}"), "u1") == Err(Refused("Agent not found: a9"))
}

# The sessions that changed last, a session telling no time the oldest.
expect {
	changed = |id, updated| { ..Chat.session({ id, provider: "paseo", agent: "claude", title: id, status: Idle }), updated }
	sessions = [changed("a1", Err(Missing)), changed("a2", Ok("2026-01-02T00:00:00.000Z")), changed("a3", Ok("2026-01-01T09:00:00.000Z")), changed("a4", Ok("2026-01-03T00:00:00.000Z"))]
	Paseo.newest(sessions, 2) == ["a4", "a2"] and Paseo.newest(sessions, 9) == ["a4", "a2", "a3", "a1"] and Paseo.newest([], 3) == []
}

session : Str -> Str
session = |message| "{\"type\":\"session\",\"message\":${message}}"

## A request as liton writes it: Json.to_str orders fields by name.
request : Str -> Str
request = |message| "{\"message\":${message},\"type\":\"session\"}"

expect Paseo.permission_answer("a1", "p1", Bool.False, Err(Missing)) == request("{\"agentId\":\"a1\",\"requestId\":\"p1\",\"response\":{\"behavior\":\"deny\"},\"type\":\"agent_permission_response\"}")
expect Paseo.permission_answer("a1", "p1", Bool.True, Ok("implement")) == request("{\"agentId\":\"a1\",\"requestId\":\"p1\",\"response\":{\"behavior\":\"allow\",\"selectedActionId\":\"implement\"},\"type\":\"agent_permission_response\"}")
expect Paseo.send_request("a1", "Go on", Err(Missing), [], "w1") == request("{\"agentId\":\"a1\",\"requestId\":\"w1\",\"text\":\"Go on\",\"type\":\"send_agent_message_request\"}")
expect Paseo.send_request("a1", "Also the docs", Ok(Steer), [], "w1") == request("{\"activeTurnBehavior\":\"steer\",\"agentId\":\"a1\",\"requestId\":\"w1\",\"text\":\"Also the docs\",\"type\":\"send_agent_message_request\"}")
expect {
	sent = Paseo.send_request("a1", "See", Err(Missing), [Image({ name: "shot.png", mime_type: "image/png", data: "aGk=" }), Text({ name: "notes.md", text: "# Notes" })], "w1")
	sent.contains("\"images\":[{\"data\":\"aGk=\",\"mimeType\":\"image/png\"}]") and sent.contains("\"attachments\":[{\"mimeType\":\"text/plain\",\"text\":\"# Notes\",\"title\":\"notes.md\",\"type\":\"text\"}]")
}

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

expect Paseo.rename_request("a1", "Fix login", "u1") == request("{\"agentId\":\"a1\",\"name\":\"Fix login\",\"requestId\":\"u1\",\"type\":\"update_agent_request\"}")
expect Paseo.archive_request("a1", "x1") == request("{\"agentId\":\"a1\",\"requestId\":\"x1\",\"type\":\"archive_agent_request\"}")

expect {
	answer = |fields| session("{\"type\":\"update_agent_response\",\"payload\":{\"requestId\":\"u1\",\"agentId\":\"a1\",${fields}}}")
	Paseo.accepted(answer("\"accepted\":true,\"error\":null"), "update_agent_response", "u1") == Ok({})
		and Paseo.accepted(answer("\"accepted\":false,\"error\":\"Agent a1 not found\""), "update_agent_response", "u1") == Err(Refused("Agent a1 not found"))
		and Paseo.accepted(answer("\"accepted\":false"), "update_agent_response", "u1") == Err(Refused("Paseo did not take the change"))
		and Paseo.accepted(answer("\"accepted\":true,\"error\":null"), "update_agent_response", "u2") == Err(OtherMessage)
}

expect {
	archived = session("{\"type\":\"agent_archived\",\"payload\":{\"agentId\":\"a1\",\"archivedAt\":\"2026-01-01T00:00:00.000Z\",\"requestId\":\"x1\"}}")
	failure = session("{\"type\":\"rpc_error\",\"payload\":{\"requestId\":\"x1\",\"requestType\":\"archive_agent_request\",\"error\":\"Agent not found: a9\",\"code\":\"handler_error\"}}")
	Paseo.archived(archived, "x1") == Ok({}) and Paseo.archived(failure, "x1") == Err(Refused("Agent not found: a9")) and Paseo.archived(archived, "x2") == Err(OtherMessage)
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

expect Paseo.greeting(session("{\"type\":\"status\",\"payload\":{\"status\":\"server_info\",\"serverId\":\"s1\",\"version\":\"0.15.3\"}}")) == Welcomed({ agent_config_apply: Bool.False, agent_history_search: Bool.False, background_agents: Bool.False, version: Ok("0.15.3") })
expect Paseo.greeting(session("{\"type\":\"status\",\"payload\":{\"status\":\"server_info\",\"serverId\":\"s1\",\"features\":{\"agentRequestReceipts\":true,\"agentConfigApply\":true,\"backgroundAgents\":true,\"agentHistorySearch\":true}}}")) == Welcomed({ agent_config_apply: Bool.True, agent_history_search: Bool.True, background_agents: Bool.True, version: Err(Missing) })

# One request where Paseo applies a config at once, else one for each change.
expect {
	changes = { model: Ok("opus"), mode: Err(Missing), thinking: Ok("high") }
	Paseo.configure_requests({ agent_config_apply: Bool.True, agent_history_search: Bool.False, background_agents: Bool.False, version: Err(Missing) }, "a1", changes, "c1") == [{ request: request("{\"agentId\":\"a1\",\"config\":{\"modelId\":\"opus\",\"thinkingOptionId\":\"high\"},\"requestId\":\"c1\",\"type\":\"agent.config.apply.request\"}"), answer: "agent.config.apply.response", request_id: "c1" }]
		and Paseo.configure_requests({ agent_config_apply: Bool.False, agent_history_search: Bool.False, background_agents: Bool.False, version: Err(Missing) }, "a1", changes, "c1") == [{ request: request("{\"agentId\":\"a1\",\"modelId\":\"opus\",\"requestId\":\"c1-model\",\"type\":\"set_agent_model_request\"}"), answer: "set_agent_model_response", request_id: "c1-model" }, { request: request("{\"agentId\":\"a1\",\"requestId\":\"c1-thinking\",\"thinkingOptionId\":\"high\",\"type\":\"set_agent_thinking_request\"}"), answer: "set_agent_thinking_response", request_id: "c1-thinking" }]
}
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

expect {
	id = Paseo.uuid("liton-create-1")
	parts = id.split_on("-").map(|part| part.count_utf8_bytes())
	parts == [8, 4, 4, 4, 12] and id.split_on("-").get(2).map_ok(|part| part.starts_with("4")) == Ok(Bool.True) and Paseo.uuid("liton-create-1") == id and Paseo.uuid("liton-create-2") != id and Paseo.hex("").count_utf8_bytes() == 16
}

expect
	Paseo.create_request({ agent_id: "a1", agent: "claude", cwd: "/src/app", workspace_id: Ok("wks_1"), model: Err(Missing), mode: Err(Missing), thinking: Err(Missing), prompt: "", request_id: "r1" })
		== "{\"message\":{\"agentId\":\"a1\",\"config\":{\"cwd\":\"/src/app\",\"provider\":\"claude\"},\"idempotencyKey\":\"a1\",\"requestId\":\"r1\",\"type\":\"agent.create.request\",\"workspaceId\":\"wks_1\"},\"type\":\"session\"}"
		and Paseo.create_request({ agent_id: "a1", agent: "claude", cwd: "/src/app", workspace_id: Err(Missing), model: Ok("opus"), mode: Ok("plan"), thinking: Ok("high"), prompt: "", request_id: "r1" })
			== "{\"message\":{\"agentId\":\"a1\",\"config\":{\"cwd\":\"/src/app\",\"modeId\":\"plan\",\"model\":\"opus\",\"provider\":\"claude\",\"thinkingOptionId\":\"high\"},\"idempotencyKey\":\"a1\",\"requestId\":\"r1\",\"type\":\"agent.create.request\"},\"type\":\"session\"}"

expect {
	made = "{\"type\":\"session\",\"message\":{\"type\":\"agent.create.response\",\"payload\":{\"requestId\":\"r1\",\"agent\":{\"id\":\"a1\",\"provider\":\"claude\"},\"error\":null}}}"
	refused = "{\"type\":\"session\",\"message\":{\"type\":\"agent.create.response\",\"payload\":{\"requestId\":\"r1\",\"agent\":null,\"error\":\"Unknown provider\"}}}"
	Paseo.created(made, "r1") == Ok("a1") and Paseo.created(refused, "r1") == Err(Refused("Unknown provider")) and Paseo.created(made, "r2") == Err(OtherMessage)
}

expect Paseo.agent_kinds("{\"type\":\"session\",\"message\":{\"type\":\"list_available_providers_response\",\"payload\":{\"requestId\":\"r1\",\"fetchedAt\":\"x\",\"providers\":[{\"provider\":\"claude\",\"available\":true},{\"provider\":\"codex\",\"available\":false,\"error\":\"not installed\"}]}}}", "r1") == Ok([Chat.agent_kind({ provider: "paseo", agent: "claude" })])

expect {
	kinds = [Chat.agent_kind({ provider: "paseo", agent: "claude" }), Chat.agent_kind({ provider: "paseo", agent: "codex" })]
	text = session("{\"type\":\"get_providers_snapshot_response\",\"payload\":{\"requestId\":\"r1\",\"generatedAt\":\"x\",\"entries\":[{\"provider\":\"claude\",\"status\":\"ready\",\"models\":[{\"provider\":\"claude\",\"id\":\"opus\",\"label\":\"Opus\",\"isDefault\":true,\"contextWindowMaxTokens\":200000,\"thinkingOptions\":[{\"id\":\"low\",\"label\":\"Low\"},{\"id\":\"high\",\"label\":\"High\"}],\"defaultThinkingOptionId\":\"high\"},{\"provider\":\"claude\",\"id\":\"old\",\"label\":\"Old\",\"isSelectable\":false}],\"modes\":[{\"id\":\"plan\",\"label\":\"Plan\",\"icon\":\"map\"}],\"defaultModeId\":\"plan\"},{\"provider\":\"pi\",\"status\":\"loading\"}]}}")
	claude = { ..Chat.agent_kind({ provider: "paseo", agent: "claude" }), models: Ok([{ id: "opus", label: "Opus", default: Bool.True, context_max: Ok(200_000), thinking: [{ id: "low", label: "Low", default: Bool.False }, { id: "high", label: "High", default: Bool.True }] }]), modes: Ok([{ id: "plan", label: "Plan" }]), default_mode: Ok("plan") }
	Paseo.with_choices(kinds, text, "r1") == Ok([claude, Chat.agent_kind({ provider: "paseo", agent: "codex" })])
		and Paseo.with_choices(kinds, text, "r2").map_ok(|_| {}) == Err(OtherMessage)
}

expect Paseo.address("127.0.0.1:6767") == Ok({ host: "127.0.0.1", port: 6767 }) and Paseo.address("[::1]:6767") == Ok({ host: "::1", port: 6767 }) and Paseo.address("::1:6767") == Ok({ host: "::1", port: 6767 })
expect ["127.0.0.1", ":6767", "box:0", "box:http"].all(|target| Paseo.address(target) == Err(NotAnAddress))

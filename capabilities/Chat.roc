## `chat.v1`: agent sessions as a timeline of events. The UI lists sessions,
## watches one session's timeline from a sequence number on, sends messages,
## answers the agent's permission requests, and stops a running agent.
Chat := [].{

	## Where a session is: idle, running, waiting for an answer to a permission
	## request, finished, or failed with why.
	Status : [Idle, Running, AwaitingPermission, Finished, Failed(Str)]

	## Beyond its status, what a provider tells of a session, each left out
	## when it doesn't: the model it runs, the directory it works in (with its
	## workspace's id when the provider has one) and the branch checked out
	## there, when its running turn started and when it last changed, as times
	## such as 2026-01-01T09:00:00.000Z. Then the mode it works in and its
	## thinking level, by their ids, the modes it can switch to, what its
	## last turn used, a summary of its work so far, and when it was
	## archived, if it was.
	Session : {
		id : Str,
		provider : Str,
		agent : Str,
		title : Str,
		status : Status,
		model : Try(Str, [Missing]),
		workspace : Try({ id : Try(Str, [Missing]), directory : Str }, [Missing]),
		branch : Try(Str, [Missing]),
		running_since : Try(Str, [Missing]),
		updated : Try(Str, [Missing]),
		mode : Try(Str, [Missing]),
		thinking : Try(Str, [Missing]),
		modes : Try(List(Option), [Missing]),
		usage : Try(Usage, [Missing]),
		summary : Try(Summary, [Missing]),
		archived : Try(Str, [Missing]),
	}

	## A session's work in three sentences, as a small model wrote it after
	## its last turn: what it is for (`goal`), what it has done (`done`) and
	## what happens now (`now`), and when its turn ended, as a time such as
	## 2026-01-01T09:00:00.000Z.
	Summary : { goal : Str, done : Str, now : Str, at : Str }

	## A mode an agent works in, such as Claude's plan mode, or another
	## choice a provider names.
	Option : { id : Str, label : Str }

	## What a session's last turn used, each left out when its provider
	## doesn't tell: the tokens of the context window it filled and holds at
	## most, the tokens it read (`cached_input_tokens` of them from a cache)
	## and wrote, and what it cost in US dollars.
	Usage : { context_used : Try(U64, [Missing]), context_max : Try(U64, [Missing]), input_tokens : Try(U64, [Missing]), cached_input_tokens : Try(U64, [Missing]), output_tokens : Try(U64, [Missing]), cost_usd : Try(Dec, [Missing]) }

	## A model an agent can run: whether it is its provider's default, the
	## tokens its context window holds, if told, and its thinking levels.
	Model : { id : Str, label : Str, default : Bool, context_max : Try(U64, [Missing]), thinking : List(Level) }

	## A thinking level of a model, such as low or high.
	Level : { id : Str, label : Str, default : Bool }

	## A permission request: the tool asking and a line of what it would do,
	## then what the provider tells beyond that, each left out otherwise: its
	## `body` as Markdown, such as a plan to approve, and its `choices` when
	## they are its own rather than allow and deny.
	Permission : { request_id : Str, tool : Str, description : Str, body : Try(Str, [Missing]), choices : Try(List(Choice), [Missing]) }

	## One of a permission request's choices, such as a plan's Implement or
	## Reject: whether it allows, and how the provider would show it.
	Choice : { id : Str, label : Str, allows : Bool, style : [Primary, Secondary, Danger] }

	## A permission's answer names the choice taken, when the request offered
	## its own. `TurnEnded` follows the last event of a turn, the agent's
	## work on what it was asked, once it finished, failed or was stopped or
	## interrupted: when the turn started, if the provider tells, and when it
	## ended, as times such as 2026-01-01T09:00:00.000Z.
	Event : [
		UserMessage({ text : Str }),
		AgentMessage({ text : Str }),
		ToolCall({ call_id : Str, tool : Str, input : Str }),
		ToolResult({ call_id : Str, output : Str, failed : Bool }),
		PermissionRequested(Permission),
		PermissionAnswered({ request_id : Str, allowed : Bool, choice : Try(Str, [Missing]) }),
		StatusChanged(Status),
		TurnEnded({ started : Try(Str, [Missing]), ended : Str }),
	]

	## One event in a session's timeline. Sequence numbers start at 1 and
	## increase by 1, so a watcher resumes after the last one it saw.
	Entry : { sequence : U64, event : Event }

	## `WatchSession` answers with a stream of `Entry`, those after `after`
	## first; the others answer with one `Response`. `Create` starts an agent
	## of a kind its provider offers (`Agent`) in a workspace, or in a
	## directory of the provider the call names, with a model and a first
	## prompt ("" for none), and answers `Started` with its session's id.
	## `AnswerPermission` takes one of the request's `choices` by its id, if
	## it offered any, with `allowed` as that choice allows. `Rename` gives a
	## session a title, or with "" the one its provider gives it; `Archive`
	## stops it, if it runs, and lists it no more. A session has no pin of
	## its own: a client pins the workspace it works in (workspaces.v1).
	## `Configure` switches a session's model, mode or thinking level, those
	## it names, at once. A message sent while the agent works on a turn
	## interrupts it, or with `while_running` `Steer` joins it; its
	## `attachments` go with it.
	## `ListHistory` lists sessions, archived ones too, the latest first: those
	## whose title, agent or directory holds `search`, at most `limit` of them
	## from `cursor` on (left out for the first); `Unarchive` lists one again.
	Request : [
		ListSessions,
		WatchSession({ session_id : Str, after : U64 }),
		SendMessage({ session_id : Str, text : Str, while_running : Try([Interrupt, Steer], [Missing]), attachments : Try(List(Attachment), [Missing]) }),
		AnswerPermission({ session_id : Str, request_id : Str, allowed : Bool, choice : Try(Str, [Missing]) }),
		Cancel({ session_id : Str }),
		Create(Create),
		Rename({ session_id : Str, title : Str }),
		Archive({ session_id : Str }),
		Configure({ session_id : Str, model : Try(Str, [Missing]), mode : Try(Str, [Missing]), thinking : Try(Str, [Missing]) }),
		ListHistory({ search : Str, cursor : Try(Str, [Missing]), limit : U64 }),
		Unarchive({ session_id : Str }),
	]

	## A file sent with a message: an image, its bytes in base64, or a text
	## file's text, each with its file's name.
	Attachment : [Image({ name : Str, mime_type : Str, data : Str }), Text({ name : Str, text : Str })]

	## A session to start: where it works (a workspace, or a directory), the
	## agent and, if not their defaults, the model, mode and thinking level,
	## and the first prompt.
	Create : { place : [Workspace(Str), Directory(Str)], agent : Str, model : Try(Str, [Missing]), mode : Try(Str, [Missing]), thinking : Try(Str, [Missing]), prompt : Str }

	## What a request answers: sessions, a timeline's entries, whether the
	## provider took it, the id of a session started, or a page of history
	## with the cursor of the next, left out after the last.
	Response : [Sessions(List(Session)), Entries(List(Entry)), Accepted, Rejected(Str), Started({ session_id : Str }), History({ sessions : List(Session), next : Try(Str, [Missing]) })]

	## A kind of agent a provider can start, such as `claude`, and, when its
	## provider tells, the models and modes it offers and the mode it starts
	## in.
	Agent : { provider : Str, agent : Str, models : Try(List(Model), [Missing]), modes : Try(List(Option), [Missing]), default_mode : Try(Str, [Missing]) }

	## A kind of agent the provider tells nothing more of.
	agent_kind : { provider : Str, agent : Str } -> Agent
	agent_kind = |{ provider, agent }| { provider, agent, models: Err(Missing), modes: Err(Missing), default_mode: Err(Missing) }

	## A session a provider keeps but doesn't run, such as a sandboxed agent's,
	## read only, and the directory it worked in.
	Importable : { session : Session, directory : Str }

	## A session the provider tells nothing more of.
	session : { id : Str, provider : Str, agent : Str, title : Str, status : Status } -> Session
	session = |{ id, provider, agent, title, status }| { id, provider, agent, title, status, model: Err(Missing), workspace: Err(Missing), branch: Err(Missing), running_since: Err(Missing), updated: Err(Missing), mode: Err(Missing), thinking: Err(Missing), modes: Err(Missing), usage: Err(Missing), summary: Err(Missing), archived: Err(Missing) }

	## A permission request the provider tells no more of.
	permission : { request_id : Str, tool : Str, description : Str } -> Permission
	permission = |{ request_id, tool, description }| { request_id, tool, description, body: Err(Missing), choices: Err(Missing) }

	## Whether answering `request_id` in `timeline` as `allowed`, with
	## `choice` if any, is an answer it takes: a choice must be one it offers
	## and allow as it does.
	answerable : List(Entry), Str, Bool, Try(Str, [Missing]) -> Bool
	answerable = |timeline, request_id, allowed, choice| {
		asked = timeline.keep_oks(
			|entry|
				match entry.event {
					PermissionRequested(question) if question.request_id == request_id => Ok(question.choices ?? [])
					_ => Err(Other)
				},
		)
		match choice {
			Err(Missing) => Bool.True
			Ok(id) => asked.any(|choices| choices.any(|offered| offered.id == id and offered.allows == allowed))
		}
	}

	## Milliseconds since the epoch as a time such as 2026-01-01T09:00:00.000Z,
	## by the days-to-civil-date algorithm of Howard Hinnant's chrono notes.
	timestamp : I64 -> Str
	timestamp = |ms| {
		days = ms // 86_400_000 + 719_468
		era = days // 146_097
		day_of_era = days - era * 146_097
		year_of_era = (day_of_era - day_of_era // 1_460 + day_of_era // 36_524 - day_of_era // 146_096) // 365
		day_of_year = day_of_era - (365 * year_of_era + year_of_era // 4 - year_of_era // 100)
		month_index = (5 * day_of_year + 2) // 153
		month = if (month_index < 10) month_index + 3 else month_index - 9
		year = year_of_era + era * 400 + (if (month <= 2) 1 else 0)
		padded = |number, width| {
			digits = number.to_str()
			"${Str.repeat("0", width - digits.count_utf8_bytes())}${digits}"
		}
		of_day = ms % 86_400_000
		"${year.to_str()}-${padded(month, 2)}-${padded(day_of_year - (153 * month_index + 2) // 5 + 1, 2)}T${padded(of_day // 3_600_000, 2)}:${padded(of_day // 60_000 % 60, 2)}:${padded(of_day // 1_000 % 60, 2)}.${padded(of_day % 1_000, 3)}Z"
	}

	## The permission requests in a timeline that no answer follows.
	pending_permissions : List(Entry) -> List(Str)
	pending_permissions = |timeline|
		timeline.fold(
			[],
			|pending, entry|
				match entry.event {
					PermissionRequested({ request_id, .. }) => pending.append(request_id)
					PermissionAnswered({ request_id, .. }) => pending.drop_if(|id| id == request_id)
					_ => pending
				},
		)
}

expect {
	timeline = [
		{ sequence: 1, event: PermissionRequested(Chat.permission({ request_id: "a", tool: "bash", description: "rm -rf build" })) },
		{ sequence: 2, event: PermissionRequested(Chat.permission({ request_id: "b", tool: "edit", description: "README.md" })) },
		{ sequence: 3, event: PermissionAnswered({ request_id: "a", allowed: Bool.True, choice: Err(Missing) }) },
	]
	Chat.pending_permissions(timeline) == ["b"]
}

expect {
	plan = { ..Chat.permission({ request_id: "p", tool: "ExitPlanMode", description: "Plan" }), body: Ok("1. Fix it"), choices: Ok([{ id: "reject", label: "Reject", allows: Bool.False, style: Danger }, { id: "implement", label: "Implement", allows: Bool.True, style: Primary }]) }
	timeline = [{ sequence: 1, event: PermissionRequested(plan) }, { sequence: 2, event: PermissionRequested(Chat.permission({ request_id: "q", tool: "edit", description: "" })) }]
	Chat.answerable(timeline, "p", Bool.True, Ok("implement"))
		and Chat.answerable(timeline, "p", Bool.False, Err(Missing))
		and !Chat.answerable(timeline, "p", Bool.False, Ok("implement"))
		and !Chat.answerable(timeline, "p", Bool.True, Ok("later"))
		and !Chat.answerable(timeline, "q", Bool.True, Ok("implement"))
}

expect [0, 951_782_400_000, 1_767_258_000_123, 1_709_210_096_789].map(Chat.timestamp) == ["1970-01-01T00:00:00.000Z", "2000-02-29T00:00:00.000Z", "2026-01-01T09:00:00.123Z", "2024-02-29T12:34:56.789Z"]

## `chat.v1`: agent sessions as a timeline of events. The UI lists sessions,
## watches one session's timeline from a sequence number on, sends messages,
## answers the agent's permission requests, and stops a running agent.
Chat := [].{
	Status : [Idle, Running, AwaitingPermission, Finished, Failed(Str)]

	## Beyond its status, what a provider tells of a session, each left out
	## when it doesn't: the model it runs, the directory it works in (with its
	## workspace's id when the provider has one) and the branch checked out
	## there, when its running turn started and when it last changed, as times
	## such as 2026-01-01T09:00:00.000Z.
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
	}

	Event : [
		UserMessage({ text : Str }),
		AgentMessage({ text : Str }),
		ToolCall({ call_id : Str, tool : Str, input : Str }),
		ToolResult({ call_id : Str, output : Str, failed : Bool }),
		PermissionRequested({ request_id : Str, tool : Str, description : Str }),
		PermissionAnswered({ request_id : Str, allowed : Bool }),
		StatusChanged(Status),
	]

	## One event in a session's timeline. Sequence numbers start at 1 and
	## increase by 1, so a watcher resumes after the last one it saw.
	Entry : { sequence : U64, event : Event }

	## `WatchSession` answers with a stream of `Entry`, those after `after`
	## first; the others answer with one `Response`. `Create` starts an agent
	## of a kind its provider offers (`Agent`) in a workspace, or in a
	## directory of the provider the call names, with a model and a first
	## prompt ("" for none), and answers `Started` with its session's id.
	Request : [
		ListSessions,
		WatchSession({ session_id : Str, after : U64 }),
		SendMessage({ session_id : Str, text : Str }),
		AnswerPermission({ session_id : Str, request_id : Str, allowed : Bool }),
		Cancel({ session_id : Str }),
		Create(Create),
	]

	Create : { place : [Workspace(Str), Directory(Str)], agent : Str, model : Try(Str, [Missing]), prompt : Str }

	Response : [Sessions(List(Session)), Entries(List(Entry)), Accepted, Rejected(Str), Started({ session_id : Str })]

	## A kind of agent a provider can start, such as `claude`.
	Agent : { provider : Str, agent : Str }

	## A session a provider keeps but doesn't run, such as a sandboxed agent's,
	## read only, and the directory it worked in.
	Importable : { session : Session, directory : Str }

	## A session the provider tells nothing more of.
	session : { id : Str, provider : Str, agent : Str, title : Str, status : Status } -> Session
	session = |{ id, provider, agent, title, status }| { id, provider, agent, title, status, model: Err(Missing), workspace: Err(Missing), branch: Err(Missing), running_since: Err(Missing), updated: Err(Missing) }

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
		{ sequence: 1, event: PermissionRequested({ request_id: "a", tool: "bash", description: "rm -rf build" }) },
		{ sequence: 2, event: PermissionRequested({ request_id: "b", tool: "edit", description: "README.md" }) },
		{ sequence: 3, event: PermissionAnswered({ request_id: "a", allowed: Bool.True }) },
	]
	Chat.pending_permissions(timeline) == ["b"]
}

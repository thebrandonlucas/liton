## `chat.v1`: agent sessions as a timeline of events. The UI lists sessions,
## watches one session's timeline from a sequence number on, sends messages
## and answers the agent's permission requests.
Chat := [].{
	Status : [Idle, Running, AwaitingPermission, Finished, Failed(Str)]

	Session : { id : Str, provider : Str, agent : Str, title : Str, status : Status }

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
	## first; the others answer with one `Response`.
	Request : [
		ListSessions,
		WatchSession({ session_id : Str, after : U64 }),
		SendMessage({ session_id : Str, text : Str }),
		AnswerPermission({ session_id : Str, request_id : Str, allowed : Bool }),
	]

	Response : [Sessions(List(Session)), Entries(List(Entry)), Accepted, Rejected(Str)]

	## For clients that cannot hold a stream open: one request lists the
	## sessions and fetches several timelines, each after the last sequence
	## number the client has.
	Poll : { watches : List({ session_id : Str, after : U64 }) }

	Polled : { sessions : List(Session), timelines : List({ session_id : Str, entries : List(Entry) }) }

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

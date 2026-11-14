## The capability protocol's wire (docs/protocol.md): a call and its answer,
## the errors all capabilities share, and a poll of topics, each answered
## with its new events and cursor. The daemon, the UI and the CLI all read and
## write these.
import Attention
import Capability
import Chat
import Context
import Files
import Manifest
import Voice
import WorkspaceGit
import Workspaces

Protocol := [].{

	## `Unavailable`: the provider can't be reached. `Refused`: it said no.
	## `Unsupported`: no such capability, version or operation. `Overloaded`:
	## try again later.
	Code : [BadRequest, NotFound, Unavailable, Refused, Unsupported, Overloaded]

	Error : { code : Code, message : Str }

	## `POST /liton/v1/call`. Without `provider`, every provider of the
	## capability answers, merged.
	Call(request) : { capability : Str, provider : Try(Str, [Missing]), request : request }

	## A call as read before its request, whose type its capability decides.
	Addressed : { capability : Str, provider : Try(Str, [Missing]) }

	Answer(response) : [Ok(response), Err(Error)]

	## A topic followed after the cursor `after` ("" for from the start).
	Wanted : { capability : Str, topic : Str, after : Str }

	## `POST /liton/v1/poll`.
	Poll : { topics : List(Wanted) }

	## An event of a topic. A snapshot topic's one event is its whole value.
	Event : [Sessions(List(Chat.Session)), Entry(Chat.Entry), Importable(List(Chat.Importable)), Items(List(Attention.Item)), Listed(Workspaces.Listed), Changes(WorkspaceGit.Snapshot), File(WorkspaceGit.FileHunks), Tree(Files.Tree), Contents(Files.Contents), Status(Voice.Status)]

	## A topic's new events and the cursor to ask after next. A topic that
	## can't be followed has no events, its cursor unchanged and an `error`.
	Update : { capability : Str, topic : Str, cursor : Str, events : List(Event), error : Try(Error, [Missing]) }

	Polled : { topics : List(Update) }

	## What a topic follows. A `Changes` or `File` scope is named
	## `Uncommitted`, `AgainstBase` or `Commit:<sha>`, and a `File`, `Tree` or
	## `Contents` path is written with its `%` as `%25` and its `/` as `%2F`.
	Subject : [
		Sessions,
		Timeline(Str),
		Importable,
		Items,
		WorkspaceList,
		Changes({ context : Context.Id, scope : WorkspaceGit.Scope }),
		File({ context : Context.Id, scope : WorkspaceGit.Scope, path : Str }),
		Tree({ context : Context.Id, path : Str }),
		Contents({ context : Context.Id, path : Str }),
		VoiceStatus,
	]

	## The topics of each capability providers offer, as the manifest lists
	## them. A transformer declares those of the capability it offers.
	topics : List(Manifest.Topics)
	topics = [
		{ capability: Capability.chat_v1, patterns: ["sessions", "timeline/<session_id>", "importable"] },
		{ capability: Capability.workspaces_v1, patterns: ["list"] },
		{ capability: Capability.workspace_git_v1, patterns: ["changes/<session_id>/<scope>", "changes/workspace:<workspace_id>/<scope>", "file/<session_id>/<scope>/<path>", "file/workspace:<workspace_id>/<scope>/<path>"] },
		{ capability: Capability.files_v1, patterns: ["tree/<session_id>/<path>", "tree/workspace:<workspace_id>/<path>", "file/<session_id>/<path>", "file/workspace:<workspace_id>/<path>"] },
		{ capability: Capability.voice_v1, patterns: ["status"] },
	]

	## The capability a call or topic names, if the daemon offers it, and from
	## the provider it names, if any.
	routed : Manifest.Offered, Addressed -> Try(Capability.Id, Error)
	routed = |offered, { capability, provider }|
		match Capability.from_str(capability) {
			Err(NotACapability) => Err({ code: BadRequest, message: "${capability} is not a capability name such as chat.v1" })
			Ok(id) => {
				offering = Manifest.offering(offered, id)
				match provider {
					_ if offering.is_empty() => Err({ code: Unsupported, message: "the daemon offers no ${capability}" })
					Ok(named) if !offering.contains(named) => Err({ code: NotFound, message: "no provider ${named} offers ${capability}" })
					_ => Ok(id)
				}
			}
		}

	## Whether a call to `provider`, if it names one, reaches the provider `id`.
	serves : Try(Str, [Missing]), Str -> Bool
	serves = |provider, id| provider == Err(Missing) or provider == Ok(id)

	subject : Manifest.Offered, Wanted -> Try(Subject, Error)
	subject = |offered, { capability, topic, .. }| {
		id = Protocol.routed(offered, { capability, provider: Err(Missing) })?
		found =
			match Capability.to_str(id) {
				"chat.v1" if topic == "sessions" => Ok(Sessions)
				"chat.v1" if topic.starts_with("timeline/") and topic != "timeline/" => Ok(Timeline(topic.drop_prefix("timeline/")))
				"chat.v1" if topic == "importable" => Ok(Importable)
				"attention.v1" if topic == "items" => Ok(Items)
				"workspaces.v1" if topic == "list" => Ok(WorkspaceList)
				"workspace.git.v1" if topic.starts_with("changes/") => changes_subject(topic.drop_prefix("changes/"))
				"workspace.git.v1" if topic.starts_with("file/") => file_subject(topic.drop_prefix("file/"))
				"files.v1" if topic.starts_with("tree/") => placed_path(topic.drop_prefix("tree/")).map_ok(|placed| Tree(placed))
				"files.v1" if topic.starts_with("file/") => placed_path(topic.drop_prefix("file/")).map_ok(|placed| Contents(placed))
				"voice.v1" if topic == "status" => Ok(VoiceStatus)
				_ => Err(NoTopic)
			}
		found.map_err(|_| { code: NotFound, message: "${capability} has no topic ${topic}" })
	}

	## The capability and topic name that follow `subject`.
	named : Subject -> { capability : Str, topic : Str }
	named = |followed|
		match followed {
			Sessions => { capability: "chat.v1", topic: "sessions" }
			Timeline(session_id) => { capability: "chat.v1", topic: "timeline/${session_id}" }
			Importable => { capability: "chat.v1", topic: "importable" }
			Items => { capability: "attention.v1", topic: "items" }
			WorkspaceList => { capability: "workspaces.v1", topic: "list" }
			VoiceStatus => { capability: "voice.v1", topic: "status" }
			Changes(scoped) => { capability: "workspace.git.v1", topic: "changes/${scoped_name(scoped)}" }
			File({ context, scope, path }) => { capability: "workspace.git.v1", topic: "file/${scoped_name({ context, scope })}/${escaped(path)}" }
			Tree({ context, path }) => { capability: "files.v1", topic: "tree/${context_name(context)}/${escaped(path)}" }
			Contents({ context, path }) => { capability: "files.v1", topic: "file/${context_name(context)}/${escaped(path)}" }
		}

	## A snapshot topic's update: its value, cursored by its fingerprint,
	## unless the client has it already.
	snapshot : Wanted, Event -> Update
	snapshot = |{ capability, topic, after }, event| {
		cursor = Protocol.fingerprint(Json.to_str(event))
		{ capability, topic, cursor, events: if (cursor == after) [] else [event], error: Err(Missing) }
	}

	## An append-only timeline's update: the entries after the cursor, a
	## sequence number, and the last one's as the next.
	appended : Wanted, List(Chat.Entry) -> Update
	appended = |{ capability, topic, after }, entries|
		{ capability, topic, cursor: entries.last().map_ok(|entry| entry.sequence.to_str()) ?? after, events: entries.map(|entry| Entry(entry)), error: Err(Missing) }

	failed : Wanted, Error -> Update
	failed = |{ capability, topic, after }, error| { capability, topic, cursor: after, events: [], error: Ok(error) }

	## The sequence number a timeline's cursor holds, 0 for none.
	sequence : Wanted -> Try(U64, Error)
	sequence = |{ after, .. }|
		if (after == "") Ok(0) else U64.from_str(after).map_err(|_| { code: BadRequest, message: "${after} is not a timeline's cursor" })

	## A 64-bit FNV-1a hash of `text`, as a snapshot's cursor.
	fingerprint : Str -> Str
	fingerprint = |text| text.to_utf8().fold(14695981039346656037.U64, |hash, byte| hash.bitwise_xor(byte.to_u64()).times_wrap(1099511628211)).to_str()
}

## A `changes/` topic's subject from the rest of its name: the context, which
## may hold slashes, then the scope.
changes_subject : Str -> Try(Protocol.Subject, [NoTopic])
changes_subject = |rest| {
	parts = rest.split_on("/")
	scope : Try(WorkspaceGit.Scope, [NoTopic])
	scope =
		match parts.last() ?? "" {
			"Uncommitted" => Ok(Uncommitted)
			"AgainstBase" => Ok(AgainstBase)
			named_scope if named_scope.starts_with("Commit:") and named_scope != "Commit:" => Ok(Commit(named_scope.drop_prefix("Commit:")))
			_ => Err(NoTopic)
		}
	context = context_of(Str.join_with(parts.drop_last(1), "/"))?
	scope.map_ok(|picked| Changes({ context, scope: picked }))
}

## A file/ topic's subject from the rest of its name: a changes/ topic's
## context and scope, then the escaped path.
file_subject : Str -> Try(Protocol.Subject, [NoTopic])
file_subject = |rest| {
	parts = rest.split_on("/")
	path = unescaped(parts.last() ?? "")
	match changes_subject(Str.join_with(parts.drop_last(1), "/")) {
		Ok(Changes({ context, scope })) if path != "" => Ok(File({ context, scope, path }))
		_ => Err(NoTopic)
	}
}

## The context and path of a files.v1 topic from the rest of its name: the
## context, which may hold slashes, then the escaped path.
placed_path : Str -> Try({ context : Context.Id, path : Str }, [NoTopic])
placed_path = |rest| {
	parts = rest.split_on("/")
	path = unescaped(parts.last() ?? "")
	if (path == "") Err(NoTopic) else context_of(Str.join_with(parts.drop_last(1), "/")).map_ok(|context| { context, path })
}

## A topic's context from its name: a session id, or `workspace:<id>`.
context_of : Str -> Try(Context.Id, [NoTopic])
context_of = |focus|
	if focus == "" or focus == "workspace:" {
		Err(NoTopic)
	} else if focus.starts_with("workspace:") {
		Ok(Workspace(focus.drop_prefix("workspace:")))
	} else {
		Ok(Session(focus))
	}

context_name : Context.Id -> Str
context_name = |context|
	match context {
		Session(session_id) => session_id
		Workspace(workspace_id) => "workspace:${workspace_id}"
	}

## A context and scope as changes/ and file/ topics name them.
scoped_name : { context : Context.Id, scope : WorkspaceGit.Scope } -> Str
scoped_name = |{ context, scope }| {
	scope_name = match scope {
		Uncommitted => "Uncommitted"
		AgainstBase => "AgainstBase"
		Commit(sha) => "Commit:${sha}"
	}
	"${context_name(context)}/${scope_name}"
}

## A path as a topic names it, its `%` as `%25` and its `/` as `%2F`.
escaped : Str -> Str
escaped = |path| Str.join_with(path.split_on("%").map(|part| Str.join_with(part.split_on("/"), "%2F")), "%25")

unescaped : Str -> Str
unescaped = |name| Str.join_with(name.split_on("%25").map(|part| Str.join_with(part.split_on("%2F"), "/")), "%")

offered : Manifest.Offered
offered = {
	protocol: 1,
	daemon: { id: "liton", name: "liton" },
	providers: [{ id: "mock", name: "Mock", capabilities: [Capability.chat_v1, Capability.workspace_git_v1, Capability.files_v1] }],
	transformers: [{ id: "attention", name: "Attention", offers: Capability.attention_v1, uses: [Capability.chat_v1] }],
	topics: Protocol.topics,
}

expect {
	decoded : Try(Protocol.Call(Chat.Request), _)
	decoded = Json.parse("{\"capability\":\"chat.v1\",\"request\":{\"SendMessage\":{\"session_id\":\"s1\",\"text\":\"Hi\"}}}")
	decoded == Ok({ capability: "chat.v1", provider: Err(Missing), request: SendMessage({ session_id: "s1", text: "Hi" }) })
}

expect {
	refused : Protocol.Answer(Chat.Response)
	refused = Err({ code: NotFound, message: "no session s2" })
	accepted : Protocol.Answer(Chat.Response)
	accepted = Ok(Accepted)
	Json.to_str(refused) == "{\"Err\":{\"code\":\"NotFound\",\"message\":\"no session s2\"}}" and Json.to_str(accepted) == "{\"Ok\":\"Accepted\"}"
}

expect Protocol.routed(offered, { capability: "attention.v1", provider: Err(Missing) }) == Ok(Capability.attention_v1)
expect Protocol.routed(offered, { capability: "chat.v1", provider: Ok("mock") }) == Ok(Capability.chat_v1)
expect Protocol.routed(offered, { capability: "chat.v1", provider: Ok("paseo") }).map_err(|error| error.code) == Err(NotFound)
expect Protocol.routed(offered, { capability: "chat.v2", provider: Err(Missing) }).map_err(|error| error.code) == Err(Unsupported)
expect Protocol.routed(offered, { capability: "chat", provider: Err(Missing) }).map_err(|error| error.code) == Err(BadRequest)
expect Protocol.serves(Err(Missing), "mock") and Protocol.serves(Ok("mock"), "mock") and !Protocol.serves(Ok("paseo"), "mock")

# Each subject's topic name reads back as it, a session id with slashes too.
expect {
	subjects = [Sessions, Timeline("fix-auth"), Importable, Items, Changes({ context: Session("import:a/b"), scope: Commit("c1") }), Changes({ context: Workspace("w1"), scope: AgainstBase }), File({ context: Session("import:a/b"), scope: Uncommitted, path: "src/100%2F/a b.roc" }), Tree({ context: Session("peer/fix-auth"), path: "." }), Contents({ context: Workspace("w1"), path: "src/100%2F/a b.roc" })]
	subjects.all(|followed| Protocol.subject(offered, { capability: Protocol.named(followed).capability, topic: Protocol.named(followed).topic, after: "" }) == Ok(followed))
}

expect Protocol.named(Changes({ context: Workspace("w1"), scope: Uncommitted })).topic == "changes/workspace:w1/Uncommitted"
expect Protocol.named(File({ context: Session("s1"), scope: Commit("c1"), path: "src/a%.roc" })).topic == "file/s1/Commit:c1/src%2Fa%25.roc"
expect Protocol.named(Tree({ context: Workspace("w1"), path: "src/a" })) == { capability: "files.v1", topic: "tree/workspace:w1/src%2Fa" } and Protocol.named(Contents({ context: Session("s1"), path: "README.md" })).topic == "file/s1/README.md"
expect ["tree/s1", "tree/s1/", "tree/workspace:/.", "file//a.roc", "trees/s1/."].all(|topic| Protocol.subject(offered, { capability: "files.v1", topic, after: "" }).map_err(|error| error.code) == Err(NotFound))
expect ["file/s1/Uncommitted", "file/s1/Uncommitted/", "file/s1/Staged/a.roc", "file/Uncommitted/a.roc"].all(|topic| Protocol.subject(offered, { capability: "workspace.git.v1", topic, after: "" }).map_err(|error| error.code) == Err(NotFound))

expect ["timeline/", "everything", "changes/s1/Uncommitted"].all(|topic| Protocol.subject(offered, { capability: "chat.v1", topic, after: "" }).map_err(|error| error.code) == Err(NotFound))
expect ["changes/s1/Staged", "changes/s1", "changes/workspace:/Uncommitted", "changes/s1/Commit:"].all(|topic| Protocol.subject(offered, { capability: "workspace.git.v1", topic, after: "" }).map_err(|error| error.code) == Err(NotFound))
expect Protocol.subject(offered, { capability: "workspaces.v1", topic: "list", after: "" }).map_err(|error| error.code) == Err(Unsupported)

# A snapshot asked after its cursor has no events; a timeline resumes after its last entry.
expect {
	wanted = { capability: "attention.v1", topic: "items", after: "" }
	first = Protocol.snapshot(wanted, Items([]))
	again = Protocol.snapshot({ ..wanted, after: first.cursor }, Items([]))
	first.events == [Items([])] and again.events == [] and again.cursor == first.cursor
}

expect {
	wanted = { capability: "chat.v1", topic: "timeline/s1", after: "2" }
	entry = { sequence: 3, event: AgentMessage({ text: "Done." }) }
	Protocol.appended(wanted, [entry]).cursor == "3" and Protocol.appended({ ..wanted, after: "3" }, []).cursor == "3" and Protocol.sequence(wanted) == Ok(2) and Protocol.sequence({ ..wanted, after: "x" }).is_err()
}

expect {
	polled : Protocol.Polled
	polled = { topics: [Protocol.appended({ capability: "chat.v1", topic: "timeline/s1", after: "" }, [{ sequence: 1, event: StatusChanged(Running) }]), Protocol.failed({ capability: "chat.v2", topic: "sessions", after: "" }, { code: Unsupported, message: "the daemon offers no chat.v2" })] }
	Json.to_str(polled) == "{\"topics\":[{\"capability\":\"chat.v1\",\"cursor\":\"1\",\"events\":[{\"Entry\":{\"event\":{\"StatusChanged\":\"Running\"},\"sequence\":1}}],\"topic\":\"timeline/s1\"},{\"capability\":\"chat.v2\",\"cursor\":\"\",\"error\":{\"code\":\"Unsupported\",\"message\":\"the daemon offers no chat.v2\"},\"events\":[],\"topic\":\"sessions\"}]}"
}

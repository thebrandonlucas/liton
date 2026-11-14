import cap.Capability
import cap.Chat
import cap.Manifest
import cap.Protocol
import cap.Workspaces

## Providers outside the daemon (docs/protocol.md, Providers outside the
## daemon), each named in the setup or LITON_PROVIDERS and serving /liton/v1 at
## its URL. All a remote offers is named under its name, `<name>/<its id>`:
## its providers, sessions, projects and workspaces, so they never collide
## with the daemon's own, and a call or topic of one of them reaches the
## remote as it names it.
Remote := [].{
	Endpoint : { name : Str, url : Str }

	## The remotes LITON_PROVIDERS lists, comma-separated, each `name=url`. A
	## name is letters, digits, `-` and `_`, so its `/` never meets a local id
	## (Paseo's own ids with a `/` start with `import:`).
	parsed : Str -> Try(List(Endpoint), Str)
	parsed = |text| {
		endpoints = text.split_on(",").map(|entry| entry.trim()).drop_if(|entry| entry == "").map_try(endpoint_of).map_err(|problem| "LITON_PROVIDERS: ${problem}")?
		names = endpoints.map(|listed| listed.name)
		match names.find_first(|name| names.keep_if(|other| other == name).len() > 1) {
			Ok(name) => Err("LITON_PROVIDERS names ${name} twice")
			Err(_) => Ok(endpoints)
		}
	}

	## The remotes a setup declares, with those LITON_PROVIDERS lists in place
	## of any of the same name, and after them otherwise.
	declared : List(Endpoint), Str -> Try(List(Endpoint), Str)
	declared = |from_setup, listed| {
		overrides = Remote.parsed(listed)?
		checked = from_setup.map_try(|{ name, url }| endpoint_of("${name}=${url}")).map_err(|problem| "the setup's remote ${problem}")?
		Ok(checked.map(|remote| overrides.find_first(|over| over.name == remote.name) ?? remote).concat(overrides.drop_if(|over| checked.any(|remote| remote.name == over.name))))
	}

	## `id` as liton names it, under the remote `name`.
	prefixed : Str, Str -> Str
	prefixed = |name, id| "${name}/${id}"

	## The remote whose session or workspace a topic follows, and the topic as
	## it names it, or `Merged` for a list every provider adds to, such as
	## sessions.
	routed : List(Endpoint), Protocol.Subject -> Try({ endpoint : Endpoint, subject : Protocol.Subject }, [Merged])
	routed = |endpoints, subject|
		match subject {
			Timeline(session_id) => theirs(endpoints, session_id).map_ok(|(endpoint, id)| { endpoint, subject: Timeline(id) }).map_err(|_| Merged)
			Changes({ context, scope }) => their_context(endpoints, context).map_ok(|(endpoint, id)| { endpoint, subject: Changes({ context: id, scope }) }).map_err(|_| Merged)
			File({ context, scope, path }) => their_context(endpoints, context).map_ok(|(endpoint, id)| { endpoint, subject: File({ context: id, scope, path }) }).map_err(|_| Merged)
			Tree({ context, path }) => their_context(endpoints, context).map_ok(|(endpoint, id)| { endpoint, subject: Tree({ context: id, path }) }).map_err(|_| Merged)
			Contents({ context, path }) => their_context(endpoints, context).map_ok(|(endpoint, id)| { endpoint, subject: Contents({ context: id, path }) }).map_err(|_| Merged)
			_ => Err(Merged)
		}

	## The remote a session belongs to, if any.
	owner : List(Endpoint), Str -> Try(Endpoint, [Local])
	owner = |endpoints, session_id| theirs(endpoints, session_id).map_ok(|(endpoint, _)| endpoint).map_err(|_| Local)

	## The remote whose session a chat.v1 request names, if any.
	chat_owner : List(Endpoint), Chat.Request -> Try(Endpoint, [Local])
	chat_owner = |endpoints, asked|
		match asked {
			ListSessions => Err(Local)
			WatchSession({ session_id, .. }) => Remote.owner(endpoints, session_id)
			SendMessage({ session_id, .. }) => Remote.owner(endpoints, session_id)
			AnswerPermission({ session_id, .. }) => Remote.owner(endpoints, session_id)
			Cancel({ session_id }) => Remote.owner(endpoints, session_id)
			Create({ place: Workspace(workspace_id), .. }) => Remote.owner(endpoints, workspace_id)
			Create({ place: Directory(_), .. }) => Err(Local)
		}

	## The topics of each remote a merged list needs: workspaces are counted
	## from sessions.
	merged : Protocol.Subject -> List(Protocol.Subject)
	merged = |subject|
		match subject {
			Sessions => [Sessions]
			Importable => [Importable]
			Agents => [Agents]
			WorkspaceList => [WorkspaceList, Sessions]
			_ => []
		}

	## The providers a remote's manifest adds to liton's, under its name, with
	## the capabilities the daemon routes to them.
	providers : Str, Manifest.Advertised -> List(Manifest.Provider)
	providers = |name, advertised|
		advertised.providers
			.map(|provider| { ..provider, id: Remote.prefixed(name, provider.id), capabilities: provider.capabilities.keep_if(|id| routable.contains(id)) })
			.drop_if(|provider| provider.capabilities.is_empty())

	## Whether a call naming `provider`, if it names one, reaches the remote
	## `name`.
	serves : Str, Try(Str, [Missing]) -> Bool
	serves = |name, provider| provider.map_ok(|named| named.starts_with("${name}/")) ?? Bool.True

	## A chat.v1 call to the remote `name`, its session and provider as the
	## remote names them.
	call : Str, Try(Str, [Missing]), Chat.Request -> Protocol.Call(Chat.Request)
	call = |name, provider, asked| {
		their_id = |id| id.drop_prefix("${name}/")
		request =
			match asked {
				ListSessions => ListSessions
				WatchSession(watch) => WatchSession({ ..watch, session_id: their_id(watch.session_id) })
				SendMessage(message) => SendMessage({ ..message, session_id: their_id(message.session_id) })
				AnswerPermission(answer) => AnswerPermission({ ..answer, session_id: their_id(answer.session_id) })
				Cancel({ session_id }) => Cancel({ session_id: their_id(session_id) })
				Create(created) =>
					match created.place {
						Workspace(workspace_id) => Create({ ..created, place: Workspace(their_id(workspace_id)) })
						Directory(_) => Create(created)
					}
			}
		{ capability: "chat.v1", provider: provider.map_ok(their_id), request }
	}

	## A workspaces.v1 Create to the remote `name`, its project and provider
	## as the remote names them.
	workspaces_call : Str, Try(Str, [Missing]), Workspaces.Create -> Protocol.Call(Workspaces.Request)
	workspaces_call = |name, provider, created| {
		their_id = |id| id.drop_prefix("${name}/")
		{ capability: "workspaces.v1", provider: provider.map_ok(their_id), request: Create({ ..created, project_id: their_id(created.project_id) }) }
	}

	## A remote's answer to a chat.v1 call, a session it started named under
	## its name.
	chat_answer : Str, Protocol.Answer(Chat.Response) -> Protocol.Answer(Chat.Response)
	chat_answer = |name, answer|
		match answer {
			Ok(Started({ session_id })) => Ok(Started({ session_id: Remote.prefixed(name, session_id) }))
			_ => answer
		}

	## A remote's answer to a workspaces.v1 call, a workspace it created named
	## under its name.
	workspaces_answer : Str, Protocol.Answer(Workspaces.Response) -> Protocol.Answer(Workspaces.Response)
	workspaces_answer = |name, answer|
		match answer {
			Ok(Created({ workspace_id })) => Ok(Created({ workspace_id: Remote.prefixed(name, workspace_id) }))
			_ => answer
		}

	## An event of the remote `name`'s topic as liton serves it, its ids under
	## the remote's name.
	event : Str, Protocol.Event -> Protocol.Event
	event = |name, given|
		match given {
			Sessions(sessions) => Sessions(sessions.map(|shown| session(name, shown)))
			Importable(listed) => Importable(listed.map(|kept| { ..kept, session: session(name, kept.session) }))
			Agents(listed) => Agents(listed.map(|kind| { ..kind, provider: Remote.prefixed(name, kind.provider) }))
			Listed({ projects, workspaces }) =>
				Listed({
					projects: projects.map(|project| { ..project, id: Remote.prefixed(name, project.id), provider: Remote.prefixed(name, project.provider) }),
					workspaces: workspaces.map(|shown| workspace(name, shown)),
				})
			Changes(snapshot) =>
				match snapshot.workspace {
					Known(known) => Changes({ ..snapshot, workspace: Known({ ..known, provider: Remote.prefixed(name, known.provider) }) })
					Unknown => given
				}
			_ => given
		}

	## How long the daemon waits before asking a remote that failed `failures`
	## times in a row again: a second, doubling up to a minute.
	backoff_ms : I64 -> I64
	backoff_ms = |failures| if (failures >= 6) 60_000 else 1_000 * (2.I64).pow(failures - 1)
}

## The capabilities the daemon routes to a remote's sessions and workspaces.
## A remote's transformers are left out: the daemon's derive from every provider.
routable : List(Capability.Id)
routable = [Capability.chat_v1, Capability.workspaces_v1, Capability.workspace_git_v1, Capability.files_v1]

endpoint_of : Str -> Try(Remote.Endpoint, Str)
endpoint_of = |entry| {
	parts = entry.split_on("=")
	name = (parts.first() ?? "").trim()
	url = Str.join_with(parts.drop_first(1), "=").trim().drop_suffix("/")
	allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_".to_utf8()
	if name == "" or !name.to_utf8().all(|byte| allowed.contains(byte)) {
		Err("${entry} needs a name of letters, digits, - and _, as in name=http://127.0.0.1:8096")
	} else if !(url.starts_with("http://") or url.starts_with("https://")) {
		Err("${name} needs an http:// or https:// URL")
	} else {
		Ok({ name, url })
	}
}

## The remote an id is under, and the id as it names it.
theirs : List(Remote.Endpoint), Str -> Try((Remote.Endpoint, Str), [Local])
theirs = |endpoints, id|
	endpoints
		.find_first(|listed| id.starts_with("${listed.name}/") and id != "${listed.name}/")
		.map_ok(|listed| (listed, id.drop_prefix("${listed.name}/")))
		.map_err(|_| Local)

their_context : List(Remote.Endpoint), [Session(Str), Workspace(Str)] -> Try((Remote.Endpoint, [Session(Str), Workspace(Str)]), [Local])
their_context = |endpoints, context|
	match context {
		Session(id) => theirs(endpoints, id).map_ok(|(listed, their_id)| (listed, Session(their_id)))
		Workspace(id) => theirs(endpoints, id).map_ok(|(listed, their_id)| (listed, Workspace(their_id)))
	}

session : Str, Chat.Session -> Chat.Session
session = |name, shown| { ..shown, id: Remote.prefixed(name, shown.id), provider: Remote.prefixed(name, shown.provider), workspace: shown.workspace.map_ok(|placed| { ..placed, id: placed.id.map_ok(|id| Remote.prefixed(name, id)) }) }

workspace : Str, Workspaces.Workspace -> Workspaces.Workspace
workspace = |name, shown| {
	..shown,
	id: Remote.prefixed(name, shown.id),
	provider: Remote.prefixed(name, shown.provider),
	project_id: Remote.prefixed(name, shown.project_id),
	session_ids: shown.session_ids.map(|id| Remote.prefixed(name, id)),
}

echo : Remote.Endpoint
echo = { name: "echo", url: "http://127.0.0.1:8096" }

peer : Remote.Endpoint
peer = { name: "peer", url: "https://peer.example/base" }

expect Remote.parsed(" echo=http://127.0.0.1:8096/ , peer=https://peer.example/base,") == Ok([echo, peer])
expect Remote.parsed("") == Ok([])
expect Remote.declared([echo, peer], "peer=http://127.0.0.1:9000,team=https://liton.example") == Ok([echo, { name: "peer", url: "http://127.0.0.1:9000" }, { name: "team", url: "https://liton.example" }])
expect Remote.declared([{ name: "a/b", url: "http://a" }], "").is_err() and Remote.declared([echo], "echo").is_err()
expect ["echo", "=http://a", "a/b=http://a", "a=ftp://a", "a=http://x,a=http://y"].all(|text| Remote.parsed(text).is_err())

# A remote's session, workspace and git topics reach it as it names them;
# lists merge every remote's.
expect Remote.routed([echo, peer], Timeline("peer/c/fix-auth")) == Ok({ endpoint: peer, subject: Timeline("c/fix-auth") })
expect Remote.routed([echo, peer], Changes({ context: Workspace("echo/w1"), scope: Uncommitted })) == Ok({ endpoint: echo, subject: Changes({ context: Workspace("w1"), scope: Uncommitted }) })
expect Remote.routed([echo, peer], File({ context: Session("echo/s1"), scope: AgainstBase, path: "a.roc" })) == Ok({ endpoint: echo, subject: File({ context: Session("s1"), scope: AgainstBase, path: "a.roc" }) })
expect Remote.routed([echo, peer], Tree({ context: Workspace("peer/w1"), path: "." })) == Ok({ endpoint: peer, subject: Tree({ context: Workspace("w1"), path: "." }) }) and Remote.routed([echo, peer], Contents({ context: Session("echo/s1"), path: "a.roc" })) == Ok({ endpoint: echo, subject: Contents({ context: Session("s1"), path: "a.roc" }) })
expect [Timeline("fix-auth"), Timeline("import:claude:/home/a"), Timeline("echo/"), Timeline("echoes/s1"), Sessions, Items].all(|subject| Remote.routed([echo, peer], subject) == Err(Merged))
expect Remote.owner([echo], "echo/s1") == Ok(echo) and Remote.owner([echo], "s1") == Err(Local)
expect Remote.merged(Sessions) == [Sessions] and Remote.merged(WorkspaceList) == [WorkspaceList, Sessions] and Remote.merged(Timeline("s1")) == []

# A remote's providers are named under it, with what the daemon routes.
expect {
	advertised = { protocol: 1, providers: [{ id: "mock", name: "Mock", capabilities: [Capability.chat_v1, { name: "ci", version: 1 }] }, { id: "ci", name: "CI", capabilities: [{ name: "ci", version: 1 }] }] }
	Remote.providers("peer", advertised) == [{ id: "peer/mock", name: "Mock", capabilities: [Capability.chat_v1] }]
}

expect Remote.serves("peer", Err(Missing)) and Remote.serves("peer", Ok("peer/mock")) and !Remote.serves("peer", Ok("mock"))

expect Remote.call("peer", Ok("peer/c/mock"), SendMessage({ session_id: "peer/c/s1", text: "Hi" })) == { capability: "chat.v1", provider: Ok("c/mock"), request: SendMessage({ session_id: "c/s1", text: "Hi" }) }
expect Remote.call("peer", Err(Missing), AnswerPermission({ session_id: "peer/s1", request_id: "r1", allowed: Bool.True })).request == AnswerPermission({ session_id: "s1", request_id: "r1", allowed: Bool.True })
expect Remote.call("peer", Err(Missing), Cancel({ session_id: "peer/s1" })).request == Cancel({ session_id: "s1" }) and Remote.chat_owner([echo, peer], Cancel({ session_id: "peer/s1" })) == Ok(peer)

# Sessions, and the projects and workspaces that list them, are named under the remote.
expect {
	shown = { ..Chat.session({ id: "s1", provider: "mock", agent: "claude", title: "Fix", status: Idle }), model: Ok("opus"), workspace: Ok({ id: Ok("w1"), directory: "/src/liton" }) }
	Remote.event("peer", Sessions([shown])) == Sessions([{ ..shown, id: "peer/s1", provider: "peer/mock", workspace: Ok({ id: Ok("peer/w1"), directory: "/src/liton" }) }])
}

expect {
	listed = Remote.event(
		"peer",
		Listed({
			projects: [{ id: "p1", provider: "mock", name: "liton", directory: "/src/liton" }],
			workspaces: [{ id: "w1", provider: "mock", project_id: "p1", name: "main", directory: "/src/liton", kind: Checkout, branch: Branch("main"), state: Idle, dirty: Bool.False, changes: Uncounted, pinned: Bool.False, labels: [], session_ids: ["s1"] }],
		}),
	)
	match listed {
		Listed({ projects, workspaces }) => projects.map(|project| project.id) == ["peer/p1"] and workspaces.map(|shown| (shown.id, shown.project_id, shown.session_ids)) == [("peer/w1", "peer/p1", ["peer/s1"])]
		_ => Bool.False
	}
}

expect Remote.event("peer", Entry({ sequence: 1, event: AgentMessage({ text: "Hi" }) })) == Entry({ sequence: 1, event: AgentMessage({ text: "Hi" }) })
expect [1, 2, 3, 6, 9].map(Remote.backoff_ms) == [1_000, 2_000, 4_000, 60_000, 60_000]

# A remote's workspace or project a Create names reaches it as it names it,
# and what it made comes back under its name.
expect {
	created = { place: Workspace("peer/w1"), agent: "claude", model: Err(Missing), prompt: "Hi" }
	Remote.chat_owner([echo, peer], Create(created)) == Ok(peer) and Remote.call("peer", Err(Missing), Create(created)).request == Create({ ..created, place: Workspace("w1") }) and Remote.chat_answer("peer", Ok(Started({ session_id: "s9" }))) == Ok(Started({ session_id: "peer/s9" }))
}
expect Remote.workspaces_call("peer", Ok("peer/mock"), { project_id: "peer/p1", kind: Worktree, branch: Err(Missing) }) == { capability: "workspaces.v1", provider: Ok("mock"), request: Create({ project_id: "p1", kind: Worktree, branch: Err(Missing) }) } and Remote.workspaces_answer("peer", Ok(Created({ workspace_id: "w2" }))) == Ok(Created({ workspace_id: "peer/w2" }))

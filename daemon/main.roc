## liton's daemon: advertises its providers' capabilities and serves chat.v1,
## workspace.git.v1 and workspaces.v1 over HTTP, from what it keeps in SQLite,
## and serves the UI. /liton/v1 speaks the capability protocol
## (docs/protocol.md); /api/... are the UI's earlier forms of it.
##
## LITON_PORT (default 8095), LITON_HOST (default 127.0.0.1), LITON_DB
## (default liton.db) and LITON_UI (default zig-out/www) configure it.
## LITON_MOCK=off leaves out the mock provider. Setting PASEO_PASSWORD adds
## the agents of the Paseo daemon at PASEO_HOST (default 127.0.0.1) and
## PASEO_PORT (default 6767), reached over its WebSocket alone.
## GET /api/paseo/importable lists, read only, the sessions Paseo's providers
## keep that Paseo doesn't run, such as sandboxed agents'.
app [Context, program] {
	cap: "../capabilities/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	mock: "../providers/mock/main.roc",
	paseo: "../providers/paseo/main.roc",
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.21.0/4viZsnWjdYsyH4Q87ESFAwM5c55Hnc15nAGW1UwzWpFU.tar.zst",
}

import pf.Env
import pf.OsStr
import pf.Path
import pf.Server
import pf.Sqlite
import pf.Stderr
import pf.Tcp
import pf.UnixTime
import http.Response
import cap.Attention
import cap.Capability
import cap.Chat
import cap.Manifest
import cap.Protocol
import cap.WorkspaceGit
import cap.Workspaces
import mock.Mock
import paseo.Paseo
import paseo.PaseoGit
import paseo.PaseoWorkspaces
import paseo.WebSocket

Context : { db : Sqlite.Db, mock_enabled : Bool, paseo : Try(PaseoDaemon, [Disabled]) }

PaseoDaemon : { host : Str, port : U16, password : Str }

program = { init!, respond!, shutdown! }

env_or! : Str, Str => Str
env_or! = |name, default| Env.var_str!(OsStr.from_str(name)) ?? default

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64)])
init! = || {
	port = U16.from_str(env_or!("LITON_PORT", "8095")) ?? 8095
	host = env_or!("LITON_HOST", "127.0.0.1")
	db = Sqlite.open!(Sqlite.default_config(Path.utf8(env_or!("LITON_DB", "liton.db")))) ? |_| Exit(2)
	create_tables!(db) ? |_| Exit(3)
	# A password Paseo refused may have been fixed since.
	Sqlite.execute!({ db, query: "DELETE FROM paseo_listings WHERE what = 'refusal';", params: {} }) ? |_| Exit(3)
	mock_enabled = env_or!("LITON_MOCK", "on") != "off"
	if mock_enabled {
		seed!(db) ? |_| Exit(4)
	}
	password = env_or!("PASEO_PASSWORD", "")
	paseo = if (password == "") Err(Disabled) else Ok({ host: env_or!("PASEO_HOST", "127.0.0.1"), port: U16.from_str(env_or!("PASEO_PORT", "6767")) ?? 6767, password })
	ui = Server.file_root({ id: "ui", path: Path.utf8(env_or!("LITON_UI", "zig-out/www")) })
	config =
		Server.default_config
			.with_listen({ host, port })
			.with_file_roots([ui])
			.with_native_routes({ files: [Server.static_mount({ at: "/ui", files: ui })], liveness: [], readiness: [] })
	Ok({ config, context: { db, mock_enabled, paseo } })
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64)])
shutdown! = |_reason, _context| Ok({})

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str)])
respond! = |request, context| {
	response =
		match (request.method(), request.target()) {
			(GET, Resource({ raw_path: "/", .. })) =>
				Ok(Response.from_status(302).with_headers([{ name: "Location", value: "/ui/index.html" }]))
			(GET, Resource({ raw_path: "/api/manifest", .. })) =>
				{
					providers = offered(context).providers
					Ok(json(Json.to_str({ protocol: Manifest.protocol, providers: if (providers.is_empty()) [] else providers.append(liton_provider) })))
				}
			(GET, Resource({ raw_path: "/liton/v1/manifest", .. })) =>
				Ok(json(Json.to_str(offered(context))))
			(POST, Resource({ raw_path: "/liton/v1/call", .. })) =>
				call!(context, request)
			(POST, Resource({ raw_path: "/liton/v1/poll", .. })) =>
				polled_topics!(context, request)
			(POST, Resource({ raw_path: "/api/chat", .. })) =>
				chat!(context, request)
			(POST, Resource({ raw_path: "/api/chat/poll", .. })) =>
				poll!(context, request)
			(POST, Resource({ raw_path: "/api/git/poll", .. })) =>
				git_poll!(context, request)
			(GET, Resource({ raw_path: "/api/attention", .. })) =>
				attention_items!(context).map_ok(|items| json(Json.to_str(items)))
			(POST, Resource({ raw_path: "/api/attention", .. })) =>
				attention!(context, request)
			(GET, Resource({ raw_path: "/api/workspaces", .. })) =>
				workspaces!(context).map_ok(|listed| json(Json.to_str(listed)))
			(POST, Resource({ raw_path: "/api/workspaces", .. })) =>
				workspaces_request!(context, request)
			(GET, Resource({ raw_path: "/api/paseo/importable", .. })) =>
				importable_listed!(context)
			_ => Ok(text(404, "Not found"))
		}
	match response {
		Ok(answer) => Ok(Server.respond(answer))
		Err(err) => Ok(Server.respond(text(500, Str.inspect(err))))
	}
}

json : Str -> Response
json = |body|
	Response.from_status(200)
		.with_headers([{ name: "Content-Type", value: "application/json; charset=utf-8" }])
		.with_body(body.to_utf8())

text : U16, Str -> Response
text = |status, body|
	Response.from_status(status)
		.with_headers([{ name: "Content-Type", value: "text/plain; charset=utf-8" }])
		.with_body(body.to_utf8())

read_json! : Server.Request => Try(Str, _)
read_json! = |request| {
	body = request.body().with_limit(64 * 1024).read_all!()?
	Str.from_utf8(body)
}

## What /liton/v1/manifest answers: the enabled providers, and attention
## once one of them supplies chat.v1.
offered : Context -> Manifest.Offered
offered = |{ mock_enabled, paseo, .. }| {
	providers = (if (mock_enabled) [Mock.provider] else []).concat(if (paseo.is_ok()) [Paseo.provider] else [])
	transformers = if (providers.any(|provider| provider.capabilities.contains(Capability.chat_v1))) [attention_transformer] else []
	manifest = { protocol: Manifest.protocol, daemon: { id: "liton", name: "liton" }, providers, transformers, topics: [] }
	{ ..manifest, topics: Protocol.topics.keep_if(|topics| Manifest.offered(manifest).contains(topics.capability)) }
}

## Answers a /liton/v1/call by its capability (see docs/protocol.md).
call! : Context, Server.Request => Try(Response, _)
call! = |context, request| {
	body = read_json!(request)?
	addressed : Try(Protocol.Addressed, _)
	addressed = Json.parse(body)
	routed =
		match addressed {
			Ok(asked) => Protocol.routed(offered(context), asked).map_ok(|id| (Capability.to_str(id), asked.provider))
			Err(_) => Err({ code: BadRequest, message: "expected a call, such as {\"capability\":\"chat.v1\",\"request\":\"ListSessions\"}" })
		}
	unanswered : Str -> Protocol.Error
	unanswered = |capability| { code: BadRequest, message: "expected a ${capability} request" }
	answered =
		match routed {
			Ok(("chat.v1", provider)) => {
				decoded : Try(Protocol.Call(Chat.Request), _)
				decoded = Json.parse(body)
				answer : Protocol.Answer(Chat.Response)
				answer = match decoded {
					Ok({ request: asked, .. }) => chat_call!(context, provider, asked)?
					Err(_) => Err(unanswered("chat.v1"))
				}
				Json.to_str(answer)
			}
			Ok(("attention.v1", _)) => {
				decoded : Try(Protocol.Call(Attention.Request), _)
				decoded = Json.parse(body)
				answer : Protocol.Answer(Attention.Response)
				answer = match decoded {
					Ok({ request: asked, .. }) => attention_call!(context, asked)?
					Err(_) => Err(unanswered("attention.v1"))
				}
				Json.to_str(answer)
			}
			Ok(("workspaces.v1", provider)) => {
				decoded : Try(Protocol.Call(Workspaces.Request), _)
				decoded = Json.parse(body)
				answer : Protocol.Answer(Workspaces.Response)
				answer = match decoded {
					Ok({ request: ListWorkspaces, .. }) => {
						listed = workspaces!(context)?
						Ok(Listed({ projects: listed.projects.keep_if(|project| Protocol.serves(provider, project.provider)), workspaces: listed.workspaces.keep_if(|workspace| Protocol.serves(provider, workspace.provider)) }))
					}
					Err(_) => Err(unanswered("workspaces.v1"))
				}
				Json.to_str(answer)
			}
			Ok((capability, _)) => Json.to_str(call_failed({ code: Unsupported, message: "${capability} has no calls; poll its topics" }))
			Err(error) => Json.to_str(call_failed(error))
		}
	Ok(json(answered))
}

call_failed : Protocol.Error -> Protocol.Answer({})
call_failed = |error| Err(error)

## Answers a /liton/v1/poll: notes what all its topics watch, so that one
## Paseo cycle asks about them all, then answers each, a topic it can't
## follow with why.
polled_topics! : Context, Server.Request => Try(Response, _)
polled_topics! = |context, request| {
	decoded : Try(Protocol.Poll, _)
	decoded = Json.parse(read_json!(request)?)
	match decoded {
		Err(_) => Ok(text(400, "expected a poll, such as {\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"after\":\"\"}]}"))
		Ok({ topics }) => {
			manifest = offered(context)
			for wanted in topics {
				match Protocol.subject(manifest, wanted) {
					Ok(subject) => interested!(context, subject)?
					Err(_) => {}
				}
			}
			paseo_cycle!(context)?
			var $updates = []
			for wanted in topics {
				$updates = $updates.append(
					match Protocol.subject(manifest, wanted) {
						Ok(subject) => update!(context, wanted, subject)?
						Err(error) => Protocol.failed(wanted, error)
					},
				)
			}
			polled : Protocol.Polled
			polled = { topics: $updates }
			Ok(json(Json.to_str(polled)))
		}
	}
}

## Notes that a poll watches a topic's subject, as the old endpoints do, so
## the next cycle asks Paseo about it.
interested! : Context, Protocol.Subject => Try({}, _)
interested! = |context, subject| {
	db = context.db
	match subject {
		Timeline(session_id) =>
			match provider!(context, session_id)? {
				PaseoSession(_) => wanted!(db, "timeline", session_id)
				_ => Ok({})
			}
		Changes({ context: focus, scope }) => git_interested!(context, focus, { scope, file: NoFile })
		File({ context: focus, scope, path }) => git_interested!(context, focus, { scope, file: Selected(path) })
		Importable if context.paseo.is_ok() => wanted!(db, "importable", "")
		WorkspaceList if context.paseo.is_ok() => {
			wanted!(db, "agent_list", "")?
			wanted!(db, "workspace_list", "")
		}
		_ => if (context.paseo.is_ok()) wanted!(db, "agent_list", "") else Ok({})
	}
}

## Notes that a poll watches what is asked of a context's workspace.
git_interested! : Context, [Session(Str), Workspace(Str)], WorkspaceGit.Asked => Try({}, _)
git_interested! = |context, focus, asked|
	match located!(context, focus)? {
		PaseoDirectory(directory) => git_wanted!(context.db, directory, asked)
		_ => Ok({})
	}

## A topic's update: a timeline's entries after its cursor, or a snapshot of
## anything else.
update! : Context, Protocol.Wanted, Protocol.Subject => Try(Protocol.Update, _)
update! = |context, wanted, subject|
	match subject {
		Sessions => Ok(Protocol.snapshot(wanted, Sessions(sessions!(context)?)))
		Timeline(session_id) =>
			match Protocol.sequence(wanted) {
				Ok(after) => Ok(Protocol.appended(wanted, visible!(context.db, session_id, after)?))
				Err(error) => Ok(Protocol.failed(wanted, error))
			}
		Items => Ok(Protocol.snapshot(wanted, Items(attention_items!(context)?)))
		WorkspaceList => Ok(Protocol.snapshot(wanted, Listed(workspaces!(context)?)))
		Importable => Ok(Protocol.snapshot(wanted, Importable(importable!(context)?)))
		Changes({ context: focus, scope }) => Ok(Protocol.snapshot(wanted, Changes(WorkspaceGit.snapshot(scope, git_found!(context, focus, { scope, file: NoFile })?))))
		File({ context: focus, scope, path }) => Ok(Protocol.snapshot(wanted, File(WorkspaceGit.file_hunks(path, git_found!(context, focus, { scope, file: Selected(path) })?))))
	}

chat! : Context, Server.Request => Try(Response, _)
chat! = |context, request| {
	decoded : Try(Chat.Request, _)
	decoded = Json.parse(read_json!(request)?)
	answer : Chat.Response
	answer =
		match decoded {
			Err(_) => Rejected("expected a chat.v1 request")
			Ok(asked) =>
				match chat_call!(context, Err(Missing), asked)? {
					Ok(response) => response
					Err({ message, .. }) => Rejected(message)
				}
		}
	Ok(json(Json.to_str(answer)))
}

## Answers a chat.v1 request, of `provider`'s sessions alone if it names one.
chat_call! : Context, Try(Str, [Missing]), Chat.Request => Try(Protocol.Answer(Chat.Response), _)
chat_call! = |context, provider, asked| {
	db = context.db
	match asked {
		ListSessions => Ok(Ok(Sessions(sessions!(context)?.keep_if(|session| Protocol.serves(provider, session.provider)))))
		WatchSession({ session_id, after }) =>
			match routed_provider!(context, provider, session_id)? {
				NoSession => Ok(no_session(session_id))
				_ => Ok(Ok(Entries(timelines!(context, [{ session_id, after }])?.first().map_ok(|timeline| timeline.entries) ?? [])))
			}
		SendMessage({ session_id, text: message }) =>
			match routed_provider!(context, provider, session_id)? {
				MockSession => {
					schedule!(db, session_id, |next| Mock.on_message(message, next))?
					Ok(Ok(Accepted))
				}
				PaseoSession(daemon) => {
					request_id = "liton-send-${now_ms!().to_str()}"
					outcome = written!(daemon, Paseo.send_request(session_id, message, request_id), request_id, Paseo.sent)
					forget_check!(db, "cycle")?
					Ok(paseo_answer(outcome))
				}
				NoSession => Ok(no_session(session_id))
			}
		AnswerPermission({ session_id, request_id, allowed }) =>
			if !Chat.pending_permissions(visible!(db, session_id, 0)?).contains(request_id) {
				Ok(Err({ code: NotFound, message: "no pending permission request ${request_id}" }))
			} else {
				match routed_provider!(context, provider, session_id)? {
					MockSession => {
						schedule!(db, session_id, |next| Mock.on_answer(request_id, allowed, next))?
						Ok(Ok(Accepted))
					}
					PaseoSession(daemon) => {
						outcome = written!(daemon, Paseo.permission_answer(session_id, request_id, allowed), request_id, Paseo.resolved)
						if outcome.is_ok() {
							known = state_of!(db, session_id)?
							store!(db, session_id, known.stored, { state: Paseo.answered(known.state, request_id), events: [PermissionAnswered({ request_id, allowed })] })?
						}
						forget_check!(db, "cycle")?
						Ok(paseo_answer(outcome))
					}
					NoSession => Ok(no_session(session_id))
				}
			}
	}
}

no_session : Str -> Protocol.Answer(a)
no_session = |session_id| Err({ code: NotFound, message: "no session ${session_id}" })

## The enabled provider a session belongs to, or `NoSession` when the call
## names another.
routed_provider! : Context, Try(Str, [Missing]), Str => Try([MockSession, PaseoSession(PaseoDaemon), NoSession], _)
routed_provider! = |context, provider, session_id| {
	found = provider!(context, session_id)?
	owner = match found {
		MockSession => Mock.provider.id
		PaseoSession(_) => Paseo.provider.id
		NoSession => ""
	}
	Ok(if (Protocol.serves(provider, owner)) found else NoSession)
}

poll! : Context, Server.Request => Try(Response, _)
poll! = |context, request| {
	decoded : Try(Chat.Poll, _)
	decoded = Json.parse(read_json!(request)?)
	match decoded {
		Err(_) => Ok(text(400, "expected a chat.v1 poll"))
		Ok({ watches }) => {
			sessions = sessions!(context)?
			polled : Chat.Polled
			polled = { sessions, timelines: timelines!(context, watches)? }
			Ok(json(Json.to_str(polled)))
		}
	}
}

## Answers a workspace.git.v1 poll, of a context or, as the UI sends it, of a
## session. A workspace that can't be read is `Unknown`, never an error.
git_poll! : Context, Server.Request => Try(Response, _)
git_poll! = |context, request| {
	body = read_json!(request)?
	of_context : Try(WorkspaceGit.ContextPoll, _)
	of_context = Json.parse(body)
	of_session : Try(WorkspaceGit.Poll, _)
	of_session = Json.parse(body)
	# `polled` and `unknown` read only the poll's scope, known and file.
	asked =
		match (of_context, of_session) {
			(Ok({ context: focus, scope, known, file }), _) => Ok({ focus, poll: { session_id: "", scope, known, file } })
			(_, Ok(poll)) => Ok({ focus: Session(poll.session_id), poll })
			_ => Err(NotAPoll)
		}
	match asked {
		Err(NotAPoll) => Ok(text(400, "expected a workspace.git.v1 poll"))
		Ok({ focus, poll }) => {
			polled : WorkspaceGit.Polled
			polled =
				match git_found!(context, focus, { scope: poll.scope, file: poll.file })? {
					Ok(found) => WorkspaceGit.polled(poll, found)
					Err(Unknown) => WorkspaceGit.unknown(poll)
				}
			Ok(json(Json.to_str(polled)))
		}
	}
}

## What a provider has of a context's workspace for what is asked, `Unknown`
## when the workspace can't be read.
git_found! : Context, [Session(Str), Workspace(Str)], WorkspaceGit.Asked => Try(Try(WorkspaceGit.Found, [Unknown]), _)
git_found! = |context, focus, poll|
	match located!(context, focus)? {
		MockWorkspace(workspace_id) => Ok(Ok(Mock.git(workspace_id, poll.scope, poll.file)))
		PaseoDirectory(directory) =>
			match paseo_git!(context, directory, poll) {
				Ok(Ok(found)) => Ok(Ok(found))
				Ok(Err(NothingCached)) => Ok(Err(Unknown))
				Err(err) => {
					logged!("Paseo: answering a git poll of ${directory} failed: ${Str.inspect(err)}")
					Ok(Err(Unknown))
				}
			}
		Nowhere => Ok(Err(Unknown))
	}

## Where a context's workspace is: a mock workspace, or a Paseo directory. A
## session's is the one it works in.
located! : Context, [Session(Str), Workspace(Str)] => Try([MockWorkspace(Str), PaseoDirectory(Str), Nowhere], _)
located! = |context, focus|
	match focus {
		Session(session_id) =>
			match provider!(context, session_id)? {
				MockSession => Ok(Mock.workspaces.find_first(|shown| shown.session_ids.contains(session_id)).map_ok(|shown| MockWorkspace(shown.id)) ?? Nowhere)
				PaseoSession(_) => {
					rows : List({ directory : Str })
					rows = Sqlite.query_many!({ db: context.db, query: "SELECT directory FROM sessions WHERE id = :session_id;", params: { session_id }, limits: Sqlite.default_query_limits })?
					Ok(rows.first().map_ok(|row| paseo_directory(row.directory)) ?? Nowhere)
				}
				NoSession => Ok(Nowhere)
			}
		Workspace(workspace_id) =>
			if context.mock_enabled and Mock.workspaces.any(|shown| shown.id == workspace_id) {
				Ok(MockWorkspace(workspace_id))
			} else if context.paseo.is_ok() {
				Ok(paseo_listed!(context.db)?.workspaces.find_first(|shown| shown.id == workspace_id).map_ok(|shown| paseo_directory(shown.directory)) ?? Nowhere)
			} else {
				Ok(Nowhere)
			}
	}

## A directory Paseo can tell the git of. A remote agent's, such as a
## sandboxed one's, is "/", which Paseo has nothing to tell of.
paseo_directory : Str -> [PaseoDirectory(Str), Nowhere]
paseo_directory = |directory| if (directory == "" or directory == "/") Nowhere else PaseoDirectory(directory)

## A Paseo directory's workspace, from what the git cache holds of it once
## the cycle asked Paseo what is due.
paseo_git! : Context, Str, WorkspaceGit.Asked => Try(Try(WorkspaceGit.Found, [NothingCached]), _)
paseo_git! = |context, directory, poll| {
	db = context.db
	git_wanted!(db, directory, poll)?
	selected = selected_commit_file(poll)
	paseo_cycle!(context)?
	known : Try({ workspace : WorkspaceGit.Workspace, status : [Status(WorkspaceGit.Status), NoStatus] }, _)
	known = Json.parse(cached!(db, directory, "workspace")?.map_ok(|row| row.value) ?? "")
	commits : Try(List(WorkspaceGit.Commit), _)
	commits = Json.parse(cached!(db, directory, "commits")?.map_ok(|row| row.value) ?? "")
	selected_hunks : Try(List(WorkspaceGit.Hunk), _)
	selected_hunks =
		match selected {
			Ok({ what, .. }) => Json.parse(cached!(db, directory, what)?.map_ok(|row| row.value) ?? "")
			Err(NoFile) => Ok([])
		}
	scope_diff =
		match poll.scope {
			Uncommitted => cached!(db, directory, "uncommitted")?
			AgainstBase => cached!(db, directory, "base")?
			Commit(_) => Err(NothingCached)
		}
	cached_diff : Try(List(WorkspaceGit.FileDiff), _)
	cached_diff = Json.parse(scope_diff.map_ok(|row| row.value) ?? "")
	diff =
		match poll.scope {
			Commit(sha) => ((commits ?? []).find_first(|commit| commit.sha == sha).map_ok(|commit| commit.files) ?? []).map(|file| { file, hunks: if (poll.file == Selected(file.path)) selected_hunks ?? [] else [] })
			_ => cached_diff ?? []
		}
	fingerprint =
		match (poll.scope, scope_diff) {
			(Commit(_), _) => WorkspaceGit.fingerprint(poll.scope, diff)
			(_, Ok(row)) => row.fingerprint
			(_, Err(NothingCached)) => WorkspaceGit.fingerprint(poll.scope, [])
		}
	Ok(known.map_ok(|{ workspace, status }| { workspace, status, fingerprint, diff, commits: commits ?? [] }).map_err(|_| NothingCached))
}

## Notes that a poll watches a Paseo directory's workspace, the poll's scope
## and, of a commit, the selected file not cached yet.
git_wanted! : Sqlite.Db, Str, WorkspaceGit.Asked => Try({}, _)
git_wanted! = |db, directory, poll| {
	wanted!(db, "workspace", directory)?
	match (poll.scope, selected_commit_file(poll)) {
		(Uncommitted, _) => wanted!(db, "uncommitted", directory)
		(AgainstBase, _) => wanted!(db, "base", directory)
		(_, Ok({ sha, path, what })) => if (cached!(db, directory, what)?.is_err()) wanted!(db, "commit_file", Json.to_str({ directory, sha, path })) else Ok({})
		_ => Ok({})
	}
}

## The file a poll of a commit selects, and what the git cache holds it as.
selected_commit_file : WorkspaceGit.Asked -> Try({ sha : Str, path : Str, what : Str }, [NoFile])
selected_commit_file = |poll|
	match (poll.scope, poll.file) {
		(Commit(sha), Selected(path)) => Ok({ sha, path, what: "commit ${sha} ${path}" })
		_ => Err(NoFile)
	}

## The built-in provider of what the daemon derives from the others' chat.v1.
liton_provider : Manifest.Provider
liton_provider = { id: "liton", name: "liton", capabilities: [Capability.attention_v1] }

## The same, as /liton/v1/manifest offers it.
attention_transformer : Manifest.Transformer
attention_transformer = { id: "attention", name: "Attention", offers: Capability.attention_v1, uses: [Capability.chat_v1] }

## Every session's attention item, ranked. Forgets the settles and snoozes
## that no longer hold, so an item that came back stays back.
attention_items! : Context => Try(List(Attention.Item), _)
attention_items! = |context| {
	db = context.db
	var $items = []
	for session in sessions!(context)? {
		$items = $items.append(Attention.item(session, visible!(db, session.id, 0)?))
	}
	asides : List(Attention.Aside)
	asides = Sqlite.query_many!({ db, query: "SELECT session_id, signature, snoozed_until FROM attention_asides;", params: {}, limits: Sqlite.default_query_limits })?
	now = now_ms!()
	for aside in asides.drop_if(|aside| Attention.holds(aside, $items, now)) {
		Sqlite.execute!({ db, query: "DELETE FROM attention_asides WHERE session_id = :session_id;", params: { session_id: aside.session_id } })?
	}
	Ok(Attention.ranked($items, asides, now))
}

attention! : Context, Server.Request => Try(Response, _)
attention! = |context, request| {
	decoded : Try(Attention.Request, _)
	decoded = Json.parse(read_json!(request)?)
	answer : Attention.Response
	answer =
		match decoded {
			Err(_) => Rejected("expected an attention.v1 request")
			Ok(asked) =>
				match attention_call!(context, asked)? {
					Ok(response) => response
					Err({ message, .. }) => Rejected(message)
				}
		}
	Ok(json(Json.to_str(answer)))
}

attention_call! : Context, Attention.Request => Try(Protocol.Answer(Attention.Response), _)
attention_call! = |context, asked|
	match asked {
		ListItems => Ok(Ok(Items(attention_items!(context)?)))
		Settle({ session_id, signature }) => set_aside!(context, { session_id, signature, snoozed_until: 0 })
		Snooze({ session_id, signature, minutes }) => set_aside!(context, { session_id, signature, snoozed_until: now_ms!() + minutes.to_i64() * 60_000 })
		Unsettle({ session_id }) => {
			Sqlite.execute!({ db: context.db, query: "DELETE FROM attention_asides WHERE session_id = :session_id;", params: { session_id: session_id } })?
			Ok(Ok(Accepted))
		}
	}

set_aside! : Context, Attention.Aside => Try(Protocol.Answer(Attention.Response), _)
set_aside! = |context, { session_id, signature, snoozed_until }|
	match provider!(context, session_id)? {
		NoSession => Ok(no_session(session_id))
		_ => {
			Sqlite.execute!({ db: context.db, query: "INSERT INTO attention_asides (session_id, signature, snoozed_until) VALUES (:session_id, :signature, :snoozed_until) ON CONFLICT (session_id) DO UPDATE SET signature = excluded.signature, snoozed_until = excluded.snoozed_until;", params: { session_id, signature, snoozed_until } })?
			Ok(Ok(Accepted))
		}
	}

## Every enabled provider's projects and workspaces, each workspace with its
## sessions and as urgent as the most urgent of them. Paseo's come from what
## the cycle last listed, its agents placed by the workspace each works in.
workspaces! : Context => Try(Workspaces.Listed, _)
workspaces! = |context| {
	db = context.db
	if context.paseo.is_ok() {
		wanted!(db, "workspace_list", "")?
	}
	items = sessions!(context)?.map(|session| Attention.item(session, []))
	from_mock = if (context.mock_enabled) { projects: Mock.projects, workspaces: Mock.workspaces } else { projects: [], workspaces: [] }
	from_paseo = if (context.paseo.is_ok()) paseo_listed!(db)? else { projects: [], workspaces: [] }
	placed : List({ id : Str, workspace_id : Str })
	placed = Sqlite.query_many!({ db, query: "SELECT id, workspace_id FROM sessions WHERE provider = 'paseo' ORDER BY position;", params: {}, limits: Sqlite.default_query_limits })?
	paseo_workspaces = from_paseo.workspaces.map(|shown| { ..shown, session_ids: placed.keep_if(|row| row.workspace_id == shown.id).map(|row| row.id) })
	Ok({ projects: from_mock.projects.concat(from_paseo.projects), workspaces: from_mock.workspaces.concat(paseo_workspaces).map(|shown| { ..shown, state: Workspaces.state(items, shown.session_ids) }) })
}

workspaces_request! : Context, Server.Request => Try(Response, _)
workspaces_request! = |context, request| {
	decoded : Try(Workspaces.Request, _)
	decoded = Json.parse(read_json!(request)?)
	answer : Workspaces.Response
	answer =
		match decoded {
			Ok(ListWorkspaces) => Listed(workspaces!(context)?)
			Err(_) => Rejected("expected a workspaces.v1 request")
		}
	Ok(json(Json.to_str(answer)))
}

## Paseo's projects and workspaces as the cycle last listed them, none before.
paseo_listed! : Sqlite.Db => Try(Workspaces.Listed, _)
paseo_listed! = |db| {
	rows : List({ value : Str })
	rows = Sqlite.query_many!({ db, query: "SELECT value FROM paseo_listings WHERE what = 'workspaces';", params: {}, limits: Sqlite.default_query_limits })?
	listed : Try(Workspaces.Listed, _)
	listed = Json.parse(rows.first().map_ok(|row| row.value) ?? "")
	Ok(listed ?? { projects: [], workspaces: [] })
}

now_ms! : () => I64
now_ms! = || (UnixTime.now!().nanos_since_epoch() // 1_000_000).to_i64_wrap()

create_tables! : Sqlite.Db => Try({}, _)
create_tables! = |db| {
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, agent TEXT NOT NULL, title TEXT NOT NULL, position INTEGER NOT NULL);", params: {} })?
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS entries (session_id TEXT NOT NULL, sequence INTEGER NOT NULL, visible_at INTEGER NOT NULL, event TEXT NOT NULL, PRIMARY KEY (session_id, sequence));", params: {} })?
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS paseo_states (session_id TEXT PRIMARY KEY, state TEXT NOT NULL);", params: {} })?
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS paseo_checks (what TEXT PRIMARY KEY, checked_at INTEGER NOT NULL);", params: {} })?
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS attention_asides (session_id TEXT PRIMARY KEY, signature TEXT NOT NULL, snoozed_until INTEGER NOT NULL);", params: {} })?
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS paseo_interests (kind TEXT NOT NULL, subject TEXT NOT NULL, wanted_at INTEGER NOT NULL, PRIMARY KEY (kind, subject));", params: {} })?
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS git_cache (directory TEXT NOT NULL, what TEXT NOT NULL, status TEXT NOT NULL, fingerprint TEXT NOT NULL, fetched_at INTEGER NOT NULL, value TEXT NOT NULL, PRIMARY KEY (directory, what));", params: {} })?
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS paseo_listings (what TEXT PRIMARY KEY, value TEXT NOT NULL);", params: {} })?
	# Sessions stored before Paseo came are all the mock provider's, and
	# Paseo's stored before git, workspaces or the WebSocket listing came have
	# no directory, workspace or listed status until listed again.
	for (column, definition) in [("provider", "TEXT NOT NULL DEFAULT 'mock'"), ("directory", "TEXT NOT NULL DEFAULT ''"), ("workspace_id", "TEXT NOT NULL DEFAULT ''"), ("status", "TEXT NOT NULL DEFAULT ''")] {
		existing : List({ name : Str })
		existing = Sqlite.query_many!({ db, query: "SELECT name FROM pragma_table_info('sessions') WHERE name = :column;", params: { column }, limits: Sqlite.default_query_limits })?
		if existing.is_empty() {
			Sqlite.execute!({ db, query: "ALTER TABLE sessions ADD COLUMN ${column} ${definition};", params: {} })?
		}
	}
	Ok({})
}

## Gives a database without mock sessions the mock provider's seed sessions.
seed! : Sqlite.Db => Try({}, _)
seed! = |db| {
	count : { count : I64 }
	count = Sqlite.query!({ db, query: "SELECT count(*) AS count FROM sessions WHERE provider = 'mock';", params: {}, limits: Sqlite.default_query_limits })?
	if count.count == 0 {
		for (seed, position) in Mock.seeds.map_with_index(|seed, position| (seed, position)) {
			Sqlite.execute!({ db, query: "INSERT INTO sessions (id, provider, agent, title, position) VALUES (:id, 'mock', :agent, :title, :position);", params: { id: seed.id, agent: seed.agent, title: seed.title, position: position.to_i64_wrap() } })?
			insert_events!(db, seed.id, 1, seed.events.map(|event| { delay_ms: 0, event }), 0)?
		}
	}
	Ok({})
}

insert_events! : Sqlite.Db, Str, U64, List(Mock.Scheduled), I64 => Try({}, _)
insert_events! = |db, session_id, first, scheduled, start| {
	for ({ delay_ms, event }, index) in scheduled.map_with_index(|item, index| (item, index)) {
		Sqlite.execute!({
			db,
			query: "INSERT INTO entries (session_id, sequence, visible_at, event) VALUES (:session_id, :sequence, :visible_at, :event);",
			params: { session_id, sequence: (first + index).to_i64_wrap(), visible_at: start + delay_ms.to_i64_wrap(), event: Json.to_str(event) },
		})?
	}
	Ok({})
}

## Stores what the provider schedules after a session's last event, so the
## events become visible in sequence order.
schedule! : Sqlite.Db, Str, (U64 -> List(Mock.Scheduled)) => Try({}, _)
schedule! = |db, session_id, plan| {
	last : { sequence : I64, visible_at : I64 }
	last = Sqlite.query!({ db, query: "SELECT coalesce(max(sequence), 0) AS sequence, coalesce(max(visible_at), 0) AS visible_at FROM entries WHERE session_id = :session_id;", params: { session_id }, limits: Sqlite.default_query_limits })?
	next = last.sequence.to_u64_wrap() + 1
	now = now_ms!()
	insert_events!(db, session_id, next, plan(next), if (now > last.visible_at) now else last.visible_at)
}

## The enabled provider a session belongs to.
provider! : Context, Str => Try([MockSession, PaseoSession(PaseoDaemon), NoSession], _)
provider! = |{ db, mock_enabled, paseo }, session_id| {
	rows : List({ provider : Str })
	rows = Sqlite.query_many!({ db, query: "SELECT provider FROM sessions WHERE id = :session_id;", params: { session_id }, limits: Sqlite.default_query_limits })?
	Ok(
		match (rows.first().map_ok(|row| row.provider), paseo) {
			(Ok("mock"), _) => if (mock_enabled) MockSession else NoSession
			(Ok("paseo"), Ok(daemon)) => PaseoSession(daemon)
			_ => NoSession
		},
	)
}

## Each watched session's entries after its `after`, once Paseo's watched
## sessions are synced when due (see `paseo_cycle!`).
timelines! : Context, List({ session_id : Str, after : U64 }) => Try(List({ session_id : Str, entries : List(Chat.Entry) }), _)
timelines! = |context, watches| {
	for { session_id, .. } in watches {
		interested!(context, Timeline(session_id))?
	}
	paseo_cycle!(context)?
	var $timelines = []
	for { session_id, after } in watches {
		$timelines = $timelines.append({ session_id, entries: visible!(context.db, session_id, after)? })
	}
	Ok($timelines)
}

visible! : Sqlite.Db, Str, U64 => Try(List(Chat.Entry), _)
visible! = |db, session_id, after| {
	rows : List({ sequence : I64, event : Str })
	rows = Sqlite.query_many!({
		db,
		query: "SELECT sequence, event FROM entries WHERE session_id = :session_id AND sequence > :after AND visible_at <= :now ORDER BY sequence;",
		params: { session_id, after: after.to_i64_wrap(), now: now_ms!() },
		limits: Sqlite.default_query_limits,
	})?
	rows.map_try(
		|row| {
			event : Try(Chat.Event, _)
			event = Json.parse(row.event)
			Ok({ sequence: row.sequence.to_u64_wrap(), event: event? })
		},
	)
}

## The mock sessions, then Paseo's.
sessions! : Context => Try(List(Chat.Session), _)
sessions! = |{ db, mock_enabled, paseo }| {
	rows : List({ id : Str, agent : Str, title : Str })
	rows = Sqlite.query_many!({ db, query: "SELECT id, agent, title FROM sessions WHERE provider = 'mock' ORDER BY position;", params: {}, limits: Sqlite.default_query_limits })?
	var $sessions = []
	for row in if (mock_enabled) rows else [] {
		$sessions = $sessions.append({ id: row.id, provider: Mock.provider.id, agent: row.agent, title: row.title, status: Mock.status(visible!(db, row.id, 0)?) })
	}
	if paseo.is_ok() {
		wanted!(db, "agent_list", "")?
		paseo_cycle!({ db, mock_enabled, paseo })?
		refused = refusal!(db)?.map_ok(|{ reason, .. }| [Paseo.refused_session(reason)]) ?? []
		Ok($sessions.concat(refused).concat(registered!(db)?))
	} else {
		Ok($sessions)
	}
}

## The Paseo agents the cycle last listed, with the status they were listed
## with, or, listed before it was kept, their last synced status.
registered! : Sqlite.Db => Try(List(Chat.Session), _)
registered! = |db| {
	rows : List({ id : Str, agent : Str, title : Str, status : Str })
	rows = Sqlite.query_many!({ db, query: "SELECT id, agent, title, status FROM sessions WHERE provider = 'paseo' ORDER BY position;", params: {}, limits: Sqlite.default_query_limits })?
	var $sessions = []
	for row in rows {
		listed : Try(Chat.Status, _)
		listed = Json.parse(row.status)
		status =
			match listed {
				Ok(known) => known
				Err(_) => state_of!(db, row.id)?.state.status
			}
		$sessions = $sessions.append({ id: row.id, provider: Paseo.provider.id, agent: row.agent, title: row.title, status })
	}
	Ok($sessions)
}

## How often, at most, the daemon runs a cycle (see `paseo_cycle!`), which
## lists Paseo's agents too. The UI polls every second, from every open tab;
## each sync was a new WebSocket session on Paseo, and one per second per tab
## kept Paseo's event loop busy enough that its own clients timed out.
paseo_interval_ms : I64
paseo_interval_ms = 3_000

## How long the daemon keeps asking Paseo about what a poll watched, such as
## a session's timeline or a directory's git status, after the last poll
## that did.
interest_ms : I64
interest_ms = 10_000

## How long a cycle may run before another can start: Paseo answers a
## directory's first status in seconds, and Tcp gives up after 30.
cycle_lease_ms : I64
cycle_lease_ms = 30_000

## How often, at most, the daemon asks Paseo for the sessions its providers
## keep: for each, Paseo may read a provider's history from disk.
importable_interval_ms : I64
importable_interval_ms = 60_000

## Notes that a poll watches `subject` as `kind`: "agent_list",
## "workspace_list" or "importable" (no subject), "timeline" (a session id), "workspace",
## "uncommitted" or "base" (a directory), or "commit_file". What no poll
## watched within `interest_ms` is asked about in a cycle at once.
wanted! : Sqlite.Db, Str, Str => Try({}, _)
wanted! = |db, kind, subject| {
	now = now_ms!()
	watched : List({ kind : Str })
	watched = Sqlite.query_many!({ db, query: "SELECT kind FROM paseo_interests WHERE kind = :kind AND subject = :subject AND wanted_at > :since;", params: { kind, subject, since: now - interest_ms }, limits: Sqlite.default_query_limits })?
	Sqlite.execute!({ db, query: "INSERT INTO paseo_interests (kind, subject, wanted_at) VALUES (:kind, :subject, :now) ON CONFLICT (kind, subject) DO UPDATE SET wanted_at = excluded.wanted_at;", params: { kind, subject, now } })?
	if (watched.is_empty()) forget_check!(db, "cycle") else Ok({})
}

## Whether `what` ran within `interval_ms`: a cycle ("cycle"), every
## `paseo_interval_ms`, or the importable sessions' listing ("importable"),
## every `importable_interval_ms`. If not, records that it runs now.
recently_checked! : Sqlite.Db, Str, I64 => Try(Bool, _)
recently_checked! = |db, what, interval_ms| {
	now = now_ms!()
	claimed : List({ what : Str })
	claimed = Sqlite.query_many!({ db, query: "INSERT INTO paseo_checks (what, checked_at) VALUES (:what, :now) ON CONFLICT (what) DO UPDATE SET checked_at = excluded.checked_at WHERE paseo_checks.checked_at <= :since RETURNING what;", params: { what, now, since: now - interval_ms }, limits: Sqlite.default_query_limits })?
	Ok(claimed.is_empty())
}

## Lets the next poll ask about `what` at once (after a send, say).
forget_check! : Sqlite.Db, Str => Try({}, _)
forget_check! = |db, what| Sqlite.execute!({ db, query: "DELETE FROM paseo_checks WHERE what = :what;", params: { what } })

logged! : Str => {}
logged! = |line| {
	_ = Stderr.line!(line)
	{}
}

## Sends one write, such as a prompt, over a connection of its own, and reads
## Paseo's answer to it with `answer`.
written! : PaseoDaemon, Str, Str, (Str, Str -> Try({}, _)) => Try({}, _)
written! = |daemon, request, request_id, answer| {
	connection = connected!(daemon, "liton-daemon-writes")?
	answered = exchange!(connection, request, request_id)
	_ = connection.write!(WebSocket.close(websocket_mask))
	answer(answered?, request_id)
}

## Paseo refusing a request or liton's password is `Refused`; any other
## failure, such as not reaching Paseo, `Unavailable`.
paseo_answer : Try({}, _) -> Protocol.Answer(Chat.Response)
paseo_answer = |outcome|
	match outcome {
		Ok({}) => Ok(Accepted)
		Err(Refused(reason)) => Err({ code: Refused, message: reason })
		Err(HelloRejected(reason)) => Err({ code: Refused, message: Paseo.refusal(reason) })
		Err(err) => Err({ code: Unavailable, message: "Paseo: ${Str.inspect(err)}" })
	}

## How long the daemon waits after Paseo refused its password before asking
## again, unless a poll watches something new or a send asks at once.
refused_wait_ms : I64
refused_wait_ms = 60_000

## Why Paseo last refused liton, and when, until a connection succeeds.
refusal! : Sqlite.Db => Try(Try({ reason : Str, at : I64 }, [NotRefused]), _)
refusal! = |db| {
	rows : List({ value : Str })
	rows = Sqlite.query_many!({ db, query: "SELECT value FROM paseo_listings WHERE what = 'refusal';", params: {}, limits: Sqlite.default_query_limits })?
	refused : Try({ reason : Str, at : I64 }, _)
	refused = Json.parse(rows.first().map_ok(|row| row.value) ?? "")
	Ok(refused.map_err(|_| NotRefused))
}

## A Paseo session's state from its last sync, and its JSON ("" before the first).
state_of! : Sqlite.Db, Str => Try({ stored : Str, state : Paseo.State }, _)
state_of! = |db, session_id| {
	rows : List({ state : Str })
	rows = Sqlite.query_many!({ db, query: "SELECT state FROM paseo_states WHERE session_id = :session_id;", params: { session_id }, limits: Sqlite.default_query_limits })?
	stored = rows.first().map_ok(|row| row.state) ?? ""
	decoded : Try(Paseo.State, _)
	decoded = Json.parse(stored)
	Ok({ stored, state: if (stored == "") Paseo.initial else decoded? })
}

## Appends a sync's events and stores its state, unless another sync of the
## session stored since `stored` was read: then only that one appends.
store! : Sqlite.Db, Str, Str, { state : Paseo.State, events : List(Chat.Event) } => Try({}, _)
store! = |db, session_id, stored, { state, events }| {
	transaction = Sqlite.begin!(db, Immediate)?
	swapped : List({ session_id : Str })
	swapped = transaction.query_many!({ query: "INSERT INTO paseo_states (session_id, state) VALUES (:session_id, :state) ON CONFLICT (session_id) DO UPDATE SET state = excluded.state WHERE paseo_states.state = :stored RETURNING session_id;", params: { session_id, state: Json.to_str(state), stored }, limits: Sqlite.default_query_limits })?
	if swapped.is_empty() {
		return transaction.rollback!()
	}
	last : { sequence : I64 }
	last = transaction.query!({ query: "SELECT coalesce(max(sequence), 0) AS sequence FROM entries WHERE session_id = :session_id;", params: { session_id }, limits: Sqlite.default_query_limits })?
	now = now_ms!()
	for (event, index) in events.map_with_index(|event, index| (event, index)) {
		transaction.execute!({ query: "INSERT INTO entries (session_id, sequence, visible_at, event) VALUES (:session_id, :sequence, :visible_at, :event);", params: { session_id, sequence: last.sequence + 1 + index.to_i64_wrap(), visible_at: now, event: Json.to_str(event) } })?
	}
	transaction.commit!()
}

## Asks Paseo, at most every `paseo_interval_ms`, about all that polls
## watched within `interest_ms`, over one WebSocket connection: its agents
## and its workspaces, each timeline's new entries, then each directory's
## status and, when due (see `PaseoGit.refresh`), its commits and diffs, then
## the commit files not cached yet. Nothing watched, no connection. A question
## that fails is logged and the next asked; a lost connection ends the cycle.
## Once Paseo refuses liton's password, the cycle waits `refused_wait_ms`.
paseo_cycle! : Context => Try({}, _)
paseo_cycle! = |{ db, paseo, .. }|
	match paseo {
		Err(Disabled) => Ok({})
		Ok(daemon) =>
			if recently_checked!(db, "cycle", paseo_interval_ms)? or (refusal!(db)?.map_ok(|{ at, .. }| at + refused_wait_ms) ?? 0) > now_ms!() {
				Ok({})
			} else {
				Sqlite.execute!({ db, query: "DELETE FROM paseo_interests WHERE wanted_at <= :since;", params: { since: now_ms!() - interest_ms } })?
				wanted : List({ kind : Str, subject : Str })
				wanted = Sqlite.query_many!({ db, query: "SELECT kind, subject FROM paseo_interests;", params: {}, limits: Sqlite.default_query_limits })?
				if !wanted.is_empty() {
					held!(db, now_ms!() + cycle_lease_ms)?
					match connected!(daemon, "liton-daemon") {
						Ok(connection) => {
							Sqlite.execute!({ db, query: "DELETE FROM paseo_listings WHERE what = 'refusal';", params: {} })?
							ordered = ["agent_list", "workspace_list", "importable", "timeline", "workspace", "uncommitted", "base", "commit_file"].fold([], |so_far, kind| so_far.concat(wanted.keep_if(|item| item.kind == kind)))
							asked_each!(db, connection, ordered, 1)
							_ = connection.write!(WebSocket.close(websocket_mask))
							{}
						}
						Err(HelloRejected(reason)) => {
							logged!("Paseo: ${Paseo.refusal(reason)}. Asking again in ${(refused_wait_ms // 1000).to_str()} s.")
							Sqlite.execute!({ db, query: "INSERT INTO paseo_listings (what, value) VALUES ('refusal', :value) ON CONFLICT (what) DO UPDATE SET value = excluded.value;", params: { value: Json.to_str({ reason, at: now_ms!() }) } })?
						}
						Err(err) => logged!("Paseo: connecting to its WebSocket failed: ${Str.inspect(err)}")
					}
					held!(db, now_ms!())?
				}
				Ok({})
			}
	}

## Keeps the next cycle from starting before `until`, `paseo_interval_ms`
## after it.
held! : Sqlite.Db, I64 => Try({}, _)
held! = |db, until| Sqlite.execute!({ db, query: "UPDATE paseo_checks SET checked_at = :until WHERE what = 'cycle';", params: { until } })

## A WebSocket connection to Paseo as `client_id`, once Paseo welcomed its
## hello. The password goes both in the WebSocket protocol and in the hello
## (see `Paseo.hello`). Paseo refusing it is `HelloRejected`.
connected! : PaseoDaemon, Str => Try(Tcp.Connection, _)
connected! = |daemon, client_id| {
	connection = Tcp.connect!(daemon.host, daemon.port)?
	connection.write_utf8!(WebSocket.handshake({ host: daemon.host, port: daemon.port, path: "/ws", protocol: Paseo.protocol(daemon.password), key: "bGl0b24tZGFlbW9uLWtleQ==" }))?
	status_line = connection.read_line!()?
	if !WebSocket.accepted(status_line) {
		return Err(HandshakeRefused(status_line.trim()))
	}
	skip_headers!(connection)?
	connection.write!(WebSocket.text(Paseo.hello(client_id, daemon.password), websocket_mask))?
	greeted!(connection)?
	Ok(connection)
}

## Waits for Paseo's welcome. Paseo 0.9, and 0.15 given a wrong password in
## the WebSocket protocol, close with 4401 instead of rejecting the hello.
greeted! : Tcp.Connection => Try({}, _)
greeted! = |connection|
	match message!(connection, []) {
		Ok(received) =>
			match Paseo.greeting(received) {
				Welcomed => Ok({})
				Rejected(reason) => Err(HelloRejected(reason))
				NotGreeting => greeted!(connection)
			}
		Err(ClosedByPaseo({ code: 4401, reason })) => Err(HelloRejected(reason))
		Err(err) => Err(err)
	}

## Asks about each of `wanted` in turn, the `number`th first, until the
## connection is lost.
asked_each! : Sqlite.Db, Tcp.Connection, List({ kind : Str, subject : Str }), U64 => {}
asked_each! = |db, connection, wanted, number|
	match wanted.first() {
		Err(_) => {}
		Ok({ kind, subject }) =>
			match asked!(db, connection, { kind, subject }, "liton-${number.to_str()}") {
				Err(ConnectionLost(err)) => logged!("Paseo: its WebSocket failed, asking about the ${kind} ${subject}: ${err}")
				outcome => {
					match outcome {
						Ok({}) => {}
						Err(err) => logged!("Paseo: asking about the ${kind} ${subject} failed: ${Str.inspect(err)}")
					}
					asked_each!(db, connection, wanted.drop_first(1), number + 1)
				}
			}
	}

## Asks Paseo about one thing a poll watched, and keeps the answer.
asked! : Sqlite.Db, Tcp.Connection, { kind : Str, subject : Str }, Str => Try({}, _)
asked! = |db, connection, { kind, subject }, request_id|
	match kind {
		"agent_list" => listed_agents!(db, connection, request_id)
		"workspace_list" => listed_workspaces!(db, connection, request_id)
		"importable" => listed_importable!(db, connection, request_id)
		"timeline" => fetch!(db, connection, subject, request_id, 10)
		"workspace" => checked_out!(db, connection, subject, request_id)
		"uncommitted" => diffed!(db, connection, subject, Uncommitted, request_id)
		"base" => diffed!(db, connection, subject, AgainstBase, request_id)
		"commit_file" => commit_file!(db, connection, subject, request_id)
		_ => Ok({})
	}

## Keeps the agents Paseo lists in the registry, in its order, with the
## title, status, directory and workspace of each, and drops those it no
## longer lists, such as archived ones.
listed_agents! : Sqlite.Db, Tcp.Connection, Str => Try({}, _)
listed_agents! = |db, connection, request_id| {
	listed = Paseo.agents_answer(exchange!(connection, Paseo.agents_request(request_id), request_id)?, request_id)?
	for ({ session, directory, workspace_id }, position) in listed.map_with_index(|agent, position| (agent, position)) {
		Sqlite.execute!({ db, query: "INSERT INTO sessions (id, provider, agent, title, position, directory, workspace_id, status) VALUES (:id, 'paseo', :agent, :title, :position, :directory, :workspace_id, :status) ON CONFLICT (id) DO UPDATE SET agent = excluded.agent, title = excluded.title, position = excluded.position, directory = excluded.directory, workspace_id = excluded.workspace_id, status = excluded.status;", params: { id: session.id, agent: session.agent, title: session.title, position: position.to_i64_wrap(), directory, workspace_id, status: Json.to_str(session.status) } })?
	}
	Sqlite.execute!({ db, query: "DELETE FROM sessions WHERE provider = 'paseo' AND id NOT IN (SELECT value FROM json_each(:ids));", params: { ids: Json.to_str(listed.map(|{ session, .. }| session.id)) } })
}

## Keeps the projects and workspaces Paseo lists.
listed_workspaces! : Sqlite.Db, Tcp.Connection, Str => Try({}, _)
listed_workspaces! = |db, connection, request_id| {
	listed = PaseoWorkspaces.answer(exchange!(connection, PaseoWorkspaces.request(request_id), request_id)?, request_id)?
	Sqlite.execute!({ db, query: "INSERT INTO paseo_listings (what, value) VALUES ('workspaces', :value) ON CONFLICT (what) DO UPDATE SET value = excluded.value;", params: { value: Json.to_str(listed) } })
}

## Keeps the sessions Paseo's providers keep, every `importable_interval_ms`
## at most.
listed_importable! : Sqlite.Db, Tcp.Connection, Str => Try({}, _)
listed_importable! = |db, connection, request_id|
	if recently_checked!(db, "importable", importable_interval_ms)? {
		Ok({})
	} else {
		listed = Paseo.importable_answer(exchange!(connection, Paseo.importable_request(request_id), request_id)?, request_id)?
		Sqlite.execute!({ db, query: "INSERT INTO paseo_listings (what, value) VALUES ('importable', :value) ON CONFLICT (what) DO UPDATE SET value = excluded.value;", params: { value: Json.to_str(listed) } })
	}

## GET /api/paseo/importable: the importable sessions, once a cycle asked.
importable_listed! : Context => Try(Response, _)
importable_listed! = |context| {
	interested!(context, Importable)?
	paseo_cycle!(context)?
	Ok(json(Json.to_str(importable!(context)?)))
}

## The sessions Paseo's providers keep that Paseo doesn't run, as the cycle
## last listed them (none before).
importable! : Context => Try(List(Chat.Importable), _)
importable! = |context| {
	rows : List({ value : Str })
	rows = Sqlite.query_many!({ db: context.db, query: "SELECT value FROM paseo_listings WHERE what = 'importable';", params: {}, limits: Sqlite.default_query_limits })?
	listed : Try(List(Chat.Importable), _)
	listed = Json.parse(rows.first().map_ok(|row| row.value) ?? "")
	Ok(if (context.paseo.is_ok()) listed ?? [] else [])
}

## Sends a request, and answers the message that answers it, skipping
## Paseo's others. Failing to write or read is `ConnectionLost`.
exchange! : Tcp.Connection, Str, Str => Try(Str, _)
exchange! = |connection, request, request_id| {
	connection.write!(WebSocket.text(request, websocket_mask)).map_err(|err| ConnectionLost(Str.inspect(err)))?
	reply!(connection, request_id)
}

reply! : Tcp.Connection, Str => Try(Str, _)
reply! = |connection, request_id| {
	answer = message!(connection, []).map_err(|err| ConnectionLost(Str.inspect(err)))?
	if (Paseo.answers_request(answer, request_id)) Ok(answer) else reply!(connection, request_id)
}

## What the git cache holds of a directory: "workspace" (its workspace and
## status), "commits", "uncommitted" or "base" (a diff), or
## "commit <sha> <path>" (a file's hunks), with the status it was fetched at.
Cached : { status : Str, fingerprint : Str, fetched_at : I64, value : Str }

cached! : Sqlite.Db, Str, Str => Try(Try(Cached, [NothingCached]), _)
cached! = |db, directory, what| {
	rows : List(Cached)
	rows = Sqlite.query_many!({ db, query: "SELECT status, fingerprint, fetched_at, value FROM git_cache WHERE directory = :directory AND what = :what;", params: { directory, what }, limits: Sqlite.default_query_limits })?
	Ok(rows.first().map_err(|_| NothingCached))
}

cache! : Sqlite.Db, Str, Str, { status : Str, fingerprint : Str, value : Str } => Try({}, _)
cache! = |db, directory, what, { status, fingerprint, value }|
	Sqlite.execute!({ db, query: "INSERT INTO git_cache (directory, what, status, fingerprint, fetched_at, value) VALUES (:directory, :what, :status, :fingerprint, :now, :value) ON CONFLICT (directory, what) DO UPDATE SET status = excluded.status, fingerprint = excluded.fingerprint, fetched_at = excluded.fetched_at, value = excluded.value;", params: { directory, what, status, fingerprint, now: now_ms!(), value } })

## When the cached `what` was fetched, and at what status.
fetched! : Sqlite.Db, Str, Str => Try(Try({ status : WorkspaceGit.Status, fetched_at : I64 }, [NothingCached]), _)
fetched! = |db, directory, what|
	match cached!(db, directory, what)? {
		Err(NothingCached) => Ok(Err(NothingCached))
		Ok(row) => {
			status : Try(WorkspaceGit.Status, _)
			status = Json.parse(row.status)
			Ok(status.map_ok(|parsed| { status: parsed, fetched_at: row.fetched_at }).map_err(|_| NothingCached))
		}
	}

## Asks for a directory's status and keeps it, then its commits when due.
checked_out! : Sqlite.Db, Tcp.Connection, Str, Str => Try({}, _)
checked_out! = |db, connection, directory, request_id| {
	checkout = PaseoGit.status_answer(exchange!(connection, PaseoGit.status_request(directory, request_id), request_id)?, directory, request_id)?
	cache!(db, directory, "workspace", { status: "", fingerprint: "", value: Json.to_str(checkout) })?
	match checkout.status {
		Status(status) if PaseoGit.refresh(Commits, fetched!(db, directory, "commits")?, status, now_ms!()) => {
			commits_id = "${request_id}-commits"
			commits = PaseoGit.commits_answer(exchange!(connection, PaseoGit.commits_request(directory, commits_id), commits_id)?, commits_id)?
			cache!(db, directory, "commits", { status: Json.to_str(status), fingerprint: "", value: Json.to_str(commits) })
		}
		_ => Ok({})
	}
}

## Fetches a directory's diff when due by the status just asked for.
diffed! : Sqlite.Db, Tcp.Connection, Str, WorkspaceGit.Scope, Str => Try({}, _)
diffed! = |db, connection, directory, scope, request_id| {
	what = if (scope == Uncommitted) "uncommitted" else "base"
	known : Try({ status : [Status(WorkspaceGit.Status), NoStatus] }, _)
	known = Json.parse(cached!(db, directory, "workspace")?.map_ok(|row| row.value) ?? "")
	match known.map_ok(|{ status }| status) {
		Ok(Status(status)) if PaseoGit.refresh(Diff, fetched!(db, directory, what)?, status, now_ms!()) => {
			# A diff Paseo can't make, such as against a base it can't find, is
			# kept empty, so it is asked for again only when a diff would be.
			answered = PaseoGit.diff_answer(exchange!(connection, PaseoGit.diff_request(directory, scope, request_id), request_id)?, request_id)
			cache!(db, directory, what, { status: Json.to_str(status), fingerprint: WorkspaceGit.fingerprint(scope, answered ?? []), value: Json.to_str(answered ?? []) })?
			answered.map_ok(|_| {})
		}
		_ => Ok({})
	}
}

## Fetches the hunks of a file in a commit, which never change, once.
commit_file! : Sqlite.Db, Tcp.Connection, Str, Str => Try({}, _)
commit_file! = |db, connection, subject, request_id| {
	decoded : Try({ directory : Str, sha : Str, path : Str }, _)
	decoded = Json.parse(subject)
	{ directory, sha, path } = decoded?
	what = "commit ${sha} ${path}"
	if cached!(db, directory, what)?.is_ok() {
		Ok({})
	} else {
		hunks = PaseoGit.commit_file_answer(exchange!(connection, PaseoGit.commit_file_request(directory, sha, path, request_id), request_id)?, request_id)?
		cache!(db, directory, what, { status: "", fingerprint: "", value: Json.to_str(hunks) })
	}
}

websocket_mask : List(U8)
websocket_mask = [0x6C, 0x69, 0x74, 0x6E]

## Reads the handshake response's headers, through the blank line.
skip_headers! : Tcp.Connection => Try({}, _)
skip_headers! = |connection| if (connection.read_line!()?.trim() == "") Ok({}) else skip_headers!(connection)

## Fetches the page after a session's state and stores what it adds, again
## while Paseo has newer entries, `pages` times at most.
fetch! : Sqlite.Db, Tcp.Connection, Str, Str, U64 => Try({}, _)
fetch! = |db, connection, session_id, request_id, pages| {
	known = state_of!(db, session_id)?
	page_id = "${request_id}-page-${pages.to_str()}"
	page = Paseo.timeline_page(exchange!(connection, Paseo.timeline_request(known.state, session_id, page_id), page_id)?, page_id)?
	snapshot =
		match page.agent {
			Ok(agent) => agent
			Err(Null) => {
				agent_id = "${page_id}-agent"
				Paseo.agent_snapshot(exchange!(connection, Paseo.agent_request(session_id, agent_id), agent_id)?, agent_id)?
			}
		}
	updated = Paseo.update(known.state, page, snapshot)
	if updated.state != known.state or !updated.events.is_empty() {
		store!(db, session_id, known.stored, updated)?
	}
	if (page.has_newer and pages > 1) fetch!(db, connection, session_id, request_id, pages - 1) else Ok({})
}

## The next text message, after `received` of its fragments, answering pings.
message! : Tcp.Connection, List(U8) => Try(Str, _)
message! = |connection, received| {
	first_two = connection.read_exactly!(2)?
	header = WebSocket.header(first_two.concat(connection.read_exactly!(WebSocket.header_rest_size(first_two))?))
	payload = WebSocket.unmask(read_bytes!(connection, header.length)?, header.mask)
	match header.opcode {
		Text | Continuation => if (header.fin) Str.from_utf8(received.concat(payload)) else message!(connection, received.concat(payload))
		Ping => {
			connection.write!(WebSocket.frame(Pong, payload, websocket_mask))?
			message!(connection, received)
		}
		Close => Err(ClosedByPaseo(WebSocket.closed(payload)))
		_ => message!(connection, received)
	}
}

## `count` bytes, read 8 MiB at a time, the most Tcp reads at once: a diff
## can be bigger.
read_bytes! : Tcp.Connection, U64 => Try(List(U8), _)
read_bytes! = |connection, count|
	if (count <= 8_388_608) connection.read_exactly!(count) else Ok(connection.read_exactly!(8_388_608)?.concat(read_bytes!(connection, count - 8_388_608)?))

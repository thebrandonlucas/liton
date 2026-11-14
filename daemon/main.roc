## liton's daemon: offers its providers' capabilities, chat.v1,
## workspace.git.v1, workspaces.v1 and files.v1, and those its transformers
## derive (transformers/), such as attention.v1 from chat.v1, at /liton/v1 in
## the capability protocol (docs/protocol.md), from what it keeps in SQLite,
## and serves the UI.
##
## LITON_PORT (default 8095), LITON_HOST (default 127.0.0.1), LITON_DB
## (default liton.db) and LITON_UI (default zig-out/www) configure it.
## LITON_MOCK=off leaves out the mock provider. Setting PASEO_PASSWORD adds
## the agents of the Paseo daemon at PASEO_HOST (default 127.0.0.1) and
## PASEO_PORT (default 6767), reached over its WebSocket alone.
##
## LITON_SETUP names the setup a Litonfile evaluates to (`liton setup`), by
## default liton.setup.json if there is one, or else liton's own
## (setup/Default.roc). It declares the remotes, the transformers and the
## presets the manifest offers clients.
##
## LITON_PROVIDERS adds providers outside the daemon to the setup's remotes,
## in place of those of the same name, each a server of /liton/v1 such as
## another liton daemon, comma-separated as `name=http://host:port` (or
## https://). Their providers, sessions and workspaces are named
## `<name>/<their id>`. The daemon asks each at most every
## LITON_PROVIDERS_INTERVAL_MS (default 1000) for all that polls watch of it,
## in one poll of its own.
##
## LITON_TRANSFORMERS adds transformers to the setup's, comma-separated:
## `attention`, attention.v1 from chat.v1, and `needs-you`, attention.v1's
## items that need you, as needs-you.v1.
##
## LITON_STT offers voice.v1, dictation, from a speech engine on the machine
## (providers/local-speech/, rig/speech/): `sherpa=ws://127.0.0.1:6006` for
## sherpa-onnx's offline WebSocket server, or `whisper=http://127.0.0.1:8178`
## for whisper.cpp's whisper-server. Unset, voice.v1 isn't offered.
app [Context, program] {
	cap: "../capabilities/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	mock: "../providers/mock/main.roc",
	paseo: "../providers/paseo/main.roc",
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.21.0/4viZsnWjdYsyH4Q87ESFAwM5c55Hnc15nAGW1UwzWpFU.tar.zst",
	remote: "../providers/remote/main.roc",
	setup: "../setup/main.roc",
	speech: "../providers/local-speech/main.roc",
	transformers: "../transformers/main.roc",
}

import pf.Env
import pf.Http
import pf.OsStr
import pf.Path
import pf.Server
import pf.Sqlite
import pf.Stderr
import pf.Tcp
import pf.UnixTime
import http.Request
import http.Response
import cap.Capability
import cap.Chat
import cap.Manifest
import cap.Protocol
import cap.Voice
import cap.WorkspaceGit
import cap.Workspaces
import mock.Mock
import paseo.Paseo
import paseo.PaseoFiles
import paseo.PaseoGit
import paseo.PaseoWorkspaces
import paseo.WebSocket
import remote.Remote
import setup.Default
import setup.Setup
import speech.LocalSpeech
import transformers.AttentionTransformer
import transformers.NeedsYou
import transformers.Transformer

Context : { db : Sqlite.Db, mock_enabled : Bool, paseo : Try(PaseoDaemon, [Disabled]), speech : Try(LocalSpeech.Engine, [Disabled]), remotes : List(Remote.Endpoint), remote_interval_ms : I64, transformers : List(Transformer.Part), setup : Setup.Offered }

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
	stt = env_or!("LITON_STT", "")
	speech = if (stt == "") Err(Disabled) else Ok(checked!(LocalSpeech.engine(stt))?)
	setup = checked!(setup!(env_or!("LITON_SETUP", "")))?
	remotes = checked!(Remote.declared(setup.remotes, env_or!("LITON_PROVIDERS", "")))?
	remote_interval_ms = I64.from_str(env_or!("LITON_PROVIDERS_INTERVAL_MS", "1000")) ?? 1_000
	ui = Server.file_root({ id: "ui", path: Path.utf8(env_or!("LITON_UI", "zig-out/www")) })
	config =
		Server.default_config
			.with_listen({ host, port })
			.with_file_roots([ui])
			.with_native_routes({ files: [Server.static_mount({ at: "/ui", files: ui })], liveness: [], readiness: [] })
	transformers = checked!(transformers_named(setup.transformers.concat(env_or!("LITON_TRANSFORMERS", "").split_on(","))))?
	context = { db, mock_enabled, paseo, speech, remotes, remote_interval_ms, transformers, setup: Setup.offered(setup) }
	# Each remote starts unasked, and its manifest is asked for at once.
	Sqlite.execute!({ db, query: "DELETE FROM remotes;", params: {} }) ? |_| Exit(3)
	for endpoint in remotes {
		Sqlite.execute!({ db, query: "INSERT INTO remotes (name) VALUES (:name);", params: { name: endpoint.name } }) ? |_| Exit(3)
		remote_cycle!(context, endpoint) ? |_| Exit(3)
	}
	Ok({ config, context })
}

## The setup at `named`, or at liton.setup.json if `named` is "" and there
## is one, or else liton's own.
setup! : Str => Try(Setup.Declared, Str)
setup! = |named| {
	path = if (named == "") "liton.setup.json" else named
	match Path.read_utf8!(Path.utf8(path)) {
		Ok(text) => Setup.from_json(text).map_err(|_| "${path} is not a setup, as `liton setup` writes from a Litonfile")
		Err(_) if named == "" => Ok(Default.setup)
		Err(problem) => Err("can't read the setup ${path}: ${Str.inspect(problem)}")
	}
}

## The transformers `named`, in the order each may use the one before.
transformers_named : List(Str) -> Try(List(Transformer.Part), Str)
transformers_named = |named| {
	ids = named.map(|id| id.trim()).drop_if(|id| id == "")
	known = [AttentionTransformer.part, NeedsYou.part]
	match ids.find_first(|id| !known.any(|part| part.id == id)) {
		Ok(unknown) => Err("no transformer is called ${unknown}; there are ${Str.join_with(known.map(|part| part.id), ", ")}")
		Err(NotFound) => Ok(known.keep_if(|part| ids.contains(part.id)))
	}
}

## What `given` holds, or else its problem on stderr and the daemon stopped.
checked! : Try(a, Str) => Try(a, [Exit(I64)])
checked! = |given|
	match given {
		Ok(value) => Ok(value)
		Err(problem) => {
			logged!(problem)
			Err(Exit(5))
		}
	}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64)])
shutdown! = |_reason, _context| Ok({})

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str)])
respond! = |request, context| {
	response =
		match (request.method(), request.target()) {
			(GET, Resource({ raw_path: "/", .. })) =>
				Ok(Response.from_status(302).with_headers([{ name: "Location", value: "/ui/index.html" }]))
			(GET, Resource({ raw_path: "/liton/v1/manifest", .. })) =>
				manifest!(context)
			(POST, Resource({ raw_path: "/liton/v1/call", .. })) =>
				call!(context, request)
			(POST, Resource({ raw_path: "/liton/v1/poll", .. })) =>
				polled_topics!(context, request)
			(POST, Resource({ raw_path, .. })) if raw_path.starts_with(audio_route) =>
				audio_chunk!(context, request, raw_path.drop_prefix(audio_route))
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

## Answers /liton/v1/manifest, once the remotes due are asked, with the
## presets the setup offers clients.
manifest! : Context => Try(Response, _)
manifest! = |context| {
	remotes_cycle!(context)?
	{ protocol, daemon, providers, transformers, topics } = offered!(context)?
	Ok(json(Json.to_str({ protocol, daemon, providers, transformers, topics, setup: context.setup })))
}

## What the daemon offers, with the providers of the remotes that are up.
offered! : Context => Try(Manifest.Offered, _)
offered! = |context| Ok(offered(context, remotes_up!(context)?.fold([], |so_far, up| so_far.concat(Remote.providers(up.name, up.advertised)))))

## What /liton/v1/manifest answers: the enabled providers, then the remotes',
## and the transformers whose capabilities they offer (see
## `Transformer.offered`).
offered : Context, List(Manifest.Provider) -> Manifest.Offered
offered = |{ mock_enabled, paseo, speech, transformers, .. }, remote_providers| {
	providers = (if (mock_enabled) [Mock.provider] else []).concat(if (paseo.is_ok()) [Paseo.provider] else []).concat(if (speech.is_ok()) [LocalSpeech.provider] else []).concat(remote_providers)
	provided = Manifest.capabilities({ protocol: Manifest.protocol, providers })
	offered_parts = Transformer.offered(transformers, provided)
	{ protocol: Manifest.protocol, daemon: { id: "liton", name: "liton" }, providers, transformers: offered_parts.map(Transformer.declared), topics: Protocol.topics.keep_if(|topics| provided.contains(topics.capability)).concat(offered_parts.map(|part| part.offers)) }
}

## The offered transformer whose capability a call or topic names.
transformer_of : Context, Manifest.Offered, Str -> Try(Transformer.Part, [NotTransformed])
transformer_of = |context, manifest, capability|
	context.transformers.find_first(|part| Capability.to_str(part.offers.capability) == capability and manifest.transformers.any(|offered_part| offered_part.id == part.id)).map_err(|_| NotTransformed)

## Answers a /liton/v1/call by its capability (see docs/protocol.md).
call! : Context, Server.Request => Try(Response, _)
call! = |context, request| {
	body = read_json!(request)?
	addressed : Try(Protocol.Addressed, _)
	addressed = Json.parse(body)
	manifest = offered!(context)?
	routed =
		match addressed {
			Ok(asked) => Protocol.routed(manifest, asked).map_ok(|id| (Capability.to_str(id), asked.provider))
			Err(_) => Err({ code: BadRequest, message: "expected a call, such as {\"capability\":\"chat.v1\",\"request\":\"ListSessions\"}" })
		}
	match routed.map_ok(|(capability, _)| transformer_of(context, manifest, capability)) {
		Ok(Ok(part)) => return Ok(json(transformer_call!(context, manifest, part, body)?))
		_ => {}
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
			Ok(("voice.v1", _)) => {
				decoded : Try(Protocol.Call(Voice.Request), _)
				decoded = Json.parse(body)
				answer : Protocol.Answer(Voice.Response)
				answer = match (decoded, context.speech) {
					(Ok({ request: asked, .. }), Ok(engine)) => voice_call!(context, engine, asked)?
					_ => Err(unanswered("voice.v1"))
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
			manifest = offered!(context)?
			for { capability, topic, .. } in topics {
				watched!(context, manifest, { capability, topic })?
			}
			paseo_cycle!(context)?
			remotes_cycle!(context)?
			var $updates = []
			for wanted in topics {
				$updates = $updates.append(topic_update!(context, manifest, wanted)?)
			}
			polled : Protocol.Polled
			polled = { topics: $updates }
			Ok(json(Json.to_str(polled)))
		}
	}
}

## Notes that a poll watches a topic's subject, so the next cycle asks Paseo
## about it.
interested! : Context, Protocol.Subject => Try({}, _)
interested! = |context, subject| {
	db = context.db
	match Remote.routed(context.remotes, subject) {
		Ok({ endpoint, subject: theirs }) => return remote_wanted!(db, endpoint.name, theirs)
		Err(Merged) =>
			for endpoint in context.remotes {
				for needed in Remote.merged(subject) {
					remote_wanted!(db, endpoint.name, needed)?
				}
			}
	}
	match subject {
		Timeline(session_id) =>
			match provider!(context, session_id)? {
				PaseoSession(_) => wanted!(db, "timeline", session_id)
				_ => Ok({})
			}
		Changes({ context: focus, scope }) => git_interested!(context, focus, { scope, file: NoFile })
		File({ context: focus, scope, path }) => git_interested!(context, focus, { scope, file: Selected(path) })
		Tree({ context: focus, path }) => files_interested!(context, focus, "tree", path)
		Contents({ context: focus, path }) => files_interested!(context, focus, "file", path)
		Importable if context.paseo.is_ok() => wanted!(db, "importable", "")
		WorkspaceList if context.paseo.is_ok() => {
			wanted!(db, "agent_list", "")?
			wanted!(db, "workspace_list", "")
		}
		VoiceStatus => Ok({})
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

## Notes that a poll watches a directory's listing ("tree") or a file
## ("file") of a context's workspace.
files_interested! : Context, [Session(Str), Workspace(Str)], Str, Str => Try({}, _)
files_interested! = |context, focus, kind, path|
	match located!(context, focus)? {
		PaseoDirectory(directory) => wanted!(context.db, kind, Json.to_str({ directory, path }))
		_ => Ok({})
	}

## A files.v1 topic's event: the directory (`Tree`) or file (`Contents`) at
## `path` of a context's workspace, as its provider has it; `Unknown` while
## Paseo hasn't answered, or there is no workspace.
explored! : Context, [Tree, Contents], [Session(Str), Workspace(Str)], Str => Try(Protocol.Event, _)
explored! = |context, what, focus, path| {
	unknown = if (what == Tree) Tree({ path, listing: Unknown }) else Contents({ path, read: Unknown })
	match located!(context, focus)? {
		MockWorkspace(_) => Ok(if (what == Tree) Tree(Mock.tree(path)) else Contents(Mock.contents(path)))
		PaseoDirectory(directory) => {
			cached : Try(Protocol.Event, _)
			cached = Json.parse(file_cached!(context.db, directory, "${if (what == Tree) "tree" else "file"} ${path}")?.map_ok(|row| row.value) ?? "")
			Ok(cached ?? unknown)
		}
		Nowhere => Ok(unknown)
	}
}

## A topic's update: a timeline's entries after its cursor, or a snapshot of
## anything else.
update! : Context, Protocol.Wanted, Protocol.Subject => Try(Protocol.Update, _)
update! = |context, wanted, subject| {
	match Remote.routed(context.remotes, subject) {
		Ok({ endpoint, subject: theirs }) => return remote_update!(context, wanted, endpoint, theirs)
		Err(Merged) => {}
	}
	match subject {
		Sessions => Ok(Protocol.snapshot(wanted, Sessions(sessions!(context)?)))
		Timeline(session_id) =>
			match Protocol.sequence(wanted) {
				Ok(after) => Ok(Protocol.appended(wanted, visible!(context.db, session_id, after)?))
				Err(error) => Ok(Protocol.failed(wanted, error))
			}
		# A transformer offers attention.v1 (see `topic_update!`), never a provider.
		Items => Ok(Protocol.failed(wanted, { code: Unsupported, message: "no provider offers ${wanted.capability}" }))
		WorkspaceList => Ok(Protocol.snapshot(wanted, Listed(workspaces!(context)?)))
		Importable => Ok(Protocol.snapshot(wanted, Importable(importable!(context)?)))
		Changes({ context: focus, scope }) => Ok(Protocol.snapshot(wanted, Changes(WorkspaceGit.snapshot(scope, git_found!(context, focus, { scope, file: NoFile })?))))
		File({ context: focus, scope, path }) => Ok(Protocol.snapshot(wanted, File(WorkspaceGit.file_hunks(path, git_found!(context, focus, { scope, file: Selected(path) })?))))
		Tree({ context: focus, path }) => Ok(Protocol.snapshot(wanted, explored!(context, Tree, focus, path)?))
		Contents({ context: focus, path }) => Ok(Protocol.snapshot(wanted, explored!(context, Contents, focus, path)?))
		VoiceStatus => Ok(Protocol.snapshot(wanted, Status({ stt: speech_status!(context)? })))
	}
}

## A topic of a remote's session or workspace, from what the remote last
## answered: a timeline's entries kept as the session's, or the last
## snapshot; no events before the remote answered. A remote that is down
## fails the topic `Unavailable`, and one that offers no such capability
## `Unsupported`.
remote_update! : Context, Protocol.Wanted, Remote.Endpoint, Protocol.Subject => Try(Protocol.Update, _)
remote_update! = |context, wanted, endpoint, theirs| {
	named = Protocol.named(theirs)
	offers = remotes_up!(context)?.find_first(|up| up.name == endpoint.name).map_ok(|up| Manifest.capabilities(up.advertised))
	rows : List({ event : Str, error : Str })
	rows = Sqlite.query_many!({ db: context.db, query: "SELECT event, error FROM remote_topics WHERE remote = :remote AND capability = :capability AND topic = :topic;", params: { remote: endpoint.name, capability: named.capability, topic: named.topic }, limits: Sqlite.default_query_limits })?
	failure : Try(Protocol.Error, _)
	failure = Json.parse(rows.first().map_ok(|row| row.error) ?? "")
	event : Try(Protocol.Event, _)
	event = Json.parse(rows.first().map_ok(|row| row.event) ?? "")
	match (offers, failure, theirs) {
		(Err(_), _, _) => Ok(Protocol.failed(wanted, { code: Unavailable, message: "the provider ${endpoint.name} can't be reached" }))
		(Ok(capabilities), _, _) if !capabilities.contains(Capability.from_str(named.capability) ?? Capability.chat_v1) => Ok(Protocol.failed(wanted, { code: Unsupported, message: "the provider ${endpoint.name} offers no ${named.capability}" }))
		(_, Ok(error), _) => Ok(Protocol.failed(wanted, error))
		(_, _, Timeline(session_id)) =>
			match Protocol.sequence(wanted) {
				Ok(after) => Ok(Protocol.appended(wanted, visible!(context.db, Remote.prefixed(endpoint.name, session_id), after)?))
				Err(error) => Ok(Protocol.failed(wanted, error))
			}
		_ =>
			match event {
				Ok(answered) => Ok(Protocol.snapshot(wanted, Remote.event(endpoint.name, answered)))
				Err(_) => Ok({ capability: wanted.capability, topic: wanted.topic, cursor: wanted.after, events: [], error: Err(Missing) })
			}
	}
}

## Answers a chat.v1 request, of `provider`'s sessions alone if it names one.
chat_call! : Context, Try(Str, [Missing]), Chat.Request => Try(Protocol.Answer(Chat.Response), _)
chat_call! = |context, provider, asked| {
	db = context.db
	match Remote.chat_owner(context.remotes, asked) {
		Ok(endpoint) if Remote.serves(endpoint.name, provider) => return Ok(forwarded!(endpoint, provider, asked))
		_ => {}
	}
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
		Cancel({ session_id }) =>
			match routed_provider!(context, provider, session_id)? {
				MockSession => {
					Sqlite.execute!({ db, query: "DELETE FROM entries WHERE session_id = :session_id AND visible_at > :now;", params: { session_id, now: now_ms!() } })?
					timeline = visible!(db, session_id, 0)?
					schedule!(db, session_id, |_| Mock.on_cancel(timeline))?
					Ok(Ok(Accepted))
				}
				PaseoSession(daemon) => {
					request_id = "liton-cancel-${now_ms!().to_str()}"
					outcome = written!(daemon, Paseo.cancel_request(session_id, request_id), request_id, Paseo.canceled)
					forget_check!(db, "cycle")?
					Ok(paseo_answer(outcome))
				}
				NoSession => Ok(no_session(session_id))
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

## Notes that a poll watches a topic: a provider's subject, or what a
## transformer offering it uses, as a client's poll of those would.
watched! : Context, Manifest.Offered, Transformer.Topic => Try({}, _)
watched! = |context, manifest, { capability, topic }|
	match transformer_of(context, manifest, capability) {
		Ok(part) => {
			for used in part.uses {
				watched!(context, manifest, used)?
			}
			Ok({})
		}
		Err(_) =>
			match Protocol.subject(manifest, { capability, topic, after: "" }) {
				Ok(subject) => interested!(context, subject)
				Err(_) => Ok({})
			}
	}

## A topic's update: from the transformer that offers it, or of its subject.
topic_update! : Context, Manifest.Offered, Protocol.Wanted => Try(Protocol.Update, _)
topic_update! = |context, manifest, wanted|
	match transformer_of(context, manifest, wanted.capability) {
		Ok(part) => Ok(Transformer.update(derived!(context, manifest, part)?.topics, wanted))
		Err(_) =>
			match Protocol.subject(manifest, wanted) {
				Ok(subject) => update!(context, wanted, subject)
				Err(error) => Ok(Protocol.failed(wanted, error))
			}
	}

## A transformer's inputs: the events the daemon has of the topics it uses,
## then of those they lead it to follow, read from what the daemon keeps.
inputs! : Context, Manifest.Offered, Transformer.Part => Try(List(Transformer.Input), _)
inputs! = |context, manifest, part| {
	read! = |topics| topics.map_try(|{ capability, topic }| Ok({ capability, topic, events: topic_update!(context, manifest, { capability, topic, after: "" })?.events }))
	used = read!(part.uses)?
	Ok(used.concat(read!((part.follows)(used))?))
}

## What a transformer derives now, its state stored when that changed.
derived! : Context, Manifest.Offered, Transformer.Part => Try({ state : Str, topics : List(Transformer.Derived) }, _)
derived! = |context, manifest, part| {
	inputs = inputs!(context, manifest, part)?
	stored = transformer_state!(context.db, part.id)?
	derived = (part.derive)(inputs, stored, now_ms!())
	_ = state_swapped!(context.db, part.id, stored, derived.state)?
	Ok(derived)
}

## Answers a call to a transformer's capability, storing the state it leaves,
## or asking it again when a request stored another since its state was read.
transformer_call! : Context, Manifest.Offered, Transformer.Part, Str => Try(Str, _)
transformer_call! = |context, manifest, part, body| {
	inputs = inputs!(context, manifest, part)?
	answered! = || {
		stored = transformer_state!(context.db, part.id)?
		called = (part.call)(inputs, stored, body, now_ms!())
		if (state_swapped!(context.db, part.id, stored, called.state)?) Ok(called.answer) else answered!()
	}
	answered!()
}

## A transformer's state as last stored, "" before.
transformer_state! : Sqlite.Db, Str => Try(Str, _)
transformer_state! = |db, transformer| {
	rows : List({ state : Str })
	rows = Sqlite.query_many!({ db, query: "SELECT state FROM transformer_states WHERE transformer = :transformer;", params: { transformer }, limits: Sqlite.default_query_limits })?
	Ok(rows.first().map_ok(|row| row.state) ?? "")
}

## Stores a transformer's state unless another was stored since `stored` was
## read, and says whether it did.
state_swapped! : Sqlite.Db, Str, Str, Str => Try(Bool, _)
state_swapped! = |db, transformer, stored, state|
	if state == stored {
		Ok(Bool.True)
	} else {
		swapped : List({ transformer : Str })
		swapped = Sqlite.query_many!({ db, query: "INSERT INTO transformer_states (transformer, state) VALUES (:transformer, :state) ON CONFLICT (transformer) DO UPDATE SET state = excluded.state WHERE transformer_states.state = :stored RETURNING transformer;", params: { transformer, state, stored }, limits: Sqlite.default_query_limits })?
		Ok(!swapped.is_empty())
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
	sessions = sessions!(context)?
	from_mock = if (context.mock_enabled) { projects: Mock.projects, workspaces: Mock.workspaces } else { projects: [], workspaces: [] }
	from_paseo = if (context.paseo.is_ok()) paseo_listed!(db)? else { projects: [], workspaces: [] }
	placed : List({ id : Str, workspace_id : Str })
	placed = Sqlite.query_many!({ db, query: "SELECT id, workspace_id FROM sessions WHERE provider = 'paseo' ORDER BY position;", params: {}, limits: Sqlite.default_query_limits })?
	paseo_workspaces = from_paseo.workspaces.map(|shown| { ..shown, session_ids: placed.keep_if(|row| row.workspace_id == shown.id).map(|row| row.id) })
	# A remote's workspaces come with the state it counted.
	from_remotes = merged_events!(context, WorkspaceList)?.fold(
		{ projects: [], workspaces: [] },
		|so_far, event| match event {
			Listed(listed) => { projects: so_far.projects.concat(listed.projects), workspaces: so_far.workspaces.concat(listed.workspaces) }
			_ => so_far
		},
	)
	Ok({ projects: from_mock.projects.concat(from_paseo.projects).concat(from_remotes.projects), workspaces: from_mock.workspaces.concat(paseo_workspaces).map(|shown| { ..shown, state: Workspaces.state(sessions, shown.session_ids) }).concat(from_remotes.workspaces) })
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
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS transformer_states (transformer TEXT PRIMARY KEY, state TEXT NOT NULL);", params: {} })?
	# Settles and snoozes kept before transformers came are attention's state.
	asides : List({ name : Str })
	asides = Sqlite.query_many!({ db, query: "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'attention_asides';", params: {}, limits: Sqlite.default_query_limits })?
	if !asides.is_empty() {
		Sqlite.execute!({ db, query: "INSERT OR IGNORE INTO transformer_states (transformer, state) SELECT 'attention', json_group_array(json_object('session_id', session_id, 'signature', signature, 'snoozed_until', snoozed_until)) FROM attention_asides;", params: {} })?
		Sqlite.execute!({ db, query: "DROP TABLE attention_asides;", params: {} })?
	}
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS paseo_interests (kind TEXT NOT NULL, subject TEXT NOT NULL, wanted_at INTEGER NOT NULL, PRIMARY KEY (kind, subject));", params: {} })?
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS git_cache (directory TEXT NOT NULL, what TEXT NOT NULL, status TEXT NOT NULL, fingerprint TEXT NOT NULL, fetched_at INTEGER NOT NULL, value TEXT NOT NULL, PRIMARY KEY (directory, what));", params: {} })?
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS paseo_listings (what TEXT PRIMARY KEY, value TEXT NOT NULL);", params: {} })?
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS file_cache (directory TEXT NOT NULL, what TEXT NOT NULL, fetched_at INTEGER NOT NULL, value TEXT NOT NULL, PRIMARY KEY (directory, what));", params: {} })?
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS remotes (name TEXT PRIMARY KEY, manifest TEXT NOT NULL DEFAULT '', manifest_at INTEGER NOT NULL DEFAULT 0, checked_at INTEGER NOT NULL DEFAULT 0, failures INTEGER NOT NULL DEFAULT 0);", params: {} })?
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS remote_topics (remote TEXT NOT NULL, capability TEXT NOT NULL, topic TEXT NOT NULL, wanted_at INTEGER NOT NULL, cursor TEXT NOT NULL DEFAULT '', event TEXT NOT NULL DEFAULT '', error TEXT NOT NULL DEFAULT '', PRIMARY KEY (remote, capability, topic));", params: {} })?
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS voice_chunks (utterance_id TEXT NOT NULL, seq INTEGER NOT NULL, pcm BLOB NOT NULL, at INTEGER NOT NULL, PRIMARY KEY (utterance_id, seq));", params: {} })?
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS voice_transcripts (utterance_id TEXT PRIMARY KEY, text TEXT NOT NULL, at INTEGER NOT NULL);", params: {} })?
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS voice_status (engine TEXT PRIMARY KEY, status TEXT NOT NULL, checked_at INTEGER NOT NULL);", params: {} })?
	# Sessions stored before Paseo came are all the mock provider's, and
	# Paseo's stored before git, workspaces or the WebSocket listing came have
	# no directory, workspace or listing until listed again.
	for (column, definition) in [("provider", "TEXT NOT NULL DEFAULT 'mock'"), ("directory", "TEXT NOT NULL DEFAULT ''"), ("workspace_id", "TEXT NOT NULL DEFAULT ''"), ("listed", "TEXT NOT NULL DEFAULT ''")] {
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
			insert_events!(db, seed.id, 1, seed.events.map(|event| { delay_ms: 0, event }), now_ms!())?
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
provider! = |{ db, mock_enabled, paseo, .. }, session_id| {
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

## The mock sessions, then Paseo's, then each remote's.
sessions! : Context => Try(List(Chat.Session), _)
sessions! = |context| {
	{ db, mock_enabled, paseo, .. } = context
	rows : List({ id : Str, agent : Str, title : Str })
	rows = Sqlite.query_many!({ db, query: "SELECT id, agent, title FROM sessions WHERE provider = 'mock' ORDER BY position;", params: {}, limits: Sqlite.default_query_limits })?
	var $sessions = []
	for row in if (mock_enabled) rows else [] {
		timed : List({ visible_at : I64, event : Str })
		timed = Sqlite.query_many!({ db, query: "SELECT visible_at, event FROM entries WHERE session_id = :session_id AND visible_at <= :now ORDER BY sequence;", params: { session_id: row.id, now: now_ms!() }, limits: Sqlite.default_query_limits })?
		events = timed.map_try(
			|{ visible_at, event }| {
				parsed : Try(Chat.Event, _)
				parsed = Json.parse(event)
				parsed.map_ok(|known| { visible_at, event: known })
			},
		)?
		$sessions = $sessions.append(Mock.session({ id: row.id, agent: row.agent, title: row.title }, events))
	}
	if paseo.is_ok() {
		wanted!(db, "agent_list", "")?
		paseo_cycle!(context)?
		refused = refusal!(db)?.map_ok(|{ reason, .. }| [Paseo.refused_session(reason)]) ?? []
		$sessions = $sessions.concat(refused).concat(registered!(db)?)
	}
	remote_sessions = merged_events!(context, Sessions)?.fold(
		[],
		|so_far, event| match event {
			Sessions(listed) => so_far.concat(listed)
			_ => so_far
		},
	)
	Ok($sessions.concat(remote_sessions))
}

## The Paseo agents the cycle last listed, as they were listed, or, listed
## before that was kept, with their last synced status.
registered! : Sqlite.Db => Try(List(Chat.Session), _)
registered! = |db| {
	rows : List({ id : Str, agent : Str, title : Str, listed : Str })
	rows = Sqlite.query_many!({ db, query: "SELECT id, agent, title, listed FROM sessions WHERE provider = 'paseo' ORDER BY position;", params: {}, limits: Sqlite.default_query_limits })?
	var $sessions = []
	for row in rows {
		listed : Try(Chat.Session, _)
		listed = Json.parse(row.listed)
		session =
			match listed {
				Ok(known) => known
				Err(_) => Chat.session({ id: row.id, provider: Paseo.provider.id, agent: row.agent, title: row.title, status: state_of!(db, row.id)?.state.status })
			}
		$sessions = $sessions.append(session)
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
## "uncommitted" or "base" (a directory), "commit_file", or "tree" or "file"
## (a directory and a path in it). What no poll watched within `interest_ms`
## is asked about in a cycle at once.
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
## the commit files not cached yet, then the listings and files fetched
## `PaseoFiles.lifetime_ms` ago or never. Nothing watched, no connection. A
## question that fails is logged and the next asked; a lost connection ends
## the cycle.
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
				Sqlite.execute!({ db, query: "DELETE FROM file_cache WHERE fetched_at <= :since;", params: { since: now_ms!() - file_cache_ms } })?
				wanted : List({ kind : Str, subject : Str })
				wanted = Sqlite.query_many!({ db, query: "SELECT kind, subject FROM paseo_interests;", params: {}, limits: Sqlite.default_query_limits })?
				if !wanted.is_empty() {
					held!(db, now_ms!() + cycle_lease_ms)?
					match connected!(daemon, "liton-daemon") {
						Ok(connection) => {
							Sqlite.execute!({ db, query: "DELETE FROM paseo_listings WHERE what = 'refusal';", params: {} })?
							ordered = ["agent_list", "workspace_list", "importable", "timeline", "workspace", "uncommitted", "base", "commit_file", "tree", "file"].fold([], |so_far, kind| so_far.concat(wanted.keep_if(|item| item.kind == kind)))
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
		"tree" => explored_by_paseo!(db, connection, kind, subject, request_id)
		"file" => explored_by_paseo!(db, connection, kind, subject, request_id)
		_ => Ok({})
	}

## Keeps the agents Paseo lists in the registry, in its order, with the
## title, status, directory and workspace of each, and drops those it no
## longer lists, such as archived ones.
listed_agents! : Sqlite.Db, Tcp.Connection, Str => Try({}, _)
listed_agents! = |db, connection, request_id| {
	listed = Paseo.agents_answer(exchange!(connection, Paseo.agents_request(request_id), request_id)?, request_id)?
	for ({ session, directory, workspace_id }, position) in listed.map_with_index(|agent, position| (agent, position)) {
		Sqlite.execute!({ db, query: "INSERT INTO sessions (id, provider, agent, title, position, directory, workspace_id, listed) VALUES (:id, 'paseo', :agent, :title, :position, :directory, :workspace_id, :listed) ON CONFLICT (id) DO UPDATE SET agent = excluded.agent, title = excluded.title, position = excluded.position, directory = excluded.directory, workspace_id = excluded.workspace_id, listed = excluded.listed;", params: { id: session.id, agent: session.agent, title: session.title, position: position.to_i64_wrap(), directory, workspace_id, listed: Json.to_str(session) } })?
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

## The sessions Paseo's providers keep that Paseo doesn't run, as the cycle
## last listed them (none before), then the remotes' importable sessions.
importable! : Context => Try(List(Chat.Importable), _)
importable! = |context| {
	rows : List({ value : Str })
	rows = Sqlite.query_many!({ db: context.db, query: "SELECT value FROM paseo_listings WHERE what = 'importable';", params: {}, limits: Sqlite.default_query_limits })?
	listed : Try(List(Chat.Importable), _)
	listed = Json.parse(rows.first().map_ok(|row| row.value) ?? "")
	from_remotes = merged_events!(context, Importable)?.fold(
		[],
		|so_far, event| match event {
			Importable(kept) => so_far.concat(kept)
			_ => so_far
		},
	)
	Ok((if (context.paseo.is_ok()) listed ?? [] else []).concat(from_remotes))
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

## How long the daemon keeps a listing or a file no poll watches any more.
file_cache_ms : I64
file_cache_ms = 600_000

## Fetches a directory's listing ("tree") or a file ("file") a poll watched,
## unless it was fetched within `PaseoFiles.lifetime_ms`, and keeps it as its
## topic's event.
explored_by_paseo! : Sqlite.Db, Tcp.Connection, Str, Str, Str => Try({}, _)
explored_by_paseo! = |db, connection, kind, subject, request_id| {
	decoded : Try({ directory : Str, path : Str }, _)
	decoded = Json.parse(subject)
	{ directory, path } = decoded?
	what = "${kind} ${path}"
	since = now_ms!() - PaseoFiles.lifetime_ms
	if file_cached!(db, directory, what)?.map_ok(|row| row.fetched_at > since) ?? Bool.False {
		Ok({})
	} else {
		event : Protocol.Event
		event =
			if kind == "tree" {
				Tree(PaseoFiles.tree_answer(exchange!(connection, PaseoFiles.tree_request(directory, path, request_id), request_id)?, path, request_id)?)
			} else {
				Contents(PaseoFiles.contents_answer(exchange!(connection, PaseoFiles.contents_request(directory, path, request_id), request_id)?, path, request_id)?)
			}
		Sqlite.execute!({ db, query: "INSERT INTO file_cache (directory, what, fetched_at, value) VALUES (:directory, :what, :now, :value) ON CONFLICT (directory, what) DO UPDATE SET fetched_at = excluded.fetched_at, value = excluded.value;", params: { directory, what, now: now_ms!(), value: Json.to_str(event) } })
	}
}

## What the file cache holds of a directory: "tree <path>" or "file <path>",
## a files.v1 topic's event.
file_cached! : Sqlite.Db, Str, Str => Try(Try({ fetched_at : I64, value : Str }, [NothingCached]), _)
file_cached! = |db, directory, what| {
	rows : List({ fetched_at : I64, value : Str })
	rows = Sqlite.query_many!({ db, query: "SELECT fetched_at, value FROM file_cache WHERE directory = :directory AND what = :what;", params: { directory, what }, limits: Sqlite.default_query_limits })?
	Ok(rows.first().map_err(|_| NothingCached))
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

## How long the daemon waits for a remote's answer, and how long a remote's
## cycle may run before another can start.
remote_timeout_ms : I64
remote_timeout_ms = 5_000

## How often, at most, the daemon asks a remote for its manifest again.
remote_manifest_ms : I64
remote_manifest_ms = 60_000

## Notes that a poll watches a remote's topic, as the remote names it.
remote_wanted! : Sqlite.Db, Str, Protocol.Subject => Try({}, _)
remote_wanted! = |db, remote, subject| {
	named = Protocol.named(subject)
	Sqlite.execute!({ db, query: "INSERT INTO remote_topics (remote, capability, topic, wanted_at) VALUES (:remote, :capability, :topic, :now) ON CONFLICT (remote, capability, topic) DO UPDATE SET wanted_at = excluded.wanted_at;", params: { remote, capability: named.capability, topic: named.topic, now: now_ms!() } })
}

## The remotes that answered when last asked, in LITON_PROVIDERS's order,
## with what they offer.
remotes_up! : Context => Try(List({ name : Str, advertised : Manifest.Advertised }), _)
remotes_up! = |context| {
	rows : List({ name : Str, manifest : Str })
	rows = Sqlite.query_many!({ db: context.db, query: "SELECT name, manifest FROM remotes WHERE failures = 0 AND manifest != '';", params: {}, limits: Sqlite.default_query_limits })?
	var $up = []
	for endpoint in context.remotes {
		advertised : Try(Manifest.Advertised, _)
		advertised = Json.parse(rows.find_first(|row| row.name == endpoint.name).map_ok(|row| row.manifest) ?? "")
		match advertised {
			Ok(parsed) => {
				$up = $up.append({ name: endpoint.name, advertised: parsed })
			}
			Err(_) => {}
		}
	}
	Ok($up)
}

## What each remote that is up last answered of `subject`, a list liton
## merges, its ids under the remote's name. Notes that the remotes' lists are
## watched, and asks the remotes when due.
merged_events! : Context, Protocol.Subject => Try(List(Protocol.Event), _)
merged_events! = |context, subject| {
	for endpoint in context.remotes {
		for needed in Remote.merged(subject) {
			remote_wanted!(context.db, endpoint.name, needed)?
		}
	}
	remotes_cycle!(context)?
	named = Protocol.named(subject)
	var $events = []
	for up in remotes_up!(context)? {
		rows : List({ event : Str })
		rows = Sqlite.query_many!({ db: context.db, query: "SELECT event FROM remote_topics WHERE remote = :remote AND capability = :capability AND topic = :topic AND error = '';", params: { remote: up.name, capability: named.capability, topic: named.topic }, limits: Sqlite.default_query_limits })?
		event : Try(Protocol.Event, _)
		event = Json.parse(rows.first().map_ok(|row| row.event) ?? "")
		match event {
			Ok(answered) => {
				$events = $events.append(Remote.event(up.name, answered))
			}
			Err(_) => {}
		}
	}
	Ok($events)
}

## Forwards a chat.v1 call to the remote whose session it names. A remote
## that can't be reached, or answers what isn't an answer, is `Unavailable`.
forwarded! : Remote.Endpoint, Try(Str, [Missing]), Chat.Request => Protocol.Answer(Chat.Response)
forwarded! = |endpoint, provider, asked| {
	unavailable = |problem| Err({ code: Unavailable, message: "the provider ${endpoint.name}: ${problem}" })
	match remote_asked!(endpoint, POST, "call", Json.to_str(Remote.call(endpoint.name, provider, asked))) {
		Ok(body) => {
			answer : Try(Protocol.Answer(Chat.Response), _)
			answer = Json.parse(body)
			answer ?? unavailable("its answer isn't a chat.v1 answer")
		}
		Err(err) => unavailable(Str.inspect(err))
	}
}

## The body of a remote's 200 answer to `what` under its /liton/v1, within
## `remote_timeout_ms`.
remote_asked! : Remote.Endpoint, [GET, POST], Str, Str => Try(Str, _)
remote_asked! = |endpoint, method, what, body| {
	asked = Request.from_method(if (method == GET) GET else POST).with_uri("${endpoint.url}/liton/v1/${what}").with_body(body.to_utf8()).with_timeout(TimeoutMilliseconds(remote_timeout_ms.to_u64_wrap()))
	response = Http.send!(if (method == GET) asked else asked.add_header("Content-Type", "application/json"))?
	if response.status() != 200 {
		return Err(AnsweredStatus(response.status()))
	}
	Str.from_utf8(response.body())
}

## Runs each remote's cycle that is due.
remotes_cycle! : Context => Try({}, _)
remotes_cycle! = |context| {
	for endpoint in context.remotes {
		remote_cycle!(context, endpoint)?
	}
	Ok({})
}

## Asks a remote, at most every `remote_interval_ms`, in one poll of its
## /liton/v1, about all that polls watched of it within `interest_ms`, and
## keeps its answers for every client; first its manifest, when the daemon has
## none, it is `remote_manifest_ms` old or the remote was down. Nothing
## watched, no poll. A remote that fails is down: left out of the manifest
## and the lists, its topics `Unavailable`, and asked again after
## `Remote.backoff_ms`. Going down and coming back are logged once.
remote_cycle! : Context, Remote.Endpoint => Try({}, _)
remote_cycle! = |context, endpoint| {
	db = context.db
	now = now_ms!()
	claimed : List({ manifest : Str, manifest_at : I64, failures : I64 })
	claimed = Sqlite.query_many!({ db, query: "UPDATE remotes SET checked_at = :until WHERE name = :name AND checked_at <= :since RETURNING manifest, manifest_at, failures;", params: { name: endpoint.name, until: now + remote_timeout_ms, since: now - context.remote_interval_ms }, limits: Sqlite.default_query_limits })?
	match claimed.first() {
		Err(_) => Ok({})
		Ok(remote) =>
			match asked_remote!(context, endpoint, remote) {
				Ok({}) => {
					if remote.failures > 0 {
						logged!("liton: the provider ${endpoint.name} answers again")
					}
					Sqlite.execute!({ db, query: "UPDATE remotes SET checked_at = :now, failures = 0 WHERE name = :name;", params: { name: endpoint.name, now: now_ms!() } })
				}
				Err(err) => {
					failures = remote.failures + 1
					if remote.failures == 0 {
						logged!("liton: the provider ${endpoint.name} at ${endpoint.url} can't be reached, asking again with backoff: ${Str.inspect(err)}")
					}
					Sqlite.execute!({ db, query: "UPDATE remotes SET checked_at = :at, failures = :failures WHERE name = :name;", params: { name: endpoint.name, failures, at: now_ms!() + Remote.backoff_ms(failures) - context.remote_interval_ms } })
				}
			}
	}
}

## One cycle's asking of a remote (see `remote_cycle!`).
asked_remote! : Context, Remote.Endpoint, { manifest : Str, manifest_at : I64, failures : I64 } => Try({}, _)
asked_remote! = |context, endpoint, remote| {
	db = context.db
	now = now_ms!()
	manifest =
		if remote.manifest == "" or remote.manifest_at <= now - remote_manifest_ms or remote.failures > 0 {
			fetched : Try(Manifest.Advertised, _)
			fetched = Json.parse(remote_asked!(endpoint, GET, "manifest", "")?)
			kept = Json.to_str(fetched.map_err(|_| NotAManifest)?)
			Sqlite.execute!({ db, query: "UPDATE remotes SET manifest = :manifest, manifest_at = :now WHERE name = :name;", params: { name: endpoint.name, manifest: kept, now } })?
			kept
		} else {
			remote.manifest
		}
	advertised : Try(Manifest.Advertised, _)
	advertised = Json.parse(manifest)
	offers = Manifest.capabilities(advertised.map_err(|_| NotAManifest)?)
	wanted : List(Protocol.Wanted)
	wanted = Sqlite.query_many!({ db, query: "SELECT capability, topic, cursor AS after FROM remote_topics WHERE remote = :name AND wanted_at > :since;", params: { name: endpoint.name, since: now - interest_ms }, limits: Sqlite.default_query_limits })?
	poll : Protocol.Poll
	poll = { topics: wanted.keep_if(|topic| Capability.from_str(topic.capability).map_ok(|id| offers.contains(id)) ?? Bool.False) }
	if poll.topics.is_empty() {
		return Ok({})
	}
	polled : Try(Protocol.Polled, _)
	polled = Json.parse(remote_asked!(endpoint, POST, "poll", Json.to_str(poll))?)
	for update in polled.map_err(|_| NotAPoll)?.topics {
		kept!(db, endpoint.name, update)?
	}
	Ok({})
}

## Keeps a remote's update of a topic: a timeline's entries as its session's
## in liton, any other topic's last event, and the cursor to ask after next,
## or why the topic can't be followed.
kept! : Sqlite.Db, Str, Protocol.Update => Try({}, _)
kept! = |db, remote, update| {
	now = now_ms!()
	for event in update.events {
		match event {
			Entry(entry) => Sqlite.execute!({ db, query: "INSERT OR IGNORE INTO entries (session_id, sequence, visible_at, event) VALUES (:session_id, :sequence, :now, :event);", params: { session_id: Remote.prefixed(remote, update.topic.drop_prefix("timeline/")), sequence: entry.sequence.to_i64_wrap(), now, event: Json.to_str(entry.event) } })?
			_ => {}
		}
	}
	snapshot =
		match update.events.last() {
			Ok(Entry(_)) | Err(_) => ""
			Ok(event) => Json.to_str(event)
		}
	error =
		match update.error {
			Ok(failed) => Json.to_str(failed)
			Err(Missing) => ""
		}
	Sqlite.execute!({ db, query: "UPDATE remote_topics SET cursor = :cursor, error = :error, event = CASE WHEN :event = '' THEN event ELSE :event END WHERE remote = :remote AND capability = :capability AND topic = :topic;", params: { remote, capability: update.capability, topic: update.topic, cursor: update.cursor, error, event: snapshot } })
}

## Where clients post an utterance's audio, `<utterance_id>/<seq>` after it.
audio_route : Str
audio_route = "/liton/v1/audio/voice.v1/"

## The most a chunk of audio may hold: a 1 s chunk is 32,000 bytes.
chunk_limit_bytes : U64
chunk_limit_bytes = 64 * 1024

## How long the daemon keeps an utterance's audio and transcript.
utterance_ms : I64
utterance_ms = 600_000

## How often, at most, the daemon asks the speech engine whether it is up.
speech_status_ms : I64
speech_status_ms = 5_000

## Answers a chunk of an utterance's audio, raw 16 kHz 16-bit mono PCM: keeps
## it, unless a chunk of its seq is kept already, and acks those kept. One
## over `chunk_limit_bytes` is answered 413.
audio_chunk! : Context, Server.Request, Str => Try(Response, _)
audio_chunk! = |context, request, rest| {
	answered = |answer| {
		typed : Protocol.Answer(Voice.Acked)
		typed = answer
		json(Json.to_str(typed))
	}
	match (context.speech, Voice.chunk(rest)) {
		(Err(Disabled), _) => Ok(answered(Err({ code: Unsupported, message: "the daemon offers no voice.v1" })))
		(_, Err(problem)) => Ok(answered(Err({ code: BadRequest, message: problem })))
		(_, Ok({ utterance_id, seq })) =>
			match request.body().with_limit(chunk_limit_bytes).read_all!() {
				Err(RequestBodyErr(TooLarge(_))) => Ok(answered(Err({ code: BadRequest, message: "a chunk holds at most ${chunk_limit_bytes.to_str()} bytes" })).with_status(413))
				Err(err) => Err(err)
				Ok(pcm) if pcm.len() % 2 == 1 => Ok(answered(Err({ code: BadRequest, message: "a chunk holds 16-bit samples, an even number of bytes" })))
				Ok(pcm) => {
					db = context.db
					now = now_ms!()
					expired!(db, now)?
					Sqlite.execute!({ db, query: "INSERT OR IGNORE INTO voice_chunks (utterance_id, seq, pcm, at) VALUES (:utterance_id, :seq, :pcm, :now);", params: { utterance_id, seq: seq.to_i64_wrap(), pcm: Sqlite.Blob.from_bytes(pcm), now } })?
					Ok(answered(Ok(Voice.acked(chunks_held!(db, utterance_id)?))))
				}
			}
	}
}

## Drops the audio and transcripts older than `utterance_ms`.
expired! : Sqlite.Db, I64 => Try({}, _)
expired! = |db, now| {
	Sqlite.execute!({ db, query: "DELETE FROM voice_chunks WHERE at <= :since;", params: { since: now - utterance_ms } })?
	Sqlite.execute!({ db, query: "DELETE FROM voice_transcripts WHERE at <= :since;", params: { since: now - utterance_ms } })
}

## The seqs of an utterance's chunks kept, in order.
chunks_held! : Sqlite.Db, Str => Try(List(U64), _)
chunks_held! = |db, utterance_id| {
	rows : List({ seq : I64 })
	rows = Sqlite.query_many!({ db, query: "SELECT seq FROM voice_chunks WHERE utterance_id = :utterance_id ORDER BY seq;", params: { utterance_id }, limits: Sqlite.default_query_limits })?
	Ok(rows.map(|row| row.seq.to_u64_wrap()))
}

## Answers a voice.v1 request. `Finish` transcribes the chunks from 0 to its
## `last_seq` once all are kept, then keeps the transcript in place of the
## audio, so a `Finish` asked again answers the same.
voice_call! : Context, LocalSpeech.Engine, Voice.Request => Try(Protocol.Answer(Voice.Response), _)
voice_call! = |context, engine, asked| {
	db = context.db
	match asked {
		Begin(_) =>
			match speech_status!(context)? {
				Ready => Ok(Ok(Accepted))
				Loading => Ok(Err({ code: Unavailable, message: "${LocalSpeech.named(engine)} is loading its model" }))
				Down(reason) => Ok(Err({ code: Unavailable, message: reason }))
			}
		Cancel({ utterance_id }) => {
			Sqlite.execute!({ db, query: "DELETE FROM voice_chunks WHERE utterance_id = :utterance_id;", params: { utterance_id } })?
			Ok(Ok(Accepted))
		}
		Finish({ last_seq, .. }) if last_seq >= Voice.max_chunks => Ok(Err({ code: BadRequest, message: "an utterance has at most ${Voice.max_chunks.to_str()} chunks" }))
		Finish({ utterance_id, last_seq }) => {
			expired!(db, now_ms!())?
			kept : List({ text : Str })
			kept = Sqlite.query_many!({ db, query: "SELECT text FROM voice_transcripts WHERE utterance_id = :utterance_id;", params: { utterance_id }, limits: Sqlite.default_query_limits })?
			count = Voice.contiguous(chunks_held!(db, utterance_id)?)
			match kept.first() {
				Ok({ text: transcript }) => Ok(Ok(Transcript({ text: transcript })))
				Err(_) if count <= last_seq => Ok(Ok(Missing({ from_seq: count })))
				Err(_) => {
					rows : List({ pcm : Sqlite.Blob })
					rows = Sqlite.query_many!({ db, query: "SELECT pcm FROM voice_chunks WHERE utterance_id = :utterance_id AND seq <= :last_seq ORDER BY seq;", params: { utterance_id, last_seq: last_seq.to_i64_wrap() }, limits: { ..Sqlite.default_query_limits, max_bytes: Voice.max_chunks * chunk_limit_bytes } })?
					match transcribed!(engine, rows.fold([], |pcm, row| pcm.concat(row.pcm.to_bytes()))) {
						Ok(transcript) => {
							Sqlite.execute!({ db, query: "INSERT OR REPLACE INTO voice_transcripts (utterance_id, text, at) VALUES (:utterance_id, :text, :now);", params: { utterance_id, text: transcript, now: now_ms!() } })?
							Sqlite.execute!({ db, query: "DELETE FROM voice_chunks WHERE utterance_id = :utterance_id;", params: { utterance_id } })?
							Ok(Ok(Transcript({ text: transcript })))
						}
						Err(err) => Ok(Err({ code: Unavailable, message: "${LocalSpeech.named(engine)}: ${Str.inspect(err)}" }))
					}
				}
			}
		}
	}
}

## The engine's transcript of an utterance.
transcribed! : LocalSpeech.Engine, List(U8) => Try(Str, _)
transcribed! = |engine, pcm|
	match engine {
		Sherpa(address) => {
			connection = sherpa_connected!(address)?
			connection.write!(WebSocket.frame(Binary, LocalSpeech.samples(pcm), websocket_mask))?
			answer = message!(connection, [])?
			_ = connection.write!(WebSocket.text("Done", websocket_mask))
			_ = connection.write!(WebSocket.close(websocket_mask))
			LocalSpeech.sherpa_text(answer)
		}
		Whisper(url) => {
			{ content_type, body } = LocalSpeech.inference(pcm)
			response = Http.send!(Request.from_method(POST).with_uri("${url}/inference").with_body(body).add_header("Content-Type", content_type).with_timeout(TimeoutMilliseconds(60_000)))?
			if response.status() != 200 {
				return Err(AnsweredStatus(response.status()))
			}
			LocalSpeech.whisper_text(Str.from_utf8(response.body())?)
		}
	}

## A WebSocket connection to sherpa-onnx's server.
sherpa_connected! : { host : Str, port : U16, path : Str } => Try(Tcp.Connection, _)
sherpa_connected! = |{ host, port, path }| {
	connection = Tcp.connect!(host, port)?
	connection.write_utf8!(WebSocket.handshake({ host, port, path, protocol: "liton", key: "bGl0b24tZGFlbW9uLWtleQ==" }))?
	status_line = connection.read_line!()?
	if !WebSocket.accepted(status_line) {
		return Err(HandshakeRefused(status_line.trim()))
	}
	skip_headers!(connection)?
	Ok(connection)
}

## Whether the speech engine is up, asked at most every `speech_status_ms`.
speech_status! : Context => Try(Voice.Engine, _)
speech_status! = |context|
	match context.speech {
		Err(Disabled) => Ok(Down("LITON_STT names no speech engine"))
		Ok(engine) => {
			named = LocalSpeech.named(engine)
			now = now_ms!()
			rows : List({ status : Str })
			rows = Sqlite.query_many!({ db: context.db, query: "SELECT status FROM voice_status WHERE engine = :named AND checked_at > :since;", params: { named, since: now - speech_status_ms }, limits: Sqlite.default_query_limits })?
			known : Try(Voice.Engine, _)
			known = Json.parse(rows.first().map_ok(|row| row.status) ?? "")
			match known {
				Ok(status) => Ok(status)
				Err(_) => {
					status =
						match engine {
							Sherpa(address) =>
								match sherpa_connected!(address) {
									Ok(connection) => {
										_ = connection.write!(WebSocket.close(websocket_mask))
										Ready
									}
									Err(err) => Down("${named} can't be reached: ${Str.inspect(err)}")
								}
							Whisper(url) =>
								match Http.send!(Request.from_method(GET).with_uri("${url}/health").with_timeout(TimeoutMilliseconds(2_000))) {
									Ok(response) if response.status() == 200 => Ready
									Ok(response) if response.status() == 503 => Loading
									Ok(response) => Down("${named} answered ${response.status().to_str()}")
									Err(err) => Down("${named} can't be reached: ${Str.inspect(err)}")
								}
						}
					Sqlite.execute!({ db: context.db, query: "INSERT OR REPLACE INTO voice_status (engine, status, checked_at) VALUES (:named, :status, :now);", params: { named, status: Json.to_str(status), now } })?
					Ok(status)
				}
			}
		}
	}

expect transformers_named(["needs-you", " attention", ""]).map_ok(|parts| parts.map(|part| part.id)) == Ok(["attention", "needs-you"]) and transformers_named(["attention", "nope"]).is_err()

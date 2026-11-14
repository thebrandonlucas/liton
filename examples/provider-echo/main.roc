## The smallest provider outside the daemon: a server of /liton/v1 (see
## docs/protocol.md, Providers outside the daemon) offering chat.v1 for two
## scripted sessions, `echo`, which answers each message with it, and
## `hello`, which only greets. A daemon adds it with
## LITON_PROVIDERS=echo=http://127.0.0.1:8096.
##
## ECHO_PORT (default 8096), ECHO_HOST (default 127.0.0.1) and ECHO_DB
## (default provider-echo.db) configure it. It logs each request it answers
## on stderr.
app [Context, program] {
	cap: "../../capabilities/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.21.0/4viZsnWjdYsyH4Q87ESFAwM5c55Hnc15nAGW1UwzWpFU.tar.zst",
}

import pf.Env
import pf.OsStr
import pf.Path
import pf.Server
import pf.Sqlite
import pf.Stderr
import http.Response
import cap.Capability
import cap.Chat
import cap.Manifest
import cap.Protocol

Context : { db : Sqlite.Db }

program = { init!, respond!, shutdown! }

env_or! : Str, Str => Str
env_or! = |name, default| Env.var_str!(OsStr.from_str(name)) ?? default

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64)])
init! = || {
	port = U16.from_str(env_or!("ECHO_PORT", "8096")) ?? 8096
	db = Sqlite.open!(Sqlite.default_config(Path.utf8(env_or!("ECHO_DB", "provider-echo.db")))) ? |_| Exit(2)
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS entries (session_id TEXT NOT NULL, sequence INTEGER NOT NULL, event TEXT NOT NULL, PRIMARY KEY (session_id, sequence));", params: {} }) ? |_| Exit(3)
	for (session, greeting) in [("echo", "Send me anything and I'll say it back."), ("hello", "Hello from a provider outside the daemon.")] {
		Sqlite.execute!({ db, query: "INSERT OR IGNORE INTO entries (session_id, sequence, event) VALUES (:session_id, 1, :event);", params: { session_id: session, event: Json.to_str(AgentMessage({ text: greeting })) } }) ? |_| Exit(3)
	}
	Ok({ config: Server.default_config.with_listen({ host: env_or!("ECHO_HOST", "127.0.0.1"), port }), context: { db } })
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64)])
shutdown! = |_reason, _context| Ok({})

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str)])
respond! = |request, { db }| {
	answered =
		match (request.method(), request.target()) {
			(GET, Resource({ raw_path: "/liton/v1/manifest", .. })) => Ok(json(Json.to_str(manifest)))
			(POST, Resource({ raw_path: "/liton/v1/call", .. })) => called!(db, request)
			(POST, Resource({ raw_path: "/liton/v1/poll", .. })) => polled!(db, request)
			_ => Ok(Response.from_status(404))
		}
	path =
		match request.target() {
			Resource({ raw_path, .. }) => raw_path
			_ => "another target"
		}
	_ = Stderr.line!("provider-echo: ${Str.inspect(request.method())} ${path}")
	match answered {
		Ok(response) => Ok(Server.respond(response))
		Err(err) => Ok(Server.respond(Response.from_status(500).with_body(Str.inspect(err).to_utf8())))
	}
}

## What it offers: chat.v1, from one provider, with its topics.
manifest : Manifest.Offered
manifest = {
	protocol: Manifest.protocol,
	daemon: { id: "echo", name: "Echo" },
	providers: [{ id: "echo", name: "Echo", capabilities: [Capability.chat_v1] }],
	transformers: [],
	topics: [{ capability: Capability.chat_v1, patterns: ["sessions", "timeline/<session_id>"] }],
}

json : Str -> Response
json = |body| Response.from_status(200).with_headers([{ name: "Content-Type", value: "application/json" }]).with_body(body.to_utf8())

read! : Server.Request => Try(Str, _)
read! = |request| Str.from_utf8(request.body().with_limit(64 * 1024).read_all!()?)

## A call, answered as its capability's Response or an error.
called! : Sqlite.Db, Server.Request => Try(Response, _)
called! = |db, request| {
	call : Try(Protocol.Call(Chat.Request), _)
	call = Json.parse(read!(request)?)
	answer : Protocol.Answer(Chat.Response)
	answer =
		match call {
			Ok({ capability: "chat.v1", request: ListSessions, .. }) => Ok(Sessions(sessions))
			Ok({ capability: "chat.v1", request: WatchSession({ session_id, after }), .. }) if known(session_id) => Ok(Entries(entries!(db, session_id, after)?))
			Ok({ capability: "chat.v1", request: SendMessage({ session_id: "echo", text }), .. }) => {
				last = entries!(db, "echo", 0)?.last().map_ok(|entry| entry.sequence) ?? 0
				for (event, offset) in [(UserMessage({ text: text }), 1), (AgentMessage({ text: "You said: ${text}" }), 2)] {
					Sqlite.execute!({ db, query: "INSERT INTO entries (session_id, sequence, event) VALUES ('echo', :sequence, :event);", params: { sequence: (last + offset).to_i64_wrap(), event: Json.to_str(event) } })?
				}
				Ok(Accepted)
			}
			Ok({ capability: "chat.v1", request: SendMessage({ session_id: "hello", .. }), .. }) => Err({ code: Refused, message: "hello only greets" })
			Ok({ capability: "chat.v1", .. }) => Err({ code: NotFound, message: "no such session or permission request" })
			Ok({ capability, .. }) => Err({ code: Unsupported, message: "echo offers no ${capability}" })
			Err(_) => Err({ code: BadRequest, message: "expected a call" })
		}
	Ok(json(Json.to_str(answer)))
}

## A poll, each topic answered after its cursor.
polled! : Sqlite.Db, Server.Request => Try(Response, _)
polled! = |db, request| {
	poll : Try(Protocol.Poll, _)
	poll = Json.parse(read!(request)?)
	match poll {
		Err(_) => Ok(Response.from_status(400))
		Ok({ topics }) => {
			var $updates = []
			for wanted in topics {
				session_id = wanted.topic.drop_prefix("timeline/")
				update =
					match (wanted.capability, Protocol.sequence(wanted)) {
						("chat.v1", _) if wanted.topic == "sessions" => Protocol.snapshot(wanted, Sessions(sessions))
						("chat.v1", Ok(after)) if wanted.topic.starts_with("timeline/") and known(session_id) => Protocol.appended(wanted, entries!(db, session_id, after)?)
						_ => Protocol.failed(wanted, { code: NotFound, message: "echo has no topic ${wanted.topic}" })
					}
				$updates = $updates.append(update)
			}
			polled : Protocol.Polled
			polled = { topics: $updates }
			Ok(json(Json.to_str(polled)))
		}
	}
}

known : Str -> Bool
known = |session_id| session_id == "echo" or session_id == "hello"

sessions : List(Chat.Session)
sessions = [Chat.session({ id: "echo", provider: "echo", agent: "echo", title: "Echo what you send", status: Idle }), Chat.session({ id: "hello", provider: "echo", agent: "echo", title: "Say hello", status: Finished })]

entries! : Sqlite.Db, Str, U64 => Try(List(Chat.Entry), _)
entries! = |db, session_id, after| {
	rows : List({ sequence : I64, event : Str })
	rows = Sqlite.query_many!({ db, query: "SELECT sequence, event FROM entries WHERE session_id = :session_id AND sequence > :after ORDER BY sequence;", params: { session_id, after: after.to_i64_wrap() }, limits: Sqlite.default_query_limits })?
	rows.map_try(
		|row| {
			event : Try(Chat.Event, _)
			event = Json.parse(row.event)
			Ok({ sequence: row.sequence.to_u64_wrap(), event: event? })
		},
	)
}

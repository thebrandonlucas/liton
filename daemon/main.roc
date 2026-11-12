## liton's daemon: advertises its providers' capabilities and serves chat.v1
## over HTTP, from timelines it keeps in SQLite, and serves the UI.
##
## LITON_PORT (default 8095), LITON_HOST (default 127.0.0.1), LITON_DB
## (default liton.db) and LITON_UI (default zig-out/www) configure it.
app [Context, program] {
	cap: "../capabilities/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	mock: "../providers/mock/main.roc",
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.21.0/4viZsnWjdYsyH4Q87ESFAwM5c55Hnc15nAGW1UwzWpFU.tar.zst",
}

import pf.Env
import pf.OsStr
import pf.Path
import pf.Server
import pf.Sqlite
import pf.UnixTime
import http.Response
import cap.Chat
import cap.Manifest
import mock.Mock

Context : { db : Sqlite.Db }

program = { init!, respond!, shutdown! }

env_or! : Str, Str => Str
env_or! = |name, default| Env.var_str!(OsStr.from_str(name)) ?? default

init! : () => Try({ config : Server.Config, context : Context }, [Exit(I64)])
init! = || {
	port = U16.from_str(env_or!("LITON_PORT", "8095")) ?? 8095
	host = env_or!("LITON_HOST", "127.0.0.1")
	db = Sqlite.open!(Sqlite.default_config(Path.utf8(env_or!("LITON_DB", "liton.db")))) ? |_| Exit(2)
	create_tables!(db) ? |_| Exit(3)
	seed!(db) ? |_| Exit(4)
	ui = Server.file_root({ id: "ui", path: Path.utf8(env_or!("LITON_UI", "zig-out/www")) })
	config =
		Server.default_config
			.with_listen({ host, port })
			.with_file_roots([ui])
			.with_native_routes({ files: [Server.static_mount({ at: "/ui", files: ui })], liveness: [], readiness: [] })
	Ok({ config, context: { db } })
}

shutdown! : Server.ShutdownReason, Context => Try({}, [Exit(I64)])
shutdown! = |_reason, _context| Ok({})

respond! : Server.Request, Context => Try(Server.Outcome, [ServerErr(Str)])
respond! = |request, { db }| {
	response =
		match (request.method(), request.target()) {
			(GET, Resource({ raw_path: "/", .. })) =>
				Ok(Response.from_status(302).with_headers([{ name: "Location", value: "/ui/index.html" }]))
			(GET, Resource({ raw_path: "/api/manifest", .. })) =>
				Ok(json(Json.to_str({ protocol: Manifest.protocol, providers: [Mock.provider] })))
			(POST, Resource({ raw_path: "/api/chat", .. })) =>
				chat!(db, request)
			(POST, Resource({ raw_path: "/api/chat/poll", .. })) =>
				poll!(db, request)
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

chat! : Sqlite.Db, Server.Request => Try(Response, _)
chat! = |db, request| {
	decoded : Try(Chat.Request, _)
	decoded = Json.parse(read_json!(request)?)
	answer : Chat.Response
	answer =
		match decoded {
			Err(_) => Rejected("expected a chat.v1 request")
			Ok(ListSessions) => Sessions(sessions!(db)?)
			Ok(WatchSession({ session_id, after })) => Entries(visible!(db, session_id, after)?)
			Ok(SendMessage({ session_id, text: message })) =>
				if known!(db, session_id)? {
					schedule!(db, session_id, |next| Mock.on_message(message, next))?
					Accepted
				} else {
					Rejected("no session ${session_id}")
				}
			Ok(AnswerPermission({ session_id, request_id, allowed })) =>
				if Chat.pending_permissions(visible!(db, session_id, 0)?).contains(request_id) {
					schedule!(db, session_id, |next| Mock.on_answer(request_id, allowed, next))?
					Accepted
				} else {
					Rejected("no pending permission request ${request_id}")
				}
		}
	Ok(json(Json.to_str(answer)))
}

poll! : Sqlite.Db, Server.Request => Try(Response, _)
poll! = |db, request| {
	decoded : Try(Chat.Poll, _)
	decoded = Json.parse(read_json!(request)?)
	match decoded {
		Err(_) => Ok(text(400, "expected a chat.v1 poll"))
		Ok({ watches }) => {
			var $timelines = []
			for { session_id, after } in watches {
				$timelines = $timelines.append({ session_id, entries: visible!(db, session_id, after)? })
			}
			polled : Chat.Polled
			polled = { sessions: sessions!(db)?, timelines: $timelines }
			Ok(json(Json.to_str(polled)))
		}
	}
}

now_ms! : () => I64
now_ms! = || (UnixTime.now!().nanos_since_epoch() // 1_000_000).to_i64_wrap()

create_tables! : Sqlite.Db => Try({}, _)
create_tables! = |db| {
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, agent TEXT NOT NULL, title TEXT NOT NULL, position INTEGER NOT NULL);", params: {} })?
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS entries (session_id TEXT NOT NULL, sequence INTEGER NOT NULL, visible_at INTEGER NOT NULL, event TEXT NOT NULL, PRIMARY KEY (session_id, sequence));", params: {} })
}

## Gives a fresh database the mock provider's seed sessions.
seed! : Sqlite.Db => Try({}, _)
seed! = |db| {
	count : { count : I64 }
	count = Sqlite.query!({ db, query: "SELECT count(*) AS count FROM sessions;", params: {}, limits: Sqlite.default_query_limits })?
	if count.count == 0 {
		for (seed, position) in Mock.seeds.map_with_index(|seed, position| (seed, position)) {
			Sqlite.execute!({ db, query: "INSERT INTO sessions (id, agent, title, position) VALUES (:id, :agent, :title, :position);", params: { id: seed.id, agent: seed.agent, title: seed.title, position: position.to_i64_wrap() } })?
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

known! : Sqlite.Db, Str => Try(Bool, _)
known! = |db, session_id| {
	rows : List({ id : Str })
	rows = Sqlite.query_many!({ db, query: "SELECT id FROM sessions WHERE id = :session_id;", params: { session_id }, limits: Sqlite.default_query_limits })?
	Ok(!rows.is_empty())
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

sessions! : Sqlite.Db => Try(List(Chat.Session), _)
sessions! = |db| {
	rows : List({ id : Str, agent : Str, title : Str })
	rows = Sqlite.query_many!({ db, query: "SELECT id, agent, title FROM sessions ORDER BY position;", params: {}, limits: Sqlite.default_query_limits })?
	var $sessions = []
	for row in rows {
		$sessions = $sessions.append({ id: row.id, provider: Mock.provider.id, agent: row.agent, title: row.title, status: Mock.status(visible!(db, row.id, 0)?) })
	}
	Ok($sessions)
}

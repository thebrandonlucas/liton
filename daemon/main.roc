## liton's daemon: advertises its providers' capabilities and serves chat.v1
## over HTTP, from timelines it keeps in SQLite, and serves the UI.
##
## LITON_PORT (default 8095), LITON_HOST (default 127.0.0.1), LITON_DB
## (default liton.db) and LITON_UI (default zig-out/www) configure it.
## LITON_MOCK=off leaves out the mock provider. Setting PASEO_PASSWORD adds
## the agents of the Paseo daemon at PASEO_HOST (default 127.0.0.1) and
## PASEO_PORT (default 6767).
app [Context, program] {
	cap: "../capabilities/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	mock: "../providers/mock/main.roc",
	paseo: "../providers/paseo/main.roc",
	pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.21.0/4viZsnWjdYsyH4Q87ESFAwM5c55Hnc15nAGW1UwzWpFU.tar.zst",
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
import cap.Attention
import cap.Capability
import cap.Chat
import cap.Manifest
import mock.Mock
import paseo.Paseo
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
					chat_providers = (if (context.mock_enabled) [Mock.provider] else []).concat(if (context.paseo.is_ok()) [Paseo.provider] else [])
					Ok(json(Json.to_str({ protocol: Manifest.protocol, providers: if (chat_providers.is_empty()) [] else chat_providers.append(liton_provider) })))
				}
			(POST, Resource({ raw_path: "/api/chat", .. })) =>
				chat!(context, request)
			(POST, Resource({ raw_path: "/api/chat/poll", .. })) =>
				poll!(context, request)
			(GET, Resource({ raw_path: "/api/attention", .. })) =>
				attention_items!(context).map_ok(|items| json(Json.to_str(items)))
			(POST, Resource({ raw_path: "/api/attention", .. })) =>
				attention!(context, request)
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

chat! : Context, Server.Request => Try(Response, _)
chat! = |context, request| {
	db = context.db
	decoded : Try(Chat.Request, _)
	decoded = Json.parse(read_json!(request)?)
	answer : Chat.Response
	answer =
		match decoded {
			Err(_) => Rejected("expected a chat.v1 request")
			Ok(ListSessions) => Sessions(sessions!(context)?)
			Ok(WatchSession({ session_id, after })) => Entries(watched!(context, session_id, after)?)
			Ok(SendMessage({ session_id, text: message })) =>
				match provider!(context, session_id)? {
					MockSession => {
						schedule!(db, session_id, |next| Mock.on_message(message, next))?
						Accepted
					}
					PaseoSession(daemon) => paseo_answer(tool!(daemon, Paseo.send_prompt(session_id, message)))
					NoSession => Rejected("no session ${session_id}")
				}
			Ok(AnswerPermission({ session_id, request_id, allowed })) =>
				if !Chat.pending_permissions(visible!(db, session_id, 0)?).contains(request_id) {
					Rejected("no pending permission request ${request_id}")
				} else {
					match provider!(context, session_id)? {
						MockSession => {
							schedule!(db, session_id, |next| Mock.on_answer(request_id, allowed, next))?
							Accepted
						}
						PaseoSession(daemon) => {
							outcome = tool!(daemon, Paseo.answer_permission(session_id, request_id, allowed))
							if outcome.is_ok() {
								known = state_of!(db, session_id)?
								store!(db, session_id, known.stored, { state: Paseo.answered(known.state, request_id), events: [PermissionAnswered({ request_id, allowed })] })?
							}
							paseo_answer(outcome)
						}
						NoSession => Rejected("no session ${session_id}")
					}
				}
		}
	Ok(json(Json.to_str(answer)))
}

poll! : Context, Server.Request => Try(Response, _)
poll! = |context, request| {
	decoded : Try(Chat.Poll, _)
	decoded = Json.parse(read_json!(request)?)
	match decoded {
		Err(_) => Ok(text(400, "expected a chat.v1 poll"))
		Ok({ watches }) => {
			sessions = sessions!(context)?
			var $timelines = []
			for { session_id, after } in watches {
				$timelines = $timelines.append({ session_id, entries: watched!(context, session_id, after)? })
			}
			polled : Chat.Polled
			polled = { sessions, timelines: $timelines }
			Ok(json(Json.to_str(polled)))
		}
	}
}

## The built-in provider of what the daemon derives from the others' chat.v1.
liton_provider : Manifest.Provider
liton_provider = { id: "liton", name: "liton", capabilities: [Capability.attention_v1] }

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
			Ok(ListItems) => Items(attention_items!(context)?)
			Ok(Settle({ session_id, signature })) => set_aside!(context, { session_id, signature, snoozed_until: 0 })?
			Ok(Snooze({ session_id, signature, minutes })) => set_aside!(context, { session_id, signature, snoozed_until: now_ms!() + minutes.to_i64() * 60_000 })?
			Ok(Unsettle({ session_id })) => {
				Sqlite.execute!({ db: context.db, query: "DELETE FROM attention_asides WHERE session_id = :session_id;", params: { session_id: session_id } })?
				Accepted
			}
		}
	Ok(json(Json.to_str(answer)))
}

set_aside! : Context, Attention.Aside => Try(Attention.Response, _)
set_aside! = |context, { session_id, signature, snoozed_until }|
	match provider!(context, session_id)? {
		NoSession => Ok(Rejected("no session ${session_id}"))
		_ => {
			Sqlite.execute!({ db: context.db, query: "INSERT INTO attention_asides (session_id, signature, snoozed_until) VALUES (:session_id, :signature, :snoozed_until) ON CONFLICT (session_id) DO UPDATE SET signature = excluded.signature, snoozed_until = excluded.snoozed_until;", params: { session_id, signature, snoozed_until } })?
			Ok(Accepted)
		}
	}

now_ms! : () => I64
now_ms! = || (UnixTime.now!().nanos_since_epoch() // 1_000_000).to_i64_wrap()

create_tables! : Sqlite.Db => Try({}, _)
create_tables! = |db| {
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, agent TEXT NOT NULL, title TEXT NOT NULL, position INTEGER NOT NULL);", params: {} })?
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS entries (session_id TEXT NOT NULL, sequence INTEGER NOT NULL, visible_at INTEGER NOT NULL, event TEXT NOT NULL, PRIMARY KEY (session_id, sequence));", params: {} })?
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS paseo_states (session_id TEXT PRIMARY KEY, state TEXT NOT NULL);", params: {} })?
	Sqlite.execute!({ db, query: "CREATE TABLE IF NOT EXISTS attention_asides (session_id TEXT PRIMARY KEY, signature TEXT NOT NULL, snoozed_until INTEGER NOT NULL);", params: {} })?
	# Sessions stored before Paseo came are all the mock provider's.
	provider_column : List({ name : Str })
	provider_column = Sqlite.query_many!({ db, query: "SELECT name FROM pragma_table_info('sessions') WHERE name = 'provider';", params: {}, limits: Sqlite.default_query_limits })?
	if provider_column.is_empty() {
		Sqlite.execute!({ db, query: "ALTER TABLE sessions ADD COLUMN provider TEXT NOT NULL DEFAULT 'mock';", params: {} })?
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

## A session's entries after `after`, a Paseo session's synced first.
watched! : Context, Str, U64 => Try(List(Chat.Entry), _)
watched! = |context, session_id, after| {
	match provider!(context, session_id)? {
		PaseoSession(daemon) => synced!(context.db, daemon, session_id)
		_ => {}
	}
	visible!(context.db, session_id, after)
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
	match paseo {
		Ok(daemon) => Ok($sessions.concat(paseo_sessions!(db, daemon)?))
		Err(Disabled) => Ok($sessions)
	}
}

## The agents Paseo lists, which the registry keeps: while Paseo can't be
## reached, the last listed ones with their last synced status.
paseo_sessions! : Sqlite.Db, PaseoDaemon => Try(List(Chat.Session), _)
paseo_sessions! = |db, daemon|
	match listed!(daemon) {
		Ok(sessions) => {
			for (session, position) in sessions.map_with_index(|session, position| (session, position)) {
				Sqlite.execute!({ db, query: "INSERT INTO sessions (id, provider, agent, title, position) VALUES (:id, 'paseo', :agent, :title, :position) ON CONFLICT (id) DO UPDATE SET agent = excluded.agent, title = excluded.title, position = excluded.position;", params: { id: session.id, agent: session.agent, title: session.title, position: position.to_i64_wrap() } })?
			}
			Ok(sessions)
		}
		Err(err) => {
			logged!("Paseo: listing its agents failed: ${Str.inspect(err)}")
			rows : List({ id : Str, agent : Str, title : Str })
			rows = Sqlite.query_many!({ db, query: "SELECT id, agent, title FROM sessions WHERE provider = 'paseo' ORDER BY position;", params: {}, limits: Sqlite.default_query_limits })?
			var $sessions = []
			for row in rows {
				$sessions = $sessions.append({ id: row.id, provider: Paseo.provider.id, agent: row.agent, title: row.title, status: state_of!(db, row.id)?.state.status })
			}
			Ok($sessions)
		}
	}

listed! : PaseoDaemon => Try(List(Chat.Session), _)
listed! = |daemon| Paseo.sessions(mcp!(daemon, Paseo.list_agents)?)

logged! : Str => {}
logged! = |line| {
	_ = Stderr.line!(line)
	{}
}

## Calls one of Paseo's MCP tools and answers the response's body.
mcp! : PaseoDaemon, Str => Try(Str, _)
mcp! = |{ host, port, password }, body| {
	request = Request.from_method(POST).with_uri("http://${host}:${port.to_str()}${Paseo.mcp_path}").with_headers(Paseo.mcp_headers(password)).with_body(body.to_utf8())
	response = Http.send_with!(request, Http.default_config.with_timeout_millis(5_000))?
	if (response.status() == 200) Str.from_utf8(response.body()) else Err(HttpStatus(response.status()))
}

## Calls a Paseo tool that acts, such as sending a prompt.
tool! : PaseoDaemon, Str => Try({}, _)
tool! = |daemon, body| Paseo.succeeded(mcp!(daemon, body)?)

paseo_answer : Try({}, _) -> Chat.Response
paseo_answer = |outcome|
	match outcome {
		Ok({}) => Accepted
		Err(ToolFailed(reason)) => Rejected(reason)
		Err(err) => Rejected("Paseo: ${Str.inspect(err)}")
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

## Appends what a Paseo session's timeline adds since its last sync. A failure
## leaves the session as it was and is only logged.
synced! : Sqlite.Db, PaseoDaemon, Str => {}
synced! = |db, daemon, session_id|
	match sync!(db, daemon, session_id) {
		Ok({}) => {}
		Err(err) => logged!("Paseo: syncing ${session_id} failed: ${Str.inspect(err)}")
	}

## Syncs over one WebSocket connection to Paseo, up to 10 pages.
sync! : Sqlite.Db, PaseoDaemon, Str => Try({}, _)
sync! = |db, daemon, session_id| {
	connection = Tcp.connect!(daemon.host, daemon.port)?
	connection.write_utf8!(WebSocket.handshake({ host: daemon.host, port: daemon.port, path: "/ws", protocol: "paseo.bearer.${daemon.password}", key: "bGl0b24tZGFlbW9uLWtleQ==" }))?
	status_line = connection.read_line!()?
	if !WebSocket.accepted(status_line) {
		return Err(HandshakeRefused(status_line.trim()))
	}
	skip_headers!(connection)?
	connection.write!(WebSocket.text(Paseo.hello("liton-daemon"), websocket_mask))?
	fetched = fetch!(db, daemon, connection, session_id, 10)
	_ = connection.write!(WebSocket.close(websocket_mask))
	fetched
}

websocket_mask : List(U8)
websocket_mask = [0x6C, 0x69, 0x74, 0x6E]

## Reads the handshake response's headers, through the blank line.
skip_headers! : Tcp.Connection => Try({}, _)
skip_headers! = |connection| if (connection.read_line!()?.trim() == "") Ok({}) else skip_headers!(connection)

## Fetches the page after a session's state and stores what it adds, again
## while Paseo has newer entries, `pages` times at most.
fetch! : Sqlite.Db, PaseoDaemon, Tcp.Connection, Str, U64 => Try({}, _)
fetch! = |db, daemon, connection, session_id, pages| {
	known = state_of!(db, session_id)?
	request_id = "page-${pages.to_str()}"
	connection.write!(WebSocket.text(Paseo.timeline_request(known.state, session_id, request_id), websocket_mask))?
	page = page!(connection, request_id)?
	snapshot =
		match page.agent {
			Ok(agent) => agent
			Err(Null) => Paseo.status_snapshot(mcp!(daemon, Paseo.agent_status(session_id))?)?
		}
	updated = Paseo.update(known.state, page, snapshot)
	if updated.state != known.state or !updated.events.is_empty() {
		store!(db, session_id, known.stored, updated)?
	}
	if (page.has_newer and pages > 1) fetch!(db, daemon, connection, session_id, pages - 1) else Ok({})
}

## The page answering `request_id`, skipping Paseo's other messages.
page! : Tcp.Connection, Str => Try(Paseo.Page, _)
page! = |connection, request_id|
	match Paseo.timeline_page(message!(connection, [])?, request_id) {
		Err(OtherMessage) => page!(connection, request_id)
		other => other
	}

## The next text message, after `received` of its fragments, answering pings.
message! : Tcp.Connection, List(U8) => Try(Str, _)
message! = |connection, received| {
	first_two = connection.read_exactly!(2)?
	header = WebSocket.header(first_two.concat(connection.read_exactly!(WebSocket.header_rest_size(first_two))?))
	payload = WebSocket.unmask(connection.read_exactly!(header.length)?, header.mask)
	match header.opcode {
		Text | Continuation => if (header.fin) Str.from_utf8(received.concat(payload)) else message!(connection, received.concat(payload))
		Ping => {
			connection.write!(WebSocket.frame(Pong, payload, websocket_mask))?
			message!(connection, received)
		}
		Close => Err(ClosedByPaseo)
		_ => message!(connection, received)
	}
}

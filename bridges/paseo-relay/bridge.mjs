// Bridges liton's daemon to a Paseo daemon reached through a relay with
// pairing. It listens on ws://127.0.0.1:<port>/ws, where liton's daemon talks
// the plain Paseo protocol as to a local Paseo, and carries that traffic over
// one protected (Noise NK) channel through the relay, opened with Paseo's own
// @getpaseo/relay/e2ee. See docs/research/relay-paired-paseo.md.
//
// Configuration, from the environment:
//   PASEO_BRIDGE_OFFER or PASEO_BRIDGE_OFFER_FILE: the pairing offer, its link
//     (https://app.paseo.sh/#offer=...) or its JSON. Public data.
//   PASEO_BRIDGE_PASSWORD_FILE (read at each connection) or
//     PASEO_BRIDGE_PASSWORD: the daemon's password. Never logged or written.
//   PASEO_BRIDGE_PORT (default 18767), PASEO_BRIDGE_CLIENT_ID (default
//     liton-bridge), PASEO_BRIDGE_MAX_IN_FLIGHT (default 4) and
//     PASEO_BRIDGE_IDLE_MS (default 300000).
//
// Load: the daemon is shared with its user's other clients, and a proxy in
// front of a relay may cap requests per client address, each WebSocket
// holding a slot. So the bridge holds one upstream connection, as one Paseo
// session, and multiplexes every local connection over it: it answers a
// local `hello` itself, with the upstream's `server_info`, gives each local
// request a requestId of its own, and routes the reply back by it (Paseo
// echoes it in `payload.requestId`). Messages answering no local request go
// to every local client. That suits request and reply, all liton uses; the
// session's subscriptions, if a client made any, are shared. Upstream
// connections start at least 1.5 s apart, doubling to 30 s on failures, and
// only while a local client wanted one within PASEO_BRIDGE_IDLE_MS. At most
// PASEO_BRIDGE_MAX_IN_FLIGHT requests await replies; the rest queue.
//
// The password lives here alone: the bridge sends it in the upstream hello's
// `auth`, inside the channel, and ignores what local hellos carry. It only
// accepts protected channels, never Paseo's legacy NaCl mode.
//
// GET /status answers JSON: the state, the relay's round trip, the last error.
import { readFileSync } from "node:fs";
import { createServer } from "node:http";
import { WebSocket, WebSocketServer } from "ws";
import { openClientSecureChannel } from "@getpaseo/relay/e2ee";

const environment = process.env;
const port = Number(environment.PASEO_BRIDGE_PORT ?? 18767);
const client_id = environment.PASEO_BRIDGE_CLIENT_ID ?? "liton-bridge";
const max_in_flight = Number(environment.PASEO_BRIDGE_MAX_IN_FLIGHT ?? 4);
const idle_ms = Number(environment.PASEO_BRIDGE_IDLE_MS ?? 300_000);
const max_local_clients = 8;
const max_queued = 64;
const first_delay_ms = 1_500;
const max_delay_ms = 30_000;
// A connection that lasted this long resets the backoff when it ends.
const stable_ms = 30_000;
const ready_timeout_ms = 15_000;
const heartbeat_ms = 10_000;
const heartbeat_timeout_ms = 15_000;
const request_timeout_ms = 60_000;
// liton's own (providers/paseo/Paseo.roc, `hello`). With
// explicit_event_subscriptions Paseo pushes only what the session asked for.
const capabilities = { explicit_event_subscriptions: true, selective_agent_timeline: true, hello_rejection: true, all_providers: true, owned_subscriptions: true };

const logged = (line) => console.error(`${new Date().toISOString()} paseo-relay-bridge: ${line}`);
const exit_with = (line) => { logged(line); process.exit(2); };

const offer = parsed_offer(environment.PASEO_BRIDGE_OFFER ?? (environment.PASEO_BRIDGE_OFFER_FILE ? readFileSync(environment.PASEO_BRIDGE_OFFER_FILE, "utf8") : exit_with("set PASEO_BRIDGE_OFFER or PASEO_BRIDGE_OFFER_FILE to the pairing offer")));
const relay_url = `${offer.relay.useTls ? "wss" : "ws"}://${offer.relay.endpoint}/ws?${new URLSearchParams({ serverId: offer.serverId, role: "client", v: "2" })}`;
const password_file = environment.PASEO_BRIDGE_PASSWORD_FILE;
const password_from_environment = environment.PASEO_BRIDGE_PASSWORD;
delete environment.PASEO_BRIDGE_PASSWORD;
if (!password_file && !password_from_environment) exit_with("set PASEO_BRIDGE_PASSWORD_FILE or PASEO_BRIDGE_PASSWORD to the daemon's password");
password();

function parsed_offer(text) {
	const trimmed = text.trim();
	const at = trimmed.indexOf("#offer=");
	let decoded;
	try {
		decoded = JSON.parse(trimmed.startsWith("{") ? trimmed : Buffer.from(trimmed.slice(at + "#offer=".length), "base64url").toString("utf8"));
	} catch {
		exit_with("the pairing offer is neither a link with #offer= nor JSON");
	}
	if ((!trimmed.startsWith("{") && at < 0) || decoded?.v !== 2 || typeof decoded.serverId !== "string" || typeof decoded.daemonPublicKeyB64 !== "string" || typeof decoded.relay?.endpoint !== "string") {
		exit_with("the pairing offer isn't a version 2 offer with a serverId, a daemonPublicKeyB64 and a relay endpoint");
	}
	return decoded;
}

function password() {
	const read = password_file ? readFileSync(password_file, "utf8").replace(/\r?\n$/, "") : password_from_environment;
	if (!read) throw new Error("the password is empty");
	return read;
}

// What GET /status shows.
const status = { state: "idle", serverId: offer.serverId, relay: offer.relay.endpoint, securityMode: null, connectedAt: null, latencyMs: null, lastError: null, nextAttemptAt: null, upstreamConnections: 0, requestsForwarded: 0, localClients: 0, inFlight: 0, queued: 0 };
let upstream = null;
// The wait after the next failure, and when an attempt may start.
let delay_ms = first_delay_ms;
let next_attempt_at = 0;
let last_demand_at = 0;
let rejected = null;
let last_failure = null;
const clients = new Set();
// requestId upstream -> { client, original_id, upstream_id, answered, sent_at }
const routes = new Map();
const queue = [];
let request_count = 0;

function in_flight() {
	let count = 0;
	for (const route of routes.values()) if (!route.answered) count++;
	return count;
}

// ---- Upstream: the relay, the protected channel, one Paseo session ----

function connect() {
	let secret;
	try {
		secret = password();
	} catch (error) {
		return failed(`can't read the password: ${error.code ?? error.message}`, false);
	}
	next_attempt_at = Date.now() + first_delay_ms;
	status.upstreamConnections++;
	status.state = "connecting";
	const socket = new WebSocket(relay_url, { perMessageDeflate: false, handshakeTimeout: ready_timeout_ms, maxPayload: 33_554_432 });
	socket.binaryType = "arraybuffer";
	const link = { socket, channel: null, ready: false, started_at: Date.now(), ready_at: 0, server_info: null, ping_sent_at: 0, ended: false, error: null };
	upstream = link;
	const transport = { send: (data) => socket.send(data), close: (code, reason) => socket.close(code, reason), onmessage: null, onclose: null, onerror: null };
	socket.on("message", (data, is_binary) => transport.onmessage?.({ data: is_binary ? data : Buffer.from(data).toString("utf8"), isBinary: is_binary }));
	socket.on("close", (code, reason) => {
		transport.onclose?.(code, reason.toString());
		ended(link, link.error ?? `the relay closed the connection (${code}${reason.length ? ` ${reason}` : ""})`);
	});
	socket.on("error", (error) => {
		link.error ??= error.message;
		transport.onerror?.(error);
	});
	// A proxy's 429, say: never retry sooner than the backoff.
	socket.on("unexpected-response", (request, response) => {
		request.destroy();
		ended(link, `the relay answered HTTP ${response.statusCode}`);
	});
	socket.on("open", async () => {
		status.state = "handshaking";
		try {
			link.channel = await openClientSecureChannel(transport, {
				daemonPublicKeyB64: offer.daemonPublicKeyB64,
				minimumMode: "protected",
				events: {
					onopen: () => {
						if (link.channel.securityMode() !== "protected") return end(link, "the daemon offered only legacy security");
						status.securityMode = "protected";
						link.channel.send(JSON.stringify({ type: "hello", clientId: client_id, clientType: "cli", protocolVersion: 1, auth: { kind: "password", password: secret }, capabilities })).catch(() => {});
						secret = null;
					},
					onmessage: (data) => from_upstream(link, data),
					onclose: (code, reason) => ended(link, link.error ?? `the protected channel closed (${code}${reason ? ` ${reason}` : ""})`),
					onerror: (error) => { link.error ??= `the protected channel failed: ${error.message}`; },
				},
			});
		} catch (error) {
			end(link, `the protected handshake failed: ${error.message}`);
		}
	});
}

function from_upstream(link, data) {
	if (typeof data !== "string") return;
	let message;
	try {
		message = JSON.parse(data);
	} catch {
		return;
	}
	if (!link.ready) {
		if (message.type === "hello.rejected") {
			rejected = { reason: message.reason ?? "rejected" };
			return end(link, `the daemon refused the password: ${rejected.reason}`);
		}
		if (message.type === "session" && message.message?.type === "status" && message.message.payload?.status === "server_info") {
			link.ready = true;
			link.ready_at = Date.now();
			link.server_info = data;
			rejected = null;
			last_failure = null;
			Object.assign(status, { state: "ready", connectedAt: new Date(link.ready_at).toISOString(), lastError: null, nextAttemptAt: null });
			logged(`connected to ${offer.serverId} through ${offer.relay.endpoint}, protected, in ${link.ready_at - link.started_at} ms`);
			for (const client of clients) if (client.waiting) welcome(client);
		}
		return;
	}
	if (message.type === "pong") {
		if (link.ping_sent_at) status.latencyMs = Date.now() - link.ping_sent_at;
		link.ping_sent_at = 0;
		return;
	}
	const payload = message.message?.payload ?? message.payload;
	const route = typeof payload?.requestId === "string" ? routes.get(payload.requestId) : undefined;
	if (!route) {
		for (const client of clients) if (client.welcomed) client.socket.send(data);
		return;
	}
	if (route.original_id !== payload.requestId) payload.requestId = route.original_id;
	route.answered = true;
	route.client.socket.send(route.original_id === route.upstream_id ? data : JSON.stringify(message));
	pump();
}

// Closes the upstream on purpose, as on a failure.
function end(link, reason) {
	try {
		link.socket.close(1000);
	} catch {}
	ended(link, reason);
}

// The upstream connection is gone: everything that used it goes too.
function ended(link, reason) {
	if (link.ended) return;
	link.ended = true;
	// A close on purpose waits for the relay's close; a failure doesn't.
	if (!link.on_purpose) link.socket.terminate();
	if (upstream === link) upstream = null;
	status.securityMode = null;
	status.connectedAt = null;
	status.latencyMs = null;
	if (link.on_purpose) {
		status.state = "idle";
		logged(`closed the upstream connection: ${reason}`);
	} else {
		failed(reason, link.ready && Date.now() - link.ready_at >= stable_ms);
	}
	for (const client of clients) client.welcomed ? client.socket.close(1012, close_reason(`Paseo relay: ${reason}`)) : refuse(client);
	routes.clear();
	queue.length = 0;
}

// Backs off: 1.5 s after a first failure, doubling to 30 s, and 30 s after
// a refused password. A connection that lasted `stable_ms` starts over.
function failed(reason, was_stable) {
	if (was_stable) delay_ms = first_delay_ms;
	next_attempt_at = Date.now() + (rejected ? max_delay_ms : delay_ms);
	if (!rejected) delay_ms = Math.min(delay_ms * 2, max_delay_ms);
	status.state = rejected ? "rejected" : "backoff";
	status.lastError = reason;
	status.nextAttemptAt = new Date(next_attempt_at).toISOString();
	// One line per failure, not per retry of the same one.
	if (reason !== last_failure) logged(`${reason}; next attempt in ${((next_attempt_at - Date.now()) / 1000).toFixed(1)} s at the earliest`);
	last_failure = reason;
}

// Once a second: heartbeats, timeouts, reconnects and the idle close.
function tick() {
	const now = Date.now();
	const link = upstream;
	if (link && !link.ready && now - link.started_at > ready_timeout_ms) end(link, `no answer from the daemon within ${ready_timeout_ms / 1000} s`);
	if (link?.ready) {
		if (clients.size === 0 && now - last_demand_at > idle_ms) {
			link.on_purpose = true;
			end(link, "idle");
		} else if (link.ping_sent_at && now - link.ping_sent_at > heartbeat_timeout_ms) {
			end(link, `no heartbeat answer within ${heartbeat_timeout_ms / 1000} s`);
		} else if (!link.ping_sent_at && now - Math.max(link.ready_at, link.pinged_at ?? 0) >= heartbeat_ms) {
			link.ping_sent_at = link.pinged_at = now;
			link.channel.send(JSON.stringify({ type: "ping" })).catch(() => {});
		}
	}
	// A request unanswered this long frees its slot; a later reply goes to every client.
	for (const [id, route] of routes) if (now - route.sent_at > request_timeout_ms) routes.delete(id);
	// After a refused password, only a local hello tries again (see `greet`).
	const wanted = last_demand_at > 0 && now - last_demand_at < idle_ms && !rejected;
	if (!upstream && wanted && now >= next_attempt_at) connect();
	pump();
	Object.assign(status, { localClients: clients.size, inFlight: in_flight(), queued: queue.length });
}
setInterval(tick, 1_000).unref();

// ---- Local side: liton's daemon ----

function close_reason(text) {
	return Buffer.from(text).subarray(0, 120).toString("utf8").replace(/\uFFFD$/, "");
}

function welcome(client) {
	client.waiting = false;
	client.welcomed = true;
	client.socket.send(upstream.server_info);
}

function greet(client) {
	last_demand_at = Date.now();
	if (upstream?.ready) return welcome(client);
	if (!upstream && Date.now() >= next_attempt_at) connect();
	if (upstream) {
		client.waiting = true;
	} else {
		refuse(client);
	}
}

// Tells a local client why there is no upstream: as Paseo would, if it
// refused the password.
function refuse(client) {
	if (rejected) {
		client.socket.send(JSON.stringify({ type: "hello.rejected", reason: rejected.reason }));
		client.socket.close(1000);
	} else {
		const seconds = Math.ceil(Math.max(0, next_attempt_at - Date.now()) / 1000);
		client.socket.close(1013, close_reason(`Paseo relay unavailable, retrying in ${seconds} s: ${status.lastError ?? ""}`));
	}
}

function from_local(client, data, is_binary) {
	if (is_binary) return client.socket.close(1003, "text only");
	let message;
	try {
		message = JSON.parse(data.toString("utf8"));
	} catch {
		return client.socket.close(1007, "not JSON");
	}
	last_demand_at = Date.now();
	if (!client.welcomed && !client.waiting) {
		// The local hello's auth, clientId and capabilities are ignored: the
		// upstream session's are the bridge's.
		return message.type === "hello" ? greet(client) : client.socket.close(1002, "hello first");
	}
	if (message.type === "hello") return;
	if (message.type === "ping") return client.socket.send(JSON.stringify({ type: "pong" }));
	if (!client.welcomed) return client.socket.close(1002, "wait for server_info");
	if (queue.length >= max_queued) return client.socket.close(1013, "too many requests queued");
	queue.push({ client, message });
	pump();
}

// Sends queued messages while fewer than `max_in_flight` await replies.
function pump() {
	while (queue.length && upstream?.ready) {
		const { client, message } = queue[0];
		const inner = message.type === "session" ? message.message : undefined;
		const correlated = typeof inner?.requestId === "string";
		if (correlated && in_flight() >= max_in_flight) return;
		queue.shift();
		if (!clients.has(client)) continue;
		if (correlated) {
			// A request's id is the client's own, so it is replaced by one unique
			// upstream; any other id, such as the permission an
			// agent_permission_response answers, names something and stays.
			const original_id = inner.requestId;
			const upstream_id = /request$/.test(inner.type) || inner.type === "ping" ? `bridge-${++request_count}` : original_id;
			inner.requestId = upstream_id;
			routes.set(upstream_id, { client, original_id, upstream_id, answered: false, sent_at: Date.now() });
		}
		status.requestsForwarded++;
		upstream.channel.send(JSON.stringify(message)).catch(() => {});
	}
}

function dropped(client) {
	clients.delete(client);
	for (const [id, route] of routes) if (route.client === client) routes.delete(id);
	pump();
}

const sockets = new WebSocketServer({ noServer: true, perMessageDeflate: false, maxPayload: 33_554_432 });
const server = createServer((request, response) => {
	if (request.method === "GET" && request.url === "/status") {
		Object.assign(status, { localClients: clients.size, inFlight: in_flight(), queued: queue.length });
		response.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(status));
	} else {
		response.writeHead(404).end();
	}
});
server.on("upgrade", (request, socket, head) => {
	// A browser always sends Origin: no web page may use the bridge.
	const refusal = request.headers.origin !== undefined ? "403 Forbidden" : new URL(request.url, "ws://localhost").pathname !== "/ws" ? "404 Not Found" : clients.size >= max_local_clients ? "503 Service Unavailable" : null;
	if (refusal) return socket.end(`HTTP/1.1 ${refusal}\r\nConnection: close\r\n\r\n`);
	sockets.handleUpgrade(request, socket, head, (local) => {
		const client = { socket: local, welcomed: false, waiting: false };
		clients.add(client);
		local.on("message", (data, is_binary) => from_local(client, data, is_binary));
		local.on("close", () => dropped(client));
		local.on("error", () => {});
	});
});
server.listen(port, "127.0.0.1", () => logged(`listening on ws://127.0.0.1:${port}/ws for ${offer.serverId} through ${offer.relay.endpoint}`));

for (const signal of ["SIGINT", "SIGTERM"]) {
	process.on(signal, () => {
		if (upstream) {
			upstream.on_purpose = true;
			end(upstream, "stopping");
		}
		setTimeout(() => process.exit(0), 300);
	});
}

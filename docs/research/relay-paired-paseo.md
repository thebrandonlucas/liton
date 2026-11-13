# Research: a relay-paired Paseo daemon

What liton needs to work with the *sandbox architecture*: a headless,
read-only Paseo daemon runs remotely with no inbound port. It and its clients
both connect out to a Paseo relay, and the two ends encrypt end to end.
Sandboxed agents make the changes and appear in Paseo as ACP providers.
Clients pair with an offer link plus a password.

Sources are Paseo **v0.15.3** (`getpaseo/paseo`, tag `v0.15.3`) and
`getpaseo/paseo-relay` at `5f4b763`. Paths below are relative to those trees.
liton was built against Paseo 0.9.2.

## Recommendation

Use a **local bridge** (option B, below): a small Node process that uses
Paseo's own `@getpaseo/relay/e2ee` to open one protected channel through the
relay and exposes it as a plain `ws://127.0.0.1` socket. liton's daemon
provider keeps speaking the plain Paseo protocol it already speaks. Move
the bridge into liton's own platform host (option C) once that host does TLS
and the crypto. Either way, liton keeps **one** connection to the remote
daemon.

## 1. Protocol changes, 0.9.2 → 0.15.3

**The protocol version is still 1.** The daemon rejects only
`protocolVersion < 1` (`packages/server/src/server/websocket-server.ts:515`,
`:1747`). Every request liton sends is unchanged or only gained optional
fields. The top-level response schemas are identical. I diffed the extracted
zod schemas of 0.9.2's `protocol/dist/messages.js` against 0.15.3's
`packages/protocol/src/messages.ts`:

| liton uses | 0.15.3 |
|---|---|
| `fetch_agents_request` | same, plus optional `includeBackground` |
| `fetch_workspaces_request` | same, plus optional `includeBackground` and `filter.includeInternal` |
| `fetch_agent_timeline_request` | same, plus optional `wholeTurns` (sent only when the host advertises `features.wholeTurnTimeline`, `docs/timeline-sync.md`) |
| `checkout_status_request`, `checkout.diff.get.request`, `checkout.commits.list.request`, `checkout.commits.file_diff.request` | unchanged, and so are their responses |
| agent and workspace payloads | additive: `internal`, `background`, `setupStatus`, `createdAt`, `lastUserMessageAt` |
| timeline items (`messages.ts:717`) | unchanged union: user and assistant messages, reasoning, tool calls, todo, error, notification, compaction, plugin |

**Authentication moved into `hello`.** `hello` now carries
`auth: {kind:"password", password}` or `{kind:"localCredential", token}`
(`messages.ts:7741-7790`). A bad password gets
`{type:"hello.rejected", reason:"password_required"|"incorrect_password"|"incompatible_protocol"}`
(`:7797`) if the client advertises the `hello_rejection` capability.
Otherwise the daemon closes the socket. The `paseo.bearer.<password>`
subprotocol and the `Authorization` header that liton uses today still work,
but only on a direct connection. They are marked
`COMPAT(headerAuth) … remove after 2027-03-24` (`websocket-server.ts:984`).
**Through a relay there are no headers:** the password must go in
`hello.auth`.

**MCP is gone from this path.** liton prompts and answers permissions through
the HTTP endpoint `/mcp/agents`. Through the relay only the WebSocket
travels, so use the WebSocket equivalents. Both exist in 0.9.2 as well:

- `send_agent_message_request {requestId, agentId, text, messageId?, activeTurnBehavior?}` (`messages.ts:1422`);
- `agent_permission_response {agentId, requestId, response}` (`:2236`).

**Capabilities.** None are required. liton already sends
`explicit_event_subscriptions` and `selective_agent_timeline`. Without them
the daemon falls back to legacy broadcasts that are due for removal in
early 2027 (`packages/protocol/src/client-capabilities.ts`). Add
`hello_rejection` to get typed auth failures. Add `timeline_notifications`
only if the decoder skips unknown item types, which liton's does. Through a
relay, `server_info.features.relayProtectedSecurity: true` is how the client
detects a downgrade (§3).

**Subscriptions.** Live pushes are opt-in per session:

- `session.events.set_subscription.request {events:[…]}` (`messages.ts:3251`)
  subscribes to events such as `agent_permission_request` and
  `checkout_status_update`;
- `agent.timeline.set_subscription.request {agentIds}` (`:1987`) streams
  `agent_stream` for the agents being viewed;
- `fetch_agents_request` and `fetch_workspaces_request` take
  `subscribe:{subscriptionId}`;
- `subscription.release.request` ends a subscription.

The rule in `docs/timeline-sync.md` is to apply live rows in order, and to
re-fetch `direction:"after"` until `hasNewer:false` on a gap. All of these
already exist in 0.9.2. A reconnect with the same `clientId` resumes the
daemon-side session (`websocket-server.ts:1805`).

**Session permissions.** `hello.sessionPermissions` narrows the session.
liton could send `["workspace.read","workspace.write"]`: reads need
`workspace.read`, while `send_agent_message_request`, `agent_permission_response`
and `import_agent_request` need `workspace.write`
(`packages/server/src/server/authorization/operation-permissions.ts`).
Untested.

**Importing sessions from ACP providers.** These two messages already existed
in 0.9.2:

- `fetch_recent_provider_sessions_request {cwd?, providers?, query?, limit≤200}`
  (`messages.ts:1405`) returns entries plus per-provider errors (`:4333`);
- `import_agent_request {provider, sessionId, cwd?, workspaceId?}` (`:1891`)
  makes the session an ordinary Paseo agent.

For a generic ACP provider, the daemon lists sessions only if the agent
advertises `sessionCapabilities.list`. It loads history only with
`loadSession` (`packages/server/src/server/agent/providers/acp-agent.ts:1247-1330`).
It passes `cwd` straight through to ACP `session/list`. Remote sessions
report the virtual directory `/`, so a workspace-scoped query hides them.
The app's "Import session → Show all" just drops `cwd`
(`packages/app/src/components/import-session-sheet.tsx:501-509`). liton
should do the same: list without `cwd` and group by `entry.cwd`.

## 2. Relay v2 transport

All sockets use `GET /ws` with query parameters
(`packages/protocol/src/daemon-endpoints.ts:235`):

```
?serverId=<id>&role=server&v=2                      daemon control socket
?serverId=<id>&role=client&v=2                      client; the relay assigns connectionId
?serverId=<id>&role=server&v=2&connectionId=<cid>   daemon data socket, one per client
```

In `paseo-relay/lib/paseo_relay/ownership.ex`:

- **Control.** On attach the relay sends `{"type":"sync","connectionIds":[…]}`
  (`:339`). It sends `{"type":"connected","connectionId"}` when a client
  arrives (`:361`) and `{"type":"disconnected","connectionId"}` when the last
  socket of a connection leaves (`:383`). The only inbound control message
  is a JSON `{"type":"ping"}`, answered `{"type":"pong","ts"}`
  (`socket.ex:439`). A new control socket replaces the old one with close
  `1008 "Replaced by new connection"`.
- **Client.** It is opaque after the upgrade. Its frames wait up to 15 s for
  the daemon's data socket (`PASEO_RELAY_DATA_ATTACH_TIMEOUT_MS`). The relay
  re-sends `sync` to the control socket after 10 s and resets it with
  `1011` 5 s later (`ownership.ex:281-292`). When the daemon's data socket
  goes away, the client gets `1012 "Server disconnected"` (`:402`).
- **Validation.** The relay parses only the client's `hello` and
  `e2ee_hello` frames. It requires `key` to be a canonical base64 32-byte
  X25519 key, or closes `1008 "Invalid handshake key"` (README;
  `handshake_validation.ex`).
- **Limits.** `serverId` and `connectionId` are at most 256 bytes. A message
  is at most 32 MiB (`1009` above it). Control input is at most 64 KiB
  (`protocol.ex`). `1013` means capacity, memory pressure or no delivery
  route, and is retryable. Paseo caps relay messages at 32 MiB
  (`packages/protocol/src/websocket-message-limit.ts`).
- **Reconnects.** The daemon pings its control socket every 10 s and
  reconnects after 30 s without a pong, or 8 s without `sync`
  (`packages/server/src/server/relay-transport.ts:48-50`). The client retries
  from 1.5 s, doubling to 30 s (`packages/client/src/daemon-client.ts:1123`).
  It also heartbeats every 10 s. A relay restart drops every session, and
  both sides reconnect.
- **Deployment limits outside the relay.** A TLS proxy in front of a relay
  may cap in-flight requests per client IP, for example at 64, answering 429.
  A WebSocket holds its slot for its whole life. The remote daemon is also
  shared with the developer's phone and desktop clients. So liton must hold
  exactly one client socket, back off on 429, `1012` and `1013`, and bound
  its own request rate (see §6).

## 3. End-to-end encryption

`packages/relay/src/secure-channel.ts` has two modes
(`docs/relay-endpoint-security.md`):

- **protected:** `Noise_NK_25519_ChaChaPoly_SHA256` (Noise revision 34),
  prologue `"paseo-relay-e2ee/1"` (`:114`). The primitives come from
  `@noble/curves` x25519, `@noble/ciphers` ChaCha20-Poly1305 and
  `@noble/hashes` SHA-256/HMAC. The Noise state machine is Paseo's own.
- **legacy:** an ephemeral client key with NaCl `box` (X25519 plus
  XSalsa20-Poly1305, `tweetnacl`) and a random 24-byte nonce per message
  (`packages/relay/src/crypto.ts`). It has no replay protection.

The handshake, as the first frames on the client socket:

1. **Client → daemon:**
   `{"type":"e2ee_hello","key":<legacy ephemeral pub b64>,"capabilities":{"binaryCiphertext":true},"protected":{"v":1,"message":<b64 Noise msg1: -> e, es>}}`.
   The Noise payload is two bytes, `[0x01, flags]`, where bit 0 is
   `binaryCiphertext`. The client resends the identical hello every second
   until the daemon answers (`:119`).
2. **Daemon → client:**
   `{"type":"e2ee_ready","protected":{"v":1,"message":<b64 msg2: <- e, ee>}}`,
   whose payload holds the selected flags. Then `split()`: the initiator
   sends with the first cipher state.
3. **Records.** Each application frame becomes
   `(u16 BE len ‖ ciphertext)+`. Every chunk's plaintext is
   `kind(1) ‖ flags FIRST/FINAL(1) ‖ totalLength(u32 BE) ‖ data`, with at
   most 65513 data bytes per chunk (`packages/relay/src/protected-records.ts`).
   The nonce is a 64-bit counter. Any failure closes the channel: the daemon
   uses `1011`, a browser client `4003`. A text frame travels as base64
   WebSocket text. A binary frame travels as WebSocket binary only if
   `binaryCiphertext` was negotiated.
4. **Then the plain protocol**, inside the channel: the client's `hello`
   with `auth`, then the daemon's `server_info`, and so on. The relay never
   sees the password.

The client generates fresh ephemerals per connection and keeps nothing
secret beyond the password. It needs only the daemon's static public key,
from the offer. To stop a downgrade, after a protected handshake the client
pins `minimumMode:"protected"` for that daemon key. With the pin it refuses
a legacy `e2ee_ready` (close `4002`). A client that ended up in legacy mode
closes if `server_info.features.relayProtectedSecurity` is true. The daemon
can refuse legacy clients with `daemon.relay.requireProtectedSecurity`.
liton should implement or use **protected only**.

The daemon's identity is `$PASEO_HOME/daemon-keypair.json`,
`{v:2, publicKeyB64, secretKeyB64}`. These are a 32-byte X25519 pair
(`packages/server/src/server/daemon-keypair.ts`). The same key is the Noise
static key and the key in the pairing offer.

## 4. Pairing

An offer is `https://app.paseo.sh/#offer=<base64url(JSON)>`
(`packages/server/src/server/connection-offer.ts:45`). Its JSON is
(`packages/protocol/src/connection-offer.ts:9`):

```json
{"v":2,"serverId":"…","daemonPublicKeyB64":"…","relay":{"endpoint":"host:port","useTls":true},"minimumSecurityMode":"protected"}
```

`minimumSecurityMode` is present only when the daemon requires protected
mode. The offer carries **no password**: the user types it, and it travels
only as `hello.auth` inside the channel. The app link is the same even when
the daemon's web UI is off. Only the fragment matters, so liton can accept
the link and parse it with `parseConnectionOfferFromUrl`.

An equivalent URI exists, `relay://host:port/<serverId>?key=…&ssl=true&security=protected[&password=…]`
(`daemon-endpoints.ts:22-71`). `paseo daemon pair` prints the offer and a QR
code (`packages/cli/src/commands/daemon/pair.ts`).

The app persists, per host (`packages/app/src/types/host-connection.ts:510-528`):

- `serverId`, the password, and a label;
- a connection `{type:"relay", relayEndpoint, useTls, daemonPublicKeyB64, minimumSecurityMode?}`.

liton should keep the same set in its daemon's SQLite, plus a **stable
`clientId`** so reconnects resume the session. The password is a secret:
reference it from the snapshot, never store it there (design.md, Snapshot).

## 5. The client library

- **`@getpaseo/relay`** (Apache-2.0, 109 KB unpacked) holds the E2EE
  primitives. Its `./e2ee` export provides `openClientSecureChannel(transport, {daemonPublicKeyB64, minimumMode})`
  over a minimal `Transport {send, close, onmessage, onclose, onerror}`.
  Dependencies: `tweetnacl`, `@noble/{curves,ciphers,hashes}`, `base64-js`.
  It also lists `ws`, but the e2ee entry doesn't import it. It runs in a
  plain browser: it needs only `crypto.getRandomValues`. Bundled and
  minified for the browser it is **100 KB, 35 KB gzipped** (measured with
  esbuild).
- **`@getpaseo/client`** (Apache-2.0) is the full SDK: reconnects, the hello,
  the protected pin, downgrade detection, subscriptions and typed
  agent/workspace APIs. Use `createPaseoClient({url: buildRelayWebSocketUrl({endpoint, useTls, serverId, role:"client"}), password, clientId, e2ee:{enabled:true, daemonPublicKeyB64}})`.
  It uses the global `WebSocket` (browsers, Node ≥ 22). Bundled for the
  browser it is **5.3 MB, 646 KB gzipped**. 4.3 MB of that is
  `@getpaseo/protocol`'s generated validators.

Behind roc-signals 0.5 ports, the minimal shape:

- `Port.subscription({name: "paseo/relay"})`: the argument is the pairing,
  `{serverId, endpoint, useTls, daemonPublicKeyB64, clientId}`. The handler
  opens the relay socket and the secure channel, sends `hello`, and `emit`s
  every inbound text frame as one message. Use `Every(n)` delivery, since
  timeline rows must not be dropped. The unsubscribe closes the socket.
  `Threw` or `Closed` reports why: `4002`, `hello.rejected`, a relay close.
- `Port.call({name: "paseo/send", timeout_ms})`: the argument is one
  outbound message, already JSON. The handler answers when the response
  with the same `requestId` arrives, so request and response pair up in
  JavaScript.

The password would be an argument to the subscription, held in page memory.

## 6. Transport options

**A. The browser connects to the relay through ports.** Paseo becomes a
provider running in the page, with true push and no daemon hop. But it
breaks *Separate UI and daemon*. design.md would have to say: "The UI talks
to a liton daemon; a relay-paired Paseo is the exception, reached by the UI
itself through a `paseo/relay` port, with the daemon unaware of it." That
moves into the browser what the daemon does today: merging providers,
deriving `attention`, keeping timeline state in SQLite, holding secrets.
Every open tab becomes another client of a daemon that is shared and
proxy-capped. It needs the password in the page. It covers web only, while
native and TUI renderers would each need their own.

**B. A local bridge (recommended now).** A ~150-line Node process listens on
`ws://127.0.0.1:<port>/ws` and accepts one local client. For it, the bridge
opens the relay client socket, runs `openClientSecureChannel` with
`minimumMode:"protected"`, and pipes frames both ways. On the first local
`hello` it injects `auth` (or liton sends `auth` itself). It knows nothing
else of the protocol.

liton's daemon then changes little:

- `connected!` points at the bridge;
- `Paseo.hello` gains `auth`;
- prompts and permission answers move from MCP to the WebSocket messages
  (§1).

Load, both done by the bridge:

- the bridge keeps the upstream socket across liton's poll cycles. Each new
  upstream socket costs a relay data socket, a Noise handshake and a bcrypt
  check on the shared daemon;
- the bridge refuses a second local client, backs off 1.5 s → 30 s, and
  caps in-flight requests (liton's own-platform budget for Paseo, one
  connection and four in flight, fits).

This keeps *the UI talks only to liton's daemon* intact. Its costs are a
Node runtime dependency and one more process to supervise.

**C. liton's daemon speaks relay, TLS and E2EE itself.** Blocked today:

- basic-webserver 0.21's `Tcp` has only connect, read and write: no TLS
  (`Tcp.roc`);
- its 30-second I/O timeout fits a request-response poll, not a long-lived
  socket;
- Roc's builtin crypto is SHA-256 and BLAKE3 only. The compiler binary's
  only crypto builtins are `roc_builtins_crypto_sha256_*` and
  `roc_builtins_crypto_blake3_*`, so there is no X25519, ChaCha20-Poly1305
  or XSalsa20.

Pure-Roc X25519 and ChaCha20-Poly1305 are possible but slow, and not
constant-time. This becomes natural on liton's own platform
(own-platform-design.md): the host already owns sockets and WebSocket
framing, and can add TLS and a Noise NK channel (protected mode only)
behind `Connect`.

## 7. Local development rig

Nothing in this rig may reach a real deployment.

- **Relay, verified.** Paseo's Cloudflare-adapter relay runs locally in
  workerd. Copy `packages/relay/src` and a `wrangler.toml` with the
  `RELAY` Durable Object binding, **without** `account_id`, `routes` or
  `PASEO_RELAY_UPSTREAM`. The repo's own toml forwards to Paseo's hosted
  relay through `PASEO_RELAY_UPSTREAM`; Paseo's tests clear it with
  `--var PASEO_RELAY_UPSTREAM:`. Then:

  ```sh
  npm i @noble/ciphers @noble/curves @noble/hashes base64-js tweetnacl wrangler@4
  WRANGLER_SEND_METRICS=false npx wrangler dev --local --ip 127.0.0.1 --port 18787
  curl http://127.0.0.1:18787/health   # 200
  ```

- **Elixir relay, unverified.** The image is `ghcr.io/getpaseo/paseo-relay`.
  Pin it by digest and run
  `docker run --rm -p 4000:4000 -e RELEASE_DISTRIBUTION=none …`. From
  source, `mix.exs` needs Elixir ~> 1.20 on OTP 29. nixpkgs (unstable,
  2026-11) has `erlang_29` but stops at `elixir_1_19`, so a nix build needs
  an Elixir 1.20 override. Health is `GET /health` and `/ready`, on port
  4000 by default.
- **Paseo 0.15.3, verified.** `npm i --ignore-scripts @getpaseo/cli@0.15.3`
  gives a working `paseo` binary (571 MB of `node_modules`). Run it in the
  foreground with a throwaway home, and set `HOME` too so it reads no real
  agent credentials:

  ```sh
  H=$(mktemp -d)   # optionally with config.json, below
  env HOME=$H PASEO_HOME=$H PASEO_LISTEN=127.0.0.1:16767 PASEO_PASSWORD=<16+ chars> \
      PASEO_RELAY_ENABLED=true PASEO_RELAY_ENDPOINT=127.0.0.1:18787 PASEO_RELAY_USE_TLS=false \
      PASEO_WEB_UI_ENABLED=false PASEO_DICTATION_ENABLED=false PASEO_VOICE_MODE_ENABLED=false \
      paseo daemon run --home $H
  env HOME=$H PASEO_PASSWORD=<same> paseo daemon pair --home $H --json   # offer URL + relay:// URI
  ```

  With that rig, a client using `@getpaseo/client` connected through the
  relay with E2EE and the password from the offer URL in about 0.5 s, and
  listed agents. A wrong password failed with `incorrect_password`. The
  daemon logged `relay_control_connected`, then `relay_data_connected` per
  client.

  Other ways to get Paseo, unverified: `nix build github:getpaseo/paseo/v0.15.3#paseo`
  (`nix/package.nix`; slow to fetch its npm dependencies), or the image
  `ghcr.io/getpaseo/paseo:0.15.3`.

  Always set `PASEO_RELAY_ENDPOINT`. Otherwise the daemon uses Paseo's
  hosted relay and turns TLS on for it (`packages/server/src/server/config.ts:300-335`).
  `$PASEO_HOME/config.json` holds the rest of the sandbox shape. The rig
  used the first two items:
  - `features.{dictation,voiceMode,webUi}.enabled:false`;
  - `daemon.relay:{enabled:true, endpoint, useTls:false, requireProtectedSecurity:true}`.
    With this, the offer carries `minimumSecurityMode:"protected"`;
  - every built-in provider `enabled:false`, except one ACP provider (below);
  - optionally, a read-only native agent (`disallowedTools` such as Write
    and Edit).
- **TLS.** It isn't needed locally: set `useTls:false` on both ends. To
  exercise `wss`, put a local TLS terminator such as `caddy reverse-proxy`
  with its internal CA in front of the relay. Unverified.
- **A fake sandbox agent.** Configure it as an ACP provider:

  ```json
  {"extends":"acp","label":"Fake sandbox","command":["node","fake-acp.mjs"],
   "options":{"supportsMcpServers":false,"clientCapabilities":{"terminal":false,"fs":{"readTextFile":false,"writeTextFile":false}}},
   "paseoTools":{"enabled":false}}
  ```

  `@agentclientprotocol/sdk` (Apache-2.0; Paseo uses ^0.17.1) ships
  `dist/examples/agent.js`, which streams a scripted turn with a tool call
  and a permission request. Its `initialize` says `loadSession:false`. Add
  `sessionCapabilities:{list:{}}` and `loadSession:true`, a `listSessions`
  returning a few sessions with `cwd:"/"`, and a `loadSession` that replays
  their history as `session/update`s. The SDK's `AgentSideConnection`
  already routes `session/list` and `session/load`. That is the whole
  "remote sessions" path. Unverified.

## 8. What the sandbox setup changes for liton's UI

- **No terminals.** Paseo 0.15.3 has no switch to turn terminals off. The
  setup removes the terminal worker, so terminal requests fail. The
  `terminal` capability must show as missing, not broken.
- **No voice or dictation** (`features.*.enabled:false`).
  `server_info.capabilities.voice` reflects this. Hide `voice`.
- **Read-only code.** The native agent cannot write. Partial clones live
  under a home directory, created by an outside helper (clone, fetch, diff,
  show), not through Paseo's workspace creation. No worktrees are created
  and workspace scripts are off. Diffs that matter compare a **fetched
  branch with `origin/main`**, not uncommitted changes, so
  `checkout.diff.get` with `compare.mode:"base"` is the default view.
  Workspace-creating controls should hide.
- **Writes come from sandboxed agents**, as ACP providers. Their sessions
  live outside the daemon, list with `cwd "/"`, and are imported. Import is
  a first-class action: "Import session", with a "Show all" that drops the
  directory scope. Their history arrives through ACP `session/load`.
- **Permissions.** Agent-facing Paseo tools are typically disabled for these
  providers (`paseoTools.enabled:false`). The user still answers the
  permission requests the agents raise, via `agent_permission_response`.
- **The daemon is shared and remote.** Show the relay link state (connecting,
  handshaking, protected, rejected), never guess "offline". Expect drops
  on relay restarts.

## Open questions

- Should the bridge be Node (reusing Paseo's audited code) or a Rust or Zig
  binary that liton's own platform host can absorb later?
- Does a session narrowed by `sessionPermissions` still receive
  `server_info` and the subscriptions liton needs?
- Does `import_agent_request` for an ACP session with `cwd "/"` place it in
  a workspace the provider can list, and how should liton map it to a
  `workspaces.v1` context?
- How should a pairing reach the liton daemon: a settings form taking the
  offer link and the password, stored as a secret reference?
- When does Paseo flip `requireProtectedSecurity` on by default? liton
  should not depend on legacy mode either way.

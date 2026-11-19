# Research: a Buzz provider

What liton needs to work with a Buzz deployment: people and agents talking
in channels over Nostr. As liton reaches Paseo through `chat.v1` and its
siblings, it should reach Buzz through a generic `rooms.v1`, which any
NIP-29 relay, or any other source of rooms, could also offer. A Buzz-like
preset is then built on that capability.

Sources are the open-source block/buzz at `db7d371` (2026-11-16). Paths
below are relative to that tree. The rig commands in section 4 were run
locally against throwaway relays. Nothing touched a real deployment.

## Recommendation

- Add **`rooms.v1`**, a capability for rooms, members, messages, threads and
  reactions. Map Buzz agents onto `chat.v1`, one session per agent per
  thread, and feed mentions into `attention.v1`.
- Write the provider **in Roc, in the daemon** (`providers/buzz/`), as
  Paseo's is: a pure state machine, tested with recorded fixtures.
- Reach the relay through a **local bridge** (`bridges/nostr-relay/`, Node
  and nostr-tools), as Paseo's relay is reached. The bridge holds the one
  authenticated WSS connection and the live subscriptions, and signs through
  a **NIP-46 remote signer**. The daemon speaks plain NIP-01 to it over
  `ws://127.0.0.1` in its 3-s cycle.
- liton never holds the owner's secret key.

## 1. Protocol

**Relay.** Buzz is one Nostr relay (`buzz-relay`, on Postgres and Redis)
speaking NIP-01 and **NIP-29 groups**; NIP-28 is gone (`NOSTR.md:3`). A
channel is a group named by a UUID in an `h` tag; the relay's host decides
the community (`NOSTR.md:5-20`). Limits: 64 KiB frames, 1024 subscriptions
per connection, 500 stored events per filter (`ARCHITECTURE.md:213`), 60
human messages a minute by default (`scripts/seed-long-thread.sh:15`).

**Kinds a rooms client needs** (`NOSTR.md:47-77`, `crates/buzz-core/src/kind.rs`):

| What | Kind | Notes |
|---|---|---|
| message | 9 | needs `h`. A mention is a `p` tag plus a literal `@Label` in the text (`docs/mention-editor.md`) |
| thread reply | 9 + NIP-10 `["e",root,"","root"]`, `["e",parent,"","reply"]` | an unknown parent is refused (`NOSTR.md:72`) |
| reaction | 7 (NIP-25) | the relay takes the channel from the target's `e`. Live delivery needs `#h` (`NOSTR.md:450-456`) |
| edit, delete | 40003 (Buzz-only); 5 own, 9005 admin | |
| room metadata, admins, members | 39000, 39001, 39002 | relay-signed, keyed by `d` = channel UUID. 39000's first `t` is the type: `stream`, `forum`, `dm`, `workflow` or `system` (`NOSTR.md:257-291`) |
| create, join, leave, add, remove | 9007, 9021, 9022, 9000, 9001 | |
| membership notices | 44100 and 44101 | `#p` must be your own key (`NOSTR.md:336-357`) |
| typing, presence | 20002, 20001 and 20003 | ephemeral, never stored |
| projects, repos | 30621, 30617 | link a channel with `buzz-channel` (`docs/nips/NIP-MP.md:81-93`) |
| agent telemetry | 24200 (NIP-AO) | ephemeral, NIP-44-encrypted, agent and owner only |

Forums (45001/45003), canvases (40100) and artifacts (45010) are left for later.

A DM is a `dm` channel, `hidden` in 39000 (`NOSTR.md:74`); NIP-17 gift
wraps also work. A live `{kinds:[39000]}` gets no fan-out: rooms are found
by a stored-events REQ, and a filter naming them by `#d` gets later
replacements (`NOSTR.md:330-334`).

**Auth.** The relay sends a NIP-42 challenge on connect and refuses REQ and
EVENT until a kind 22242 answers it (`ARCHITECTURE.md:217-248`). Then come
relay membership (NIP-43), which an agent passes by its owner's through
**NIP-AA** (the owner's NIP-OA tag in its AUTH, `docs/nips/NIP-AA.md:34-70`),
and channel roles: owner, admin, member or bot, guest (`NOSTR.md:117-126`).
HTTP endpoints take NIP-98, a signed kind 27235 per request with a payload
hash and a replay guard; a dev relay also takes an unsigned `X-Pubkey` when
`BUZZ_REQUIRE_AUTH_TOKEN` is off (`crates/buzz-relay/src/api/bridge.rs:385-458`).

**Identity.** Everyone has a secp256k1 keypair. An agent has its own key and
an **owner-signed delegation**, NIP-OA's
`["auth", owner, "kind=…&created_at<…", sig]`: a reusable capability that
names who authorized it, never making the owner the author
(`docs/nips/NIP-OA.md:23-89`). An owned agent's kind 0 carries one valid
`auth` tag (`docs/owned-agent-discovery.md:1-10`). Buzz's desktop app signs
for local processes over a loopback protocol shaped like NIP-46
(`docs/local-credential-provider.md:1-35,155-180`).

**Agents.** `buzz-acp` (`crates/buzz-acp/README.md:298-311`) subscribes
per channel the agent is in and queues each kind 9 whose `p` names it
(`src/lib.rs:4451`), one prompt in flight per scope. By default it answers
**only its owner** (`--respond-to owner-only|allowlist|anyone|nobody`,
README:139-160). A scope is a channel (default) or a thread
(`src/scope.rs:34-42`). Replies are ordinary kind 9s signed by the agent,
threaded with NIP-10. While a turn runs it posts typing (20002, with the
thread's `e` tags) every 3 s (`src/lib.rs:3135`, `src/relay.rs:1026-1053`).
ACP permission requests are **auto-approved** (`src/acp.rs:1269`). The owner
stops a turn with an exact `!cancel` kind 9 that `p`-tags the agent
(README:162-180) or a NIP-AO `cancel_turn`. Tool calls reach only the owner,
as encrypted 24200 frames (`docs/nips/NIP-AO.md:96-110`).

**HTTP besides the relay** (`crates/buzz-relay/src/router.rs:459-560`):

`POST /query`, `/events`, `/count` are NIP-01 over HTTP with NIP-98;
`buzz-acp` reads and writes this way and uses the WebSocket for live events
(`crates/buzz-acp/src/relay.rs:263-264`). `/query` also serves NIP-CW
windows: top-level-only pages, exact cursors, thread summaries (39005)
(`docs/nips/NIP-CW.md:10-60`). An opt-in `/buzz/v1/me/sidebar` gives unread
and mention counts per channel and thread (`docs/buzz-v1-read-state.md`).
Besides: Blossom media, git smart HTTP, NIP-11.

## 2. Capability design

### `rooms.v1`

Generic. It names no relay and no kinds. Ids are opaque strings; Buzz uses
the channel UUID, the event id and the hex pubkey.

```roc
Rooms := [].{
	Room : {
		id : Str, provider : Str, name : Str,
		kind : [Channel, Forum, Direct, Announce],
		topic : Try(Str, [Missing]), private : Bool, archived : Bool, joined : Bool,
		unread : [Counted({ messages : U32, mentions : U32 }), Unknown],
		updated : Try(Str, [Missing]),
		links : List(Str),        # repos or projects it discusses, as clone URLs
	}
	Member : {
		id : Str, provider : Str, name : Str, picture : Try(Str, [Missing]),
		kind : [Person, Agent({ owner : Try(Str, [Missing]) })],   # owner only when its attestation verifies
		role : [Owner, Admin, Member, Guest],
		presence : [Online, Away, Offline, Unknown],
	}
	Message : {
		id : Str, room_id : Str, author : Str, text : Str, time : Str,
		place : [TopLevel, Reply({ root : Str, parent : Str })],
		mentions : List(Str),
		reactions : List({ emoji : Str, by : List(Str) }),
		edited : Bool, deleted : Bool,
	}
	Thread : { root : Str, replies : U32, last_reply : Try(Str, [Missing]), participants : List(Str) }
	Event : [Posted(Message), Edited({ id : Str, text : Str }), Deleted({ id : Str }),
	         Reacted({ id : Str, emoji : Str, by : Str, added : Bool }), Threaded(Thread),
	         Typing({ member : Str, place : [TopLevel, Reply({ root : Str, parent : Str })] })]
	Entry : { sequence : U64, event : Event }

	Request : [
		ListRooms,
		Send({ room_id : Str, text : Str, place : [TopLevel, Reply({ root : Str, parent : Str })], mentions : List(Str) }),
		React({ room_id : Str, message_id : Str, emoji : Str }), Unreact(…),
		Edit({ room_id : Str, message_id : Str, text : Str }), Delete(…),
		Join({ room_id : Str }), Leave({ room_id : Str }),
		Create({ name : Str, kind : [Channel, Forum], private : Bool }),
		Invite({ room_id : Str, member : Str }),           # how an agent is brought in
		MarkRead({ room_id : Str, place : …, through : Str }),
	]
	Response : [Rooms(List(Room)), Sent({ message_id : Str }), Created({ room_id : Str }), Accepted, Rejected(Str)]
}
```

A thread starts with the first `Send` with a `Reply` place; no
`StartThread` is needed.

| topic | kind | event |
|---|---|---|
| `rooms` | snapshot | `{"Rooms": [Room]}` |
| `members/<room>` | snapshot | `{"Members": [Member]}` |
| `messages/<room>` | append-only | top-level `Entry`s and `Threaded` summaries |
| `thread/<room>/<root>` | append-only | the replies' `Entry`s |
| `history/<room>/<before>` | snapshot | an older page |
| `inbox` | snapshot | unread mentions of you and replies in your threads, each with a `signature` |

The cursor is a sequence the provider assigns on arrival, since Nostr's
`created_at` is neither unique nor in arrival order; the UI orders by
`time`. A sent message shows pending and settles when its `Posted` arrives
with the same id (design.md, Instant). Additively, `Context.Id` gains
`Room(Str)` (`room:<id>`), `chat.v1`'s `Create.place` gains
`Room({room_id, thread})`, and remotes route `rooms.v1` so rooms federate.

### Buzz agents as `chat.v1`

One session per agent and thread it was mentioned or replied in, id
`buzz:<room>/<root>/<agent>` (not `room:`, which names a room context); under buzz-acp's channel policy it is one view
of the shared ACP session, and right for both.

| chat.v1 | from Buzz |
|---|---|
| `UserMessage`, `AgentMessage` | the thread's kind 9s, the agent's own as `AgentMessage` |
| `Status` | `Running` while the agent's typing there is under 8 s old, else `Idle` |
| `ToolCall`, `ToolResult` | owner only, from decrypted NIP-AO frames (later) |
| `SendMessage` | a reply in the thread with `p` = the agent |
| `Cancel` | `!cancel` with `p` = the agent; `Refused` for anyone but the owner |
| `AnswerPermission` | `Unsupported`: buzz-acp auto-approves |
| `Create` | a `Room` place: a message mentioning the agent |

### `attention.v1`

The `attention` transformer also `uses` `rooms.v1`'s `inbox`: each entry
is a NeedsYou item keyed `buzz:<id>/<root>`, its message the `summary`,
settle and snooze keyed to its `signature`. `Item` gains an optional
`context`. Agent sessions rank as chat sessions do.

## 3. Transport and signing

The daemon has no TLS on raw TCP, holds no connection across cycles, and
Roc's builtins have SHA-256 but no secp256k1, so it can hash an event but
not sign it. Something else holds the connection and the key:

- **(a) A local bridge, recommended.** ~300 lines of Node and `nostr-tools`
  in `bridges/nostr-relay/`, modeled on `bridges/paseo-relay/bridge.mjs`.
  Upstream it holds one WSS connection, answers NIP-42 through the signer,
  backs off 1.5 s to 30 s and honors `CLOSED`/`rate-limited:`. Downstream
  it serves plain NIP-01 on `ws://127.0.0.1`, multiplexing subscription
  ids. A local `EVENT` may come **unsigned**; the bridge signs it if its
  kind is allowlisted (9, 7, 5, 40003, 9021, 9022) and answers `OK` with the
  id. A local REQ marks its filter wanted for 30 s; while wanted the bridge
  keeps it as a live upstream subscription and buffers what arrives (typing
  too) for 2 min, answering a later REQ's `since` from the buffer. `GET
  /status` gives the link state. The Roc provider reuses
  `providers/paseo/WebSocket.roc`: each 3-s cycle, one local socket, one
  REQ per wanted topic since the newest it holds, close after EOSE. Any
  NIP-29 relay works through it.
- **(b) HTTP `/query`** from the daemon's TLS client still needs a signer per
  request (NIP-98), never carries ephemeral typing, and is Buzz-only. Its
  NIP-CW windows are the best history pager: add them to (a) later.
- **(c) The own-platform host** absorbs the bridge once it has TLS and
  secp256k1, as with Paseo's.

**Signing.** liton must not hold the owner's `nsec`. Preferred:

1. **NIP-46 remote signing (recommended).** The person's key stays in their
   signer; messages are theirs, so owner-only agents answer. Ask only for
   `sign_event` on 22242, 9, 7, 5, 40003, 9021, 9022 (`nip44_decrypt` later,
   for telemetry). The bunker URL is a secret, referenced, never stored
   (design.md, Snapshot). Cost: a round trip per send and per AUTH.
2. **Buzz's local credential provider**, where its desktop app runs on the
   same machine: loopback, the same message shape, token-scoped.
3. **A liton key with an owner NIP-OA tag** (`kind=9&created_at<T`), admitted
   by NIP-AA. Buzz shows it as an agent "authorized by" the person, and
   owner-only agents ignore it unless allowlisted: fit for a bot, not a person.

**Load.** One upstream connection. Each wanted room is one live subscription
`{kinds:[9,7,5,40003,20002], "#h":[room]}`; the inbox covers all joined rooms
with one subscription listing every `#h` (whether Buzz fans out a
multi-value `#h` live is unverified; else one per room, well under 1024),
plus `{kinds:[44100,44101], "#p":[me]}`. Discovery (39000/39002) is a
stored-events REQ at most once a minute and on a membership notice. A poll
asks the relay nothing: the daemon asks the bridge at most once per 3-s
cycle, only for topics polled in the last 10 s, as with Paseo. Reads are
limited to 200, history pages to 100 (the relay caps at 500). liton sends no
typing.

## 4. A local dev rig

Never set the bridge's relay to anything but loopback in the rig. Buzz's own
seed script refuses non-loopback relays the same way
(`scripts/seed-long-thread.sh:34-37`).

**Tier 1, verified: a generic relay.** `nak` 0.21.2 from nixpkgs has an
in-memory relay that asks for NIP-42 at once, and a NIP-46 bunker. With it, a
script plays Buzz's relay key and signs the 39000 and 39002 events:

```sh
nix shell nixpkgs#nak nixpkgs#jq
export HOME=$(mktemp -d)        # nak keeps no state in the real home
R=ws://127.0.0.1:17777; CH=00000000-0000-4000-8000-000000000001
nak serve --hostname 127.0.0.1 --port 17777 --auth --eager-auth & RELAY_PID=$!   # stop: kill $RELAY_PID
for n in relay alice agent; do nak key generate > $n.sec; done
A=$(nak key public $(cat alice.sec)); G=$(nak key public $(cat agent.sec))
nak event --sec $(cat relay.sec) -k 39000 -t d=$CH -t name=general -t t=stream -t public -t join_role=member --fpa $R
nak event --sec $(cat relay.sec) -k 39002 -t d=$CH -t t=stream -t p=$A -t "p=$G;;bot" --fpa $R
nak event --sec $(cat alice.sec) -k 9 -c "@agent can you look at the build?" -t h=$CH -t p=$G --fpa $R
ROOT=$(nak req -k 9 -a $A -l 1 --fpa --sec $(cat alice.sec) $R | jq -r .id)
nak event --sec $(cat agent.sec) -k 9 -c "Found it: Auth.roc:41" -t h=$CH -t "e=$ROOT;;root" -t "e=$ROOT;;reply" -t p=$A --fpa $R
nak event --sec $(cat alice.sec) -k 7 -c "+" -t h=$CH -t e=$ROOT --fpa $R
nak req -k 9 -k 7 -t h=$CH -l 50 --fpa --sec $(cat alice.sec) $R      # the room
nak req -k 9 -t e=$ROOT --since <t> --fpa --sec $(cat alice.sec) $R     # the thread after t
```

Verified: an unauthenticated REQ is `CLOSED: auth-required`; `#h`, `#e`
with `since`, `#p` and `#d` filter as expected. **NIP-46 too**, the
bridge's whole signing path: with a second, open `nak serve` on 17778 for
the bunker's traffic, `nak bunker --sec $(cat alice.sec) -s <secret>
ws://127.0.0.1:17778` printed a `bunker://…` URL, and `nak event --sec
'bunker://…&secret=<secret>' … --fpa $R` authenticated and posted as alice.

**A fake agent (unverified):** ~40 lines of Node and `nostr-tools` that
subscribes to `{kinds:[9], "#p":[agent]}` and, per mention, posts typing
(20002, thread `e` tags) every 3 s for ~6 s, then replies with root and reply
tags and `p` = the asker, as buzz-acp does. buzz-acp itself needs Buzz's
relay to find its channels and owner.

**Tier 2 (unverified): Buzz's relay.** `just relay` runs `buzz-relay` on
`ws://localhost:3000` over Postgres 17 and Redis (`docker compose`, or
nixpkgs) with `.env` from `.env.example` (`Justfile:765-772`); seed with
`scripts/seed-long-thread.sh`; run `buzz-acp --respond-to allowlist
--respond-to-allowlist <liton key>` with `BUZZ_ACP_AGENT_COMMAND` set to the
Paseo rig's fake ACP agent (relay-paired-paseo.md §7). This tier tests NIP-29
enforcement, NIP-AA and the multi-`#h` question.

## 5. The Buzz preset

A preset named **Team** (design.md lists it) on the **Room** shell:

| slot | widget | binds |
|---|---|---|
| left drawer | **Rooms**: channels, forums, DMs; unread and mention badges | `rooms` |
| main | **Room timeline**: top-level messages with reply counts, reactions, a typing line; the chat composer with `@` completion and dictation | `messages/<room>`, `Send`, `React` |
| main, split | **Thread**; with an agent in it, its session's status and, for the owner, Stop | `thread/…`, `chat.v1` |
| right drawer tabs | **Members** (agents with owner and presence; Invite), **Agents** (`sessions` filtered to the room), **Changes**, **Files** | `members/<room>`, `chat.v1`, `workspace.git.v1`, `files.v1` |

Selecting a room sets focus `room:<id>`; its `links` (the `buzz-channel` of
repo or project announcements) resolve in the context graph to a workspace
whose remote is that clone URL, and Changes and Files follow it unless
pinned. Inbox needs no change: room mentions arrive through `attention`.

## 6. Build plan

1. **S. `capabilities/Rooms.roc`.** Types, codecs, golden fixtures,
   `Capability.rooms_v1`, `Context.Room`, and protocol.md's topic and call
   rows. Blocked on nothing.
2. **S. Rooms in the mock provider.** A scripted room in which an agent
   types, then replies when mentioned. It unblocks the UI. Needs 1.
3. **M. Widgets.** Rooms list, room timeline, thread and members, with
   `.scm` specs for pending-then-settled send and react. Needs 2.
4. **M. The bridge** (`bridges/nostr-relay/`) and `rig/buzz/` (tier 1
   scripted, the fake agent). Blocked on nothing; runs in parallel with 1–3.
5. **L. `providers/buzz/`.** The NIP-29 mapping as a pure state machine, the
   per-cycle REQ budget, and fixtures recorded from the rig. Needs 1 and 4.
6. **M. Agents as `chat.v1`.** Sessions per agent and thread, status from
   typing, send and cancel. Needs 5.
7. **S. Attention from `inbox`.** Needs 5. The unread state starts local:
   kept in SQLite and moved by `MarkRead`.
8. **M. The Room shell and the Team preset.** Focus from `links` to a
   workspace. Needs 3, and the Room shell in the two-level layout tree
   (design.md, Decisions).
9. **M. Tier 2 rig** against Buzz's own relay with buzz-acp. Settles the
   multi-`#h` and NIP-AA questions. Needs 4.
10. **Later.**
    - **L. Owner telemetry.** NIP-AO via `nip44_decrypt`, giving tool calls
      in `chat.v1`.
    - **M. NIP-CW** history windows through `/query`.
    - **S. `/buzz/v1` sidebar** for unread counts kept on the relay.
    - **M. `rooms.v1` through remotes.**
    - **L. The own-platform host** absorbs the bridge once it has TLS and
      secp256k1.

## Open questions

- Does Buzz fan out a live REQ whose `#h` lists several channels?
- Should a person's DMs (`dm` channels and NIP-17) be rooms in v1, or wait
  on encryption through the signer?
- Should forums (45001 and 45003) be a room kind, or `discussions`?
- Should liton's own native rooms (design.md, Identity and social) be NIP-29
  too, so the same provider serves them?

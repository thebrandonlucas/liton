# liton's capability protocol

The narrow waist between liton's daemon and everything that uses it or feeds it
([design.md](design.md), Architecture). A draft, which the daemon serves at `/liton/v1` (the Wire section),
and the UI speaks.

## Capabilities

A capability is a named, versioned interface: `chat.v1`, `workspace.git.v1`,
`attention.v1`, `workspaces.v1`. Its types live in the `capabilities` Roc package,
which the daemon, the UI and the CLI all import, so a wire mismatch is a compile
error. Each capability defines:

- **calls**: a `Request` tag union and its `Response`, one answer per request;
- **topics**: streams of events a client can follow, each event with a cursor.

**Versions.** The major version is in the name. Within a major version, changes
are additive only: new optional fields, new tags a client may ignore. A breaking
change is a new name (`chat.v2`), offered beside the old one for as long as
clients use it. A client says which versions it accepts; the daemon answers with
the newest both share.

**Provenance.** Several providers can offer one capability. Every item they
return carries its `provider`, and a call that targets one provider names it.

## Wire

JSON over HTTP, under one prefix, `/liton/v1`. Field names and tag encodings are
those of Roc's `Json` codec for the types in `capabilities/Protocol.roc` and the
capability's own: a tag without a payload is a string (`"ListSessions"`), one
with a payload an object of one field (`{"SendMessage": {…}}`), and an optional
field is left out when absent.

### Manifest

`GET /liton/v1/manifest` lists what the daemon offers, and the topics of each
capability as patterns:

```json
{
  "protocol": 1,
  "daemon": { "id": "liton", "name": "liton" },
  "providers": [
    { "id": "paseo", "name": "Paseo", "capabilities": [{ "name": "chat", "version": 1 }, …] }
  ],
  "transformers": [
    { "id": "attention", "name": "Attention", "offers": { "name": "attention", "version": 1 }, "uses": [{ "name": "chat", "version": 1 }] }
  ],
  "topics": [
    { "capability": { "name": "chat", "version": 1 }, "patterns": ["sessions", "timeline/<session_id>"] }, …
  ]
}
```

A capability is offered when a provider supplies it or a transformer derives
it. A client binds to capabilities, never to providers; it uses the manifest to
show what is missing and who could supply it.

### Call

`POST /liton/v1/call`

```json
{ "capability": "chat.v1", "provider": "paseo", "request": { "SendMessage": { "session_id": "…", "text": "…" } } }
```

`provider` is optional; without it the daemon asks every provider of the
capability and merges the answers, each item tagged with its `provider`. With
it, only that provider's items and sessions are reached. The answer is the
capability's `Response`, or an error:

```json
{ "Ok": "Accepted" }
{ "Err": { "code": "NotFound", "message": "no session fix-auth" } }
```

Error codes are a closed set shared by all capabilities:

| code | when |
|---|---|
| `BadRequest` | the body isn't a call, the capability's name is malformed, or the request isn't one of the capability's requests |
| `NotFound` | no such session or pending permission request, or the named provider doesn't offer the capability |
| `Unavailable` | the provider can't be reached |
| `Refused` | the provider said no, such as to liton's password |
| `Unsupported` | the daemon offers no such capability or version, or the capability has no calls (`workspace.git.v1`) |
| `Overloaded` | try later (not used yet) |

The calls: `chat.v1`'s `ListSessions`, `WatchSession`, `SendMessage` and
`AnswerPermission`; `attention.v1`'s `ListItems`, `Settle`, `Snooze` and
`Unsettle`; `workspaces.v1`'s `ListWorkspaces`.

### Subscribe

`POST /liton/v1/poll` follows any number of topics at once, each after the
cursor the client has (`""` for none):

```json
{ "topics": [
  { "capability": "chat.v1", "topic": "sessions", "after": "" },
  { "capability": "chat.v1", "topic": "timeline/fix-auth", "after": "41" },
  { "capability": "workspace.git.v1", "topic": "changes/fix-auth/Uncommitted", "after": "9618…" }
] }
```

The answer gives each topic, in order, its new events and its new cursor, or no
events when nothing changed:

```json
{ "topics": [
  { "capability": "chat.v1", "topic": "sessions", "cursor": "1433…", "events": [{ "Sessions": [ … ] }] },
  { "capability": "chat.v1", "topic": "timeline/fix-auth", "cursor": "43", "events": [{ "Entry": { "sequence": 42, "event": … } }, …] },
  { "capability": "workspace.git.v1", "topic": "changes/fix-auth/Uncommitted", "cursor": "9618…", "events": [] }
] }
```

| capability | topic | kind | event |
|---|---|---|---|
| `chat.v1` | `sessions` | snapshot | `{"Sessions": [Session]}` |
| `chat.v1` | `timeline/<session_id>` | append-only | `{"Entry": {"sequence", "event"}}`, one per entry |
| `chat.v1` | `importable` | snapshot | `{"Importable": [{"session", "directory"}]}` |
| `attention.v1` | `items` | snapshot | `{"Items": [Item]}`, ranked |
| `workspaces.v1` | `list` | snapshot | `{"Listed": {"projects", "workspaces"}}` |
| `workspace.git.v1` | `changes/<context>/<scope>` | snapshot | `{"Changes": {"workspace", "status", "changes", "commits"}}` |
| `workspace.git.v1` | `file/<context>/<scope>/<path>` | snapshot | `{"File": {"path", "hunks"}}` |

`importable` lists the sessions a provider keeps but doesn't run, such as a
sandboxed agent's, read only, each with the directory it worked in.

A `changes` or `file` context is a session id, or `workspace:<id>`; its scope
is `Uncommitted`, `AgainstBase` or `Commit:<sha>`. A `changes` event holds the
workspace (`Unknown` while it can't be read), its status, the scope's changed
files with their `fingerprint`, and the branch's commits. A `file` event holds
the hunks of one of those files, none when the scope has no such file; its path
is written with `%` as `%25` and `/` as `%2F`, so `src/Auth.roc` is
`file/fix-auth/Uncommitted/src%2FAuth.roc`.

A cursor is opaque to the client: for an append-only topic the last sequence
number, for a snapshot topic a fingerprint of its value, whose one event is the
whole new value. A client asks again with the cursors it was given. A topic the
daemon can't follow keeps its cursor, has no events and says why, without
failing the others: `"error": {"code": "NotFound", "message": "chat.v1 has no topic …"}`
(`Unsupported` for a capability it doesn't offer, `BadRequest` for a cursor that
isn't the topic's). A body that isn't a poll is answered `400`.

Polling a topic also tells the daemon someone wants it, which is what drives the
daemon's own budgeted work upstream (see design.md, Paseo load). The daemon
notes what all of a poll's topics want before asking upstream, so one poll costs
at most one round of upstream work.

The same topics will also stream: `GET /liton/v1/stream?topic=…` as server-sent
events with the cursor as the event id, so a reconnect resumes with
`Last-Event-ID`. Polling stays as the fallback.

## Providers outside the daemon

A provider outside the daemon speaks the protocol clients do: it serves
`/liton/v1` over HTTP (Wire, above), so it can be a small HTTP server in any
language, and a liton daemon is one already, which is how daemons federate.
The daemon is its client. `examples/provider-echo/` is the smallest one, in
Roc: chat.v1 for two scripted sessions.

The contract is the manifest's `protocol` and `providers` (a provider outside
the daemon may leave out the rest), `call` for the capabilities they list,
and `poll` for their topics. A daemon is given its providers outside it, until
a Litonfile declares them, in `LITON_PROVIDERS`, comma-separated:

```sh
LITON_PROVIDERS="echo=http://127.0.0.1:8096,team=https://liton.example"
```

A name is letters, digits, `-` and `_`. Then:

- **Names.** All a remote offers is named under its name, `<name>/<its id>`:
  its providers (`echo/echo`, `team/paseo`), sessions (`team/fix-auth`),
  projects and workspaces (and the sessions each lists). That is the
  provenance, and it keeps ids unique however many remotes there are: a
  local id never starts with a name and a `/` (Paseo's ids with a `/` start
  with `import:`). Federated again, the names nest: `home/team/fix-auth`.
- **Manifest.** The daemon asks each remote for its manifest at start, then
  every minute, and adds its providers with the capabilities the daemon routes
  (`chat.v1`, `workspaces.v1`, `workspace.git.v1`). A remote's transformers
  are left out: the daemon's own derive from every provider (Transformers).
- **Calls.** A call to a remote's session (`SendMessage`, `WatchSession`,
  `AnswerPermission`) is forwarded to it with the session and provider as it
  names them, and its answer returned as given. Lists (`ListSessions`,
  `ListWorkspaces`) merge the remotes' with the daemon's own.
- **Topics.** A topic of a remote's session or workspace
  (`timeline/team/fix-auth`, `changes/team/fix-auth/Uncommitted`) follows the
  remote's own (`timeline/fix-auth`); `sessions`, `importable` and `list`
  merge each remote's. A client's poll notes what it wants of each remote;
  the daemon asks a remote at most every `LITON_PROVIDERS_INTERVAL_MS`
  (default 1000), in one poll of all that clients watched of it within the
  last 10 s, after the cursors it has, and answers every client from what it
  kept. However many clients poll, a remote sees one poll per interval at most.
- **Failures.** A remote that can't be reached, or answers anything but a
  manifest or a poll, is down: one line on stderr, its providers left out of
  the manifest and its sessions out of the lists, its topics and calls
  `Unavailable`, and the rest of each poll answered as before. It is asked
  again after a second, then two, doubling up to a minute, and its coming back
  is logged too.

Later, when the daemon's platform can hold connections
([research/own-platform-design.md](research/own-platform-design.md)), a
provider can instead keep one open: a stream of JSON lines on its stdin and
stdout when the daemon starts it, or a WebSocket when it runs on its own. The
same model, pushed rather than polled:

| From | Message | Meaning |
|---|---|---|
| provider | `{"hello": {"provider": {"id","name"}, "capabilities": [...], "protocol": 1}}` | what it offers |
| daemon | `{"call": {"id", "capability", "request"}}` | a call routed to it |
| provider | `{"answer": {"id", "response"}}` | the call's `Response`, or `{"error": {...}}` |
| daemon | `{"want": {"capability", "topic", "after"}}` / `{"drop": {...}}` | start or stop following a topic |
| provider | `{"events": {"capability", "topic", "cursor", "events"}}` | new events on a followed topic |

The daemon owns caching and fan-out to clients either way, so a provider sees
each topic wanted once however many clients follow it, and keeps its own
upstream within budget. A provider compiled into the daemon implements the
same exchange as a pure state machine.

## Transformers

A transformer is a part that uses capabilities and offers one: `attention.v1` is
derived from `chat.v1`. Transformers compose, which is how a setup pipes one
view of its agents into another.

A transformer is a pure Roc value, a `Transformer.Part` (`transformers/`),
which declares:

- `id` and `name`, as the manifest's `transformers` lists it;
- `offers`: the capability it offers and its topics' patterns, which the
  manifest's `topics` lists;
- `uses`: the topics it follows, such as `chat.v1`'s `sessions`, and
  `follows`, the further topics those lead to, such as each listed session's
  `timeline/<session_id>`;
- `derive`: from the latest events of those topics (a snapshot's value, a
  timeline's entries from the first), its stored state and the time, its new
  state and the events of each topic it offers;
- `call`: from the same inputs, its state, a call's body and the time, its new
  state and the call's answer.

The daemon hosts every transformer the same way, knowing none of them:

- **Offered.** A transformer is offered once the capabilities it uses are,
  by a provider or a transformer registered before it, so one may use
  another's output but never its own. The manifest lists it with the
  capabilities of the topics it uses.
- **Inputs.** A client's poll of a transformer's topic notes that the topics
  it `uses` are wanted, as a poll of those would, recursively for a
  transformer's output; the topics it `follows` are read from what the daemon
  keeps, with no work upstream. So a transformer adds no load beyond its
  `uses`: attention asks no provider for a timeline no client watches, and
  derives from what the daemon has of it.
- **Topics.** Each poll of an offered topic derives it again and answers it
  like any topic: a snapshot by its fingerprint, entries after their
  cursor. A topic it doesn't offer is `NotFound`.
- **Calls.** A call to the capability goes to `call`, whose answer is
  returned as given.
- **State.** The daemon keeps each transformer's state, its own JSON, in
  SQLite, and stores a new one only if no other was stored since it read it;
  a call that loses is asked again. Attention's state is the settles and
  snoozes that still hold.

`attention.v1` is always registered. `needs-you.v1`, attention's items that need
you, is offered when `LITON_TRANSFORMERS` names it (`LITON_TRANSFORMERS=needs-you`),
to show and check composition; a Litonfile will declare a setup's transformers.
A remote's transformers are not routed: the daemon derives its own from every
provider, local or remote.

## The CLI

`liton` speaks this protocol and prints JSON lines, so it composes with other
tools:

```sh
liton manifest
liton call chat.v1 '"ListSessions"'
liton call chat.v1 '{"SendMessage":{"session_id":"fix-auth","text":"Try again"}}'
echo '"ListItems"' | liton call attention.v1   # the request from stdin, also as -
liton watch chat.v1 timeline/fix-auth      # one event per line, until interrupted
liton watch chat.v1 timeline/fix-auth --after 41 attention.v1 items --interval 500   # several topics
liton watch chat.v1 timeline/fix-auth | jq -r '.Entry.event.AgentMessage.text // empty'
```

It finds the daemon from `LITON_URL` (default `http://127.0.0.1:8095`).
`call` prints the answer, `{"Ok": …}` or `{"Err": …}`, and exits 1 on an
error, with its message on stderr. `watch` polls every `--interval`
milliseconds (default 1000), from `--after`, the cursor of the topic before
it, if given; following several topics, it wraps each event as
`{"capability", "topic", "event"}`. It exits 1 when a topic can't be
followed. Either exits 2 on a usage error or when the daemon can't be
reached.

`liton setup [path]` speaks no protocol: it runs a Litonfile (by default
`./Litonfile.roc`, or the one in a directory given) with `roc`, and writes the
setup it prints to `liton.setup.json` (design.md, Setups). It exits 1 when
the Litonfile fails or prints something other than a setup, and 2 when `roc`
can't be run.

## Agents

The daemon's MCP face offers each capability's calls as tools and its topics as
resources, so an agent works with the same capabilities as a person.

## Open questions

- Authentication between a client and a daemon that isn't on the same machine.
- Whether a capability's operations should be listed like its topics, so that
  an unknown one is `Unsupported` rather than `BadRequest`.

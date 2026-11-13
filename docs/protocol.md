# liton's capability protocol

The narrow waist between liton's daemon and everything that uses it or feeds it
([design.md](design.md), Architecture). A draft, which the daemon serves at `/liton/v1` (the Wire section); its earlier
endpoints (`/api/chat`, `/api/chat/poll`, `/api/git/poll`, `/api/attention`,
`/api/workspaces`) remain until the UI moves onto it.

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
field is left out when absent. The daemon's older `/api/…` endpoints stay until
the UI moves onto these.

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
| `attention.v1` | `items` | snapshot | `{"Items": [Item]}`, ranked |
| `workspaces.v1` | `list` | snapshot | `{"Listed": {"projects", "workspaces"}}` |
| `workspace.git.v1` | `changes/<context>/<scope>` | snapshot | `{"Changes": {"workspace", "status", "changes", "commits"}}` |

A `changes` context is a session id, or `workspace:<id>`; its scope is
`Uncommitted`, `AgainstBase` or `Commit:<sha>`. Its event holds the workspace
(`Unknown` while it can't be read), its status, the scope's changed files with
their `fingerprint`, and the branch's commits; a file's hunks are not on the
protocol yet.

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

A provider in any language speaks the same model over a stream of JSON lines, on
its stdin and stdout when the daemon starts it, or on a WebSocket when it runs on
its own. Messages, one per line:

| From | Message | Meaning |
|---|---|---|
| provider | `{"hello": {"provider": {"id","name"}, "capabilities": [...], "protocol": 1}}` | what it offers |
| daemon | `{"call": {"id", "capability", "request"}}` | a call routed to it |
| provider | `{"answer": {"id", "response"}}` | the call's `Response`, or `{"error": {...}}` |
| daemon | `{"want": {"capability", "topic", "after"}}` / `{"drop": {...}}` | start or stop following a topic |
| provider | `{"events": {"capability", "topic", "cursor", "events"}}` | new events on a followed topic |

The daemon owns caching and fan-out to clients, so a provider sees each topic
wanted once however many clients follow it, and keeps its own upstream within
budget. A provider compiled into the daemon implements the same exchange as a
pure state machine; a remote liton daemon can be one too.

## Transformers

A transformer is a part that uses capabilities and offers one: `attention.v1` is
derived from `chat.v1`. It is declared like a provider, with what it `uses`; the
daemon feeds it the events of the topics it needs and serves what it offers like
any other capability. Transformers compose, which is how a setup pipes one view
of its agents into another.

## The CLI

`liton` speaks this protocol and prints JSON lines, so it composes with other
tools:

```sh
liton manifest
liton call chat.v1 '"ListSessions"'
liton call chat.v1 '{"SendMessage":{"session_id":"fix-auth","text":"Try again"}}'
liton watch chat.v1 timeline/fix-auth      # one event per line, until interrupted
liton watch chat.v1 timeline/fix-auth | jq -r '.Entry.event.AgentMessage.text // empty'
```

It finds the daemon from `LITON_URL` (default `http://127.0.0.1:8095`).

## Agents

The daemon's MCP face offers each capability's calls as tools and its topics as
resources, so an agent works with the same capabilities as a person.

## Open questions

- Authentication between a client and a daemon that isn't on the same machine.
- Whether a capability's operations should be listed like its topics, so that
  an unknown one is `Unsupported` rather than `BadRequest`.

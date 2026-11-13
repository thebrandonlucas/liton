# liton's capability protocol

The narrow waist between liton's daemon and everything that uses it or feeds it
([design.md](design.md), Architecture). A draft: the daemon's current endpoints
(`/api/chat`, `/api/chat/poll`, `/api/git/poll`, `/api/attention`,
`/api/workspaces`) are early, ad-hoc forms of it and move onto it.

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
those of Roc's `Json` codec for the capability's types.

### Manifest

`GET /liton/v1/manifest` lists what the daemon offers:

```json
{
  "protocol": 1,
  "daemon": { "id": "…", "name": "…" },
  "providers": [
    { "id": "paseo", "name": "Paseo", "capabilities": [{ "name": "chat", "version": 1 }, …] }
  ],
  "transformers": [
    { "id": "attention", "offers": { "name": "attention", "version": 1 }, "uses": [{ "name": "chat", "version": 1 }] }
  ]
}
```

A client binds to capabilities, never to providers; it uses the manifest to show
what is missing and who could supply it.

### Call

`POST /liton/v1/call`

```json
{ "capability": "chat.v1", "provider": "paseo", "request": { "SendMessage": { "session_id": "…", "text": "…" } } }
```

`provider` is optional; without it the daemon asks every provider of the
capability and merges the answers. The answer is the capability's `Response`:

```json
{ "Ok": { "Accepted": {} } }
{ "Err": { "code": "NotFound", "message": "no session …" } }
```

Error codes are a closed set shared by all capabilities: `BadRequest`,
`NotFound`, `Unavailable` (the provider can't be reached), `Refused` (it said
no), `Unsupported` (version or operation), `Overloaded` (try later).

### Subscribe

`POST /liton/v1/poll` follows any number of topics at once:

```json
{ "topics": [
  { "capability": "chat.v1", "topic": "sessions", "after": "" },
  { "capability": "chat.v1", "topic": "timeline/fix-auth", "after": "41" },
  { "capability": "workspace.git.v1", "topic": "changes/fix-auth/Uncommitted", "after": "fp:9c1e…" }
] }
```

The answer gives each topic its new events and its new cursor, or nothing when
nothing changed:

```json
{ "topics": [
  { "capability": "chat.v1", "topic": "timeline/fix-auth", "cursor": "43", "events": [ … ] },
  { "capability": "workspace.git.v1", "topic": "changes/fix-auth/Uncommitted", "cursor": "fp:9c1e…", "events": [] }
] }
```

A cursor is opaque to the client: a sequence number for an append-only topic, a
fingerprint for a snapshot topic (whose one event is the whole new value). A
client asks again with the cursors it was given. Polling a topic also tells the
daemon someone wants it, which is what drives the daemon's own budgeted work
upstream (see design.md, Paseo load).

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
liton watch chat.v1 timeline/fix-auth | jq -r '.AgentMessage.text // empty'
```

It finds the daemon from `LITON_URL` (default `http://127.0.0.1:8095`).

## Agents

The daemon's MCP face offers each capability's calls as tools and its topics as
resources, so an agent works with the same capabilities as a person.

## Open questions

- Whether a call to several providers merges answers or returns them per provider.
- Authentication between a client and a daemon that isn't on the same machine.
- How a client learns which topics a capability has: listed in the manifest, or
  part of the capability's types.

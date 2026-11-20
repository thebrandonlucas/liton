# liton's capability protocol

The narrow waist between liton's daemon and everything that uses it or feeds it
([design.md](design.md), Architecture). A draft, which the daemon serves at `/liton/v1` (the Wire section),
and the UI speaks.

## Capabilities

A capability is a named, versioned interface: `chat.v1`, `workspace.git.v1`,
`attention.v1`, `workspaces.v1`, `files.v1`, `review.v1`, `rooms.v1`, `tickets.v1`, `schedules.v1`, `hosts.v1`, `usage.v1`, `limits.v1`. Its types live in the `capabilities` Roc package,
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

A POST's body is sent as `Content-Type: application/json`. So that a page of
another site in a browser can't use it, the daemon answers `403` to a request
whose `Origin` isn't its own address, to a POST of another type, and to one
naming a host other than `LITON_HOST`, `localhost` or one of
`LITON_ALLOWED_HOSTS`.

### Authentication

Every route under `/liton/v1` but `pair` answers only a paired device,
and `401` to any other. The UI (`/ui`) and the docs (`/docs`) hold no
secrets and are served to anyone.

- **Pairing.** A device pairs once, with a pairing code: 8 symbols such as
  `K7QM-4XWP`, used once, for 10 minutes. `liton pair`, run on the daemon's
  machine, makes one (The CLI), and so does a paired device's
  `POST /liton/v1/devices/code`, which answers `{"code", "expires_at",
  "link"}`, the link opening the UI at the address asked with the code.
  `POST /liton/v1/pair` with `{"code", "name"}` then answers
  `{"device": {"id", "name"}}` and sets the device's token as a cookie,
  `liton_token`, `HttpOnly` and `SameSite=Strict`, and `Secure` when a proxy
  says the request came over HTTPS (`X-Forwarded-Proto` or `Forwarded`). A
  page's scripts never see it. A client that isn't a browser asks
  `"token": true` and is given the token in the answer too, to send as
  `Authorization: Bearer <token>`. The daemon tries at most 10 pairings a
  minute, right or wrong, and answers `429` beyond.
- **Tokens.** A token is `<device id>.<secret>`, its secret 256 random bits
  as hex. The daemon keeps only its SHA-256, compares it in constant time,
  and never shows or logs a token.
- **Devices.** `GET /liton/v1/devices` lists the devices paired,
  `{"devices": [{"id", "name", "created_at", "seen_at", "current"}]}`, with
  times in milliseconds and the one asking `current`. `POST
  /liton/v1/devices/revoke` with `{"id"}` forgets one, whose token is refused
  from then on; revoking the device asking also clears its cookie.
- **When.** `LITON_AUTH` decides. `on`, the default, requires a paired
  device unless the daemon listens on loopback alone (`LITON_HOST` is
  `127.0.0.1`, `::1` or `localhost`) and the request carries none of a
  proxy's `Forwarded`, `X-Forwarded-*` or `X-Real-IP` headers, so
  `zig build run` works as it is. `required` always requires one, and is
  what a daemon behind a proxy on the same machine needs, should the proxy
  forward without those headers. `off` never does, for development only.
- **Federation.** A daemon is a client of its remotes like any other: pair it
  as the CLI does and give it the token with `LITON_PROVIDER_TOKENS`,
  comma-separated as `name=token`, which it sends as `Authorization: Bearer`.

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
  ],
  "setup": {
    "default_preset": "Developer",
    "default_theme": "Pastoral",
    "presets": [{ "name": "Developer", "snapshot": { "version": 6, "shell": "Workbench", "columns": […], "collapsed": [], "hidden": [], "theme": "" } }, …],
    "themes": [{ "name": "Pastoral", "scheme": "Dark", "accent": "#e8c872", … }, …]
  }
}
```

A capability is offered when a provider supplies it or a transformer derives
it. A client binds to capabilities, never to providers; it uses the manifest to
show what is missing and who could supply it.

`setup` holds what the daemon's setup (design.md, Setups) offers its
clients: its presets, each a layout as a client saves it, a snapshot, with a
name, and the one a client starts with; and its themes (`Setup.Theme`) and the
one a snapshot naming none shows. Its types are `Setup.Offered`, `Setup.Preset`
and `Setup.Theme` in the `setup` package. A daemon may leave it out, and a
client then offers presets and themes of its own.

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
| `Refused` | the provider said no, such as to liton's password, or a transformer's guard did, such as past a limit (Limits) |
| `Unsupported` | the daemon offers no such capability or version, or the capability has no calls (`workspace.git.v1`, `files.v1`) |
| `Overloaded` | try later (not used yet) |

The calls: `chat.v1`'s `ListSessions`, `WatchSession`, `SendMessage`,
`AnswerPermission`, `Cancel`, `Create`, `Rename`, `Archive`, `Configure`,
`ListHistory` and `Unarchive`;
`attention.v1`'s `ListItems`, `Settle`, `Snooze`, `Unsettle` and `Seen`;
`workspaces.v1`'s `ListWorkspaces`, `Create`, `Rename`, `Pin`, `Archive` and
`RenameProject`; `review.v1`'s `AddComment`, `EditComment`, `DeleteComment`,
`Resolve`, `Reopen` and `Send` (Review, below); `voice.v1`'s `Begin`,
`Finish` and `Cancel` (Audio, below); `rooms.v1`'s `ListRooms`, `Send`,
`React`, `Unreact`, `Join` and `Leave` (Rooms, below); `tickets.v1`'s
`ListTickets`, `GetTicket`, `Comment`, `SetStatus`, `SetAssignees`, `Link`
and `Unlink` (Tickets, below); `schedules.v1`'s `ListSchedules`, `Inspect`, `Create`, `Update`,
`Pause`, `Resume`, `RunOnce` and `Delete` (Schedules, below); `usage.v1`'s
`Refresh` (Usage, below); `limits.v1`'s `SetLimit` and `ClearLimit`
(Limits, below).

`{"SendMessage": {"session_id", "text"}}` prompts a session's agent. While
it works on a turn, the message interrupts it, or with `"while_running":
"Steer"` joins the turn, as Paseo's `activeTurnBehavior` `steer`; Paseo
sends `"Interrupt"` as `interrupt`, and the mock takes a steer as a word that
it goes on.

`{"Cancel": {"session_id"}}` stops a session's running turn, as an agent's
own stop button does, and is `Accepted` once the provider stopped it (from
Paseo, its `cancel_agent_request`). A session that isn't running is left as
it is, and accepted too.

`{"AnswerPermission": {"session_id", "request_id", "allowed"}}` answers a
timeline's `PermissionRequested`. A request is `{"request_id", "tool",
"description"}`, the tool and a line of what it would do, and, when its
provider tells more, its `body` as Markdown, such as a plan to approve, and
its own `choices`, each `{"id", "label", "allows", "style"}` with `style`
`Primary`, `Secondary` or `Danger`; an attention.v1 item's `permissions`
are such requests. Answering one with choices may name the choice taken,
`"choice": id`, with `allowed` as it `allows`; a choice the request doesn't
offer is `BadRequest`. The `PermissionAnswered` that follows names it too.
From Paseo, a plan's body is its request's `input.plan` and its choices its
`actions`, such as Claude's Reject, Implement and Implement with the mode it
planned from, the choice sent as `selectedActionId`. The mock asks for a
plan when a message mentions one.

Sessions, workspaces and projects are renamed, pinned and archived where
their provider keeps them:

```json
{ "capability": "chat.v1", "request": { "Rename": { "session_id": "fix-auth", "title": "Fix the login" } } }
{ "capability": "chat.v1", "request": { "Archive": { "session_id": "fix-auth" } } }
{ "capability": "workspaces.v1", "request": { "Rename": { "workspace_id": "main", "name": "Main" } } }
{ "capability": "workspaces.v1", "request": { "Pin": { "workspace_id": "main", "pinned": true } } }
{ "capability": "workspaces.v1", "request": { "Archive": { "workspace_id": "main" } } }
{ "capability": "workspaces.v1", "request": { "RenameProject": { "project_id": "liton", "name": "liton" } } }
{ "Ok": "Accepted" }
```

A session's model, mode and thinking level switch with `Configure`, each
left out to leave it as it is, the ids its agent's `models`, the session's
`modes` and the model's `thinking` levels name:

```json
{ "capability": "chat.v1", "request": { "Configure": { "session_id": "fix-auth", "model": "claude-opus-4", "mode": "plan", "thinking": "high" } } }
{ "Ok": "Accepted" }
```

Each answers `Accepted` once the provider took it, and the next listing
shows it: a new title or name, a workspace's `pinned`, and an archived
session or workspace left out. A name `""` gives back the one the provider
derives. A session has no pin of its own, as Paseo pins workspaces and not
agents: a client pins the workspace a session works in, a session without
one can't be pinned, and projects can be neither pinned nor archived. From
Paseo these are its `update_agent_request` (the agent's name),
`archive_agent_request`, `workspace.title.set.request`,
`workspace.pin.set.request`, `archive_workspace_request` and
`project.rename.request`, and `Configure` its `agent.config.apply.request`,
or with a Paseo that doesn't list `agentConfigApply` among its features,
its `set_agent_model_request`, `set_agent_mode_request` and
`set_agent_thinking_request` one after the other; the mock's agents offer
two models of three thinking levels each and a few modes, and refuse others;
Paseo can't unarchive a workspace over its protocol, and neither can liton.
The mock keeps its own changes.

`ListHistory` pages through every session a provider keeps, archived ones
too, the latest first: those whose title, agent or directory holds `search`
(`""` for all), `limit` at a time. An archived session tells when it was
`archived`. The answer's `next` is the cursor of the next page, left out
after the last; a client sends it back as `cursor`, opaque, which holds where
each provider goes on from, so the pages of several providers go on
together. `Unarchive` lists an archived session again:

```json
{ "capability": "chat.v1", "request": { "ListHistory": { "search": "login", "limit": 50 } } }
{ "Ok": { "History": { "sessions": [{ "id": "old-readme", "provider": "mock", "agent": "claude", "title": "Tidy the README", "status": "Idle", "archived": "2026-01-01T09:00:00.000Z" }], "next": "[{\"cursor\":\"50\",\"provider\":\"mock\"}]" } } }
{ "capability": "chat.v1", "request": { "Unarchive": { "session_id": "old-readme" } } }
{ "Ok": "Accepted" }
```

An archived session's timeline still follows (`timeline/<session_id>`), for
a client to show it read only. The mock keeps the sessions it archives, and
starts with one archived a day ago. From Paseo, a page is its
`fetch_agent_history_request` with archived agents included, sorted by
`updated_at`, its `pageInfo.nextCursor` the provider's cursor, and an
archived agent's `archivedAt` its `archived`; `Unarchive` is its
`refresh_agent_request`, which lists the agent again and reloads it. Paseo
lists `agentHistorySearch` among its features from 0.3.0, so each Paseo
liton speaks (0.9.2 to 0.15.3) has a history; one that doesn't list it adds
no sessions to a page.

`attention.v1` is an inbox: one item per session, those that need you first,
then the rest by when they last changed, the latest first. An item is
`{"session_id", "provider", "title", "agent", "state", "summary",
"permissions", "signature", "updated", "unread", "set_aside"}`: `state` is
`NeedsYou`, `Failed`, `Working`, `Done` or `Idle`; `summary` the agent's last
message; `updated` when the session last changed, as
`2026-01-01T09:00:00.000Z`, as its provider tells or else as the daemon saw
it; and `unread` whether it changed since it was seen, unless its agent is
working. `{"Seen": [{"session_id", "through"}]}` marks each session seen as
its item was `updated` (a client sends it when the user opens one); through
`""`, it is unread again. Sessions it doesn't list are ignored. `Settle` and
`Snooze` take the item's `signature` and set it aside until that changes.

`Create` starts an agent, and creates a workspace:

```json
{ "capability": "chat.v1", "request": { "Create": { "place": { "Workspace": "main" }, "agent": "claude", "model": "claude-opus-4", "mode": "plan", "thinking": "high", "prompt": "Find the TODOs" } } }
{ "Ok": { "Started": { "session_id": "claude-1767258000000" } } }
{ "capability": "workspaces.v1", "request": { "Create": { "project_id": "liton", "kind": "Worktree", "branch": "docs" } } }
{ "Ok": { "Created": { "workspace_id": "workspace-1" } } }
```

An agent starts in a workspace, `{"Workspace": id}`, of the provider that
lists it, or in a directory, `{"Directory": path}`, of the provider the call
names. Its `agent` is a kind its provider offers (the `agents` topic);
`model`, `mode` and `thinking` are left out for the provider's defaults, and
`prompt` is `""` for none. A
workspace is a `Checkout` of its project's directory, or a `Worktree` on a
new branch, `branch` or one the provider names when it is left out. Both
answer once the provider made it, before it lists it; a client shows it as
starting until a listing has it. The mock provider starts its scripted
agents in its workspaces and makes workspaces of its project.

From Paseo, an agent is its `agent.create.request`, in the workspace's
directory, with an id the daemon picks, its idempotency key too; a
workspace is its `workspace.create.request`, a `wks_` id
picked likewise, a checkout its `directory` source and a worktree its
`worktree` source branched off the project's directory. Each is one write
over a connection of its own, and the next poll lists what it made. The
`agents` it starts are its available providers
(`list_available_providers_request`), asked in the daemon's cycle at most
every minute while a poll watches them.

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
| `chat.v1` | `agents` | snapshot | `{"Agents": [{"provider", "agent", "models", "modes", "default_mode"}]}`, the kinds of agent each provider starts |
| `attention.v1` | `items` | snapshot | `{"Items": [Item]}`, what needs you first, then the latest |
| `workspaces.v1` | `list` | snapshot | `{"Listed": {"projects", "workspaces"}}` |
| `workspace.git.v1` | `changes/<context>/<scope>` | snapshot | `{"Changes": {"workspace", "status", "changes", "commits"}}` |
| `workspace.git.v1` | `file/<context>/<scope>/<path>` | snapshot | `{"File": {"path", "hunks"}}` |
| `files.v1` | `tree/<context>/<path>` | snapshot | `{"Tree": {"path", "listing"}}` |
| `files.v1` | `file/<context>/<path>` | snapshot | `{"Contents": {"path", "read"}}` |
| `voice.v1` | `status` | snapshot | `{"Status": {"stt": "Ready"}}`, or `"Loading"`, or `{"Down": reason}` |
| `review.v1` | `threads/<context>` | snapshot | `{"Threads": {"round", "next", "threads", "comments"}}` |
| `rooms.v1` | `rooms` | snapshot | `{"Rooms": [Room]}` |
| `rooms.v1` | `members/<room_id>` | snapshot | `{"Members": [Member]}` |
| `rooms.v1` | `messages/<room_id>` | append-only | `{"RoomEntry": {"sequence", "event"}}`: the room's top level and its threads' summaries |
| `rooms.v1` | `thread/<room_id>/<root>` | append-only | `{"RoomEntry": {"sequence", "event"}}`: a thread's replies |
| `tickets.v1` | `list` | snapshot | `{"Tickets": {"sources", "tickets"}}` |
| `tickets.v1` | `ticket/<ticket_id>` | snapshot | `{"Ticket": {"summary", "body", "comments"}}` |
| `tickets.v1` | `links` | snapshot | `{"Links": [{"session_id", "ticket_id", "inferred"}]}` |
| `schedules.v1` | `schedules` | snapshot | `{"Schedules": [Schedule]}` |
| `schedules.v1` | `runs/<schedule_id>` | snapshot | `{"Runs": [Run]}`, the latest first |
| `usage.v1` | `reports` | snapshot | `{"Reports": [Report]}`, each account's windows and balances |
| `limits.v1` | `status` | snapshot | `{"Limits": {"limits", "sessions", "weeks"}}`, how near each session and account is to its limit |

`importable` lists the sessions a provider keeps but doesn't run, such as a
sandboxed agent's, read only, each with the directory it worked in.

Besides its `id`, `provider`, `agent`, `title` and `status`, a session tells
what its provider knows, each field left out otherwise: `model`, the
`workspace` it works in (`{"directory", "id"}`, `id` left out when the
provider has no such workspace), the `branch` checked out there, and when its
running turn started (`running_since`) and it last changed (`updated`), as
times such as `2026-01-01T09:00:00.000Z`. Paseo's come from its agent list
(the model, `activeTurn.startedAt`, `updatedAt`, and the branch it placed the
agent on), so they cost no request of their own. `running_since` holds
while its agent works on a turn, waiting for you too, for a client to show
how long it has been working.

A session tells too, as far as its provider does, the `mode` it works in and
its `thinking` level, by their ids, the `modes` it can switch to, each
`{"id", "label"}`, and the `usage` of its last turn: `{"context_used",
"context_max", "input_tokens", "cached_input_tokens", "output_tokens",
"cost_usd"}`, each left out when not told, the tokens of its context window
used and at most, those read (of them cached) and written, and its cost in
US dollars. An `agents` kind tells the `models` it runs, each `{"id",
"label", "default", "context_max", "thinking"}` with its thinking levels
`{"id", "label", "default"}`, the `modes` it offers and its `default_mode`,
each left out when its provider doesn't tell. From Paseo, these are an
agent's `currentModeId`, `effectiveThinkingOptionId` (or its
`thinkingOptionId`), `availableModes` and `lastUsage`, and a provider's
models and modes in its `get_providers_snapshot_request`.

A session tells its `summary` too, once one is written: `{"goal", "done",
"now", "at"}`, a sentence each of what the session is for, what it has done
and what happens now, and when the turn it covers ended. It is a field of
the session rather than a topic of its own: the lists that title a session
by its goal already poll `sessions`, and a summary is three sentences.
The mock writes one after each turn from the turn itself. For Paseo's, the
daemon asks Paseo (0.15 or later, whose `server_info` lists the
`backgroundAgents` feature) for a background agent on the session's
smallest model, held to a JSON schema, 30 s after a turn ended, given what
happened since and the summary so far: one agent per summary, at most two
at a time, for the sessions whose timelines it fetches. Paseo archives the
agent once it answered, and neither Paseo's lists nor liton's show it.

Where a turn ends, a timeline has a `{"TurnEnded": {"started", "ended"}}`
after the turn's last event: once its agent finished, failed or was stopped,
and before a message that interrupts it, with when the turn started, left
out when the provider doesn't tell, and when it ended, for a client to fold
the turn and say how long it worked. From Paseo, a turn starts at its user
message, or its `activeTurn.startedAt`, and ends at the agent's `updatedAt`
once liton sees it stop, or at the turn's last entry in history fetched
after it ended. The mock times its own.

A `changes` or `file` context is a session id, or `workspace:<id>`
(`room:<id>` and `ticket:<id>` also name contexts, but no workspace, so their
events are `Unknown`); its scope
is `Uncommitted`, `AgainstBase` or `Commit:<sha>`. A `changes` event holds the
workspace (`Unknown` while it can't be read), its status, the scope's changed
files with their `fingerprint`, and the branch's commits. A `file` event holds
the hunks of one of those files, none when the scope has no such file; its path
is written with `%` as `%25` and `/` as `%2F`, so `src/Auth.roc` is
`file/fix-auth/Uncommitted/src%2FAuth.roc`.

`files.v1` reads the files of the same contexts' workspaces, a path relative
to the workspace's directory and escaped the same way, `.` for the directory
itself: `tree/fix-auth/.`, `file/workspace:main/src%2FAuth.roc`. A `tree`
event's `listing` is `{"Listed": [{"name", "kind", "size", "modified"}]}`,
each `kind` `File`, `Directory` or `Symlink` (Paseo follows links, and says
no `Symlink`). A `file` event's `read` is
`{"Text": {"text", "truncated", "size", "modified"}}`, the text's first
256 KiB at most (`truncated` if there is more), or `{"Binary": {"size",
"modified"}}`, or `"TooLarge"` (Paseo sends files up to 1 MiB). Either is
`"Unknown"` until the provider has read it, or when the context has no
workspace, and `{"Unreadable": "…"}` with why, such as when there is no such
path. Paseo answers both from its `file_explorer_request`, asked when a topic
is first polled and again only while polls watch it and what was read is 10 s
old, in the daemon's cycle of Paseo requests.

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

### Review

`review.v1` is a review of a context's code, as crit.md does it: comments
on lines of a file or a diff, and on the whole review, collected as drafts
and sent to the agent as one message. The daemon hosts it itself, as its
`review` provider, for every context while some provider offers `chat.v1`,
and keeps each context's review in SQLite; a provider outside the daemon
needn't offer it.

A context's `threads/<context>` topic is its review: the rounds sent
(`round`), its threads and the comments on the whole review. A thread is
anchored to lines, numbered from 1:

```json
{ "id": "t2", "outdated": false, "resolved": false,
  "anchor": { "path": "src/Auth.roc", "scope": "File", "side": "New", "start_line": 2, "end_line": 3, "quote": "…" },
  "comments": [{ "id": "c1", "author": "Me", "text": "Should this fall back to `/`?", "state": "Draft" }] }
```

An anchor's `scope` is `File`, the file as it is, or the diff of
`Uncommitted`, `AgainstBase` or `{"Commit": sha}` (workspace.git.v1's
scopes), on its `New` side, or its `Old` one for removed lines. `quote` is
the text of its lines. A comment is by `Me` or an `Agent`, and its `state`
is `Draft` or `{"Sent": round}`. Each poll of the topic finds a thread's
lines again in the file as the daemon has it (files.v1's `file/` topic,
asking nothing upstream): where they were, or else where the quote is,
the nearest if it is in several places, the thread moving there; a thread
whose quote is gone is `outdated`. A commit's lines and removed ones don't
move.

```json
{ "capability": "review.v1", "request": { "AddComment": { "context": "fix-auth", "place": { "Lines": { "path": "src/Auth.roc", "scope": "File", "side": "New", "start_line": 2, "end_line": 3, "quote": "…" } }, "author": "Me", "text": "Why?" } } }
{ "capability": "review.v1", "request": { "Send": { "context": "fix-auth", "session_id": "fix-auth" } } }
{ "Ok": { "Sent": { "round": 1 } } }
```

Each call names its context as topics do. `AddComment` adds a comment
under a thread (`{"Thread": id}`), on lines as a new thread (`{"Lines":
anchor}`) or on the whole review (`"Overall"`); a comment of yours is a
draft, an agent's is sent. `EditComment` and `DeleteComment` change a
draft alone (else `BadRequest`), and a thread goes with its last comment;
`Resolve` and `Reopen` a thread, which a new comment reopens. Each answers
`Accepted`, or `NotFound` for no such thread or comment. Ids are numbered
from the review's `next`, so a client applying a call to the review it has
shows what the daemon will (`Review.applied`). `Send` sends the drafts to
the session as one chat.v1 message and, once its provider took it, marks
them sent in the next round, answering `{"Sent": {"round"}}`; with no
drafts it is `BadRequest`, and a message the provider refuses leaves them
drafts, answering its error. The message is Markdown an agent can follow:

````markdown
# Review, round 1

2 comments. Each heading is a file and its lines, with the lines quoted; reply to each by its heading, then revise.

## src/Auth.roc:2-3

```roc
	redirect_to = request.came_from
	Session.start(redirect_to)
```

Should this fall back to `/`?

## Overall

Looks good otherwise.
````

A heading says where a diff's lines are, as in `src/Auth.roc:41
(the uncommitted diff, removed lines)`, and a thread's earlier comments
are quoted under its lines.

### Rooms

`rooms.v1` is rooms where people and agents talk: channels, forums, direct
conversations and announcements, from any NIP-29 relay or other source of
rooms ([research/buzz-provider.md](research/buzz-provider.md)). It names no
relay and no event kinds; ids are opaque strings, such as a group's UUID, an
event id and a public key.

```json
{ "id": "general", "provider": "mock", "name": "general", "kind": "Channel", "topic": "The team",
  "private": false, "archived": false, "joined": true, "unread": "Unknown", "links": [], "me": "you" }
{ "id": "scout", "provider": "mock", "name": "Scout", "kind": { "Agent": { "owner": "you" } }, "role": "Member", "presence": "Online" }
```

A room's `kind` is `Channel`, `Forum`, `Direct` or `Announce`; a forum's
top-level messages are its posts, each with a thread of replies. `unread` is
`{"Counted": {"messages", "mentions"}}` or `"Unknown"`, `links` the
repositories or projects it discusses as clone URLs, and `me` your member id
there, when the provider knows it. A member is a `Person` or an `Agent`, with
its `owner` only when its provider verified it; its `role` is `Owner`,
`Admin`, `Member` or `Guest`, and its `presence` `Online`, `Away`, `Offline`
or `Unknown`.

A room's `messages/<room_id>` and a thread's `thread/<room_id>/<root>` are
append-only, each entry a `sequence` and an `event`: `{"Posted": Message}`,
`{"Edited": {"id", "text"}}`, `{"Deleted": {"id"}}`, `{"Reacted": {"id",
"emoji", "by", "added"}}`, `{"Threaded": {"root", "replies", "last_reply",
"participants"}}`, a thread's summary, or `{"Typing": {"member", "place"}}`.
A message is `{"id", "room_id", "author", "text", "time", "place",
"mentions", "reactions", "edited", "deleted"}`, its `place` `"TopLevel"` or
`{"Reply": {"root", "parent"}}`, its reactions `[{"emoji", "by"}]`. A
room's topic holds its top-level messages, what happens to them, and each
thread's summary; a thread's, its replies and what happens to them. The
sequence is the provider's, in the order events arrived, so a client resumes
after it, and orders messages by their `time`.

```json
{ "capability": "rooms.v1", "request": { "Send": { "room_id": "general", "text": "@Scout thanks", "place": { "Reply": { "root": "m1", "parent": "m1" } }, "mentions": ["scout"] } } }
{ "Ok": { "Sent": { "message_id": "m9" } } }
{ "capability": "rooms.v1", "request": { "React": { "room_id": "general", "message_id": "m1", "emoji": "+" } } }
{ "Ok": "Accepted" }
```

`Send` posts a message in a room or replies in a thread, the first reply
starting it, and answers `Sent` with its id once the provider took it; a
client shows it sending until its `Posted` arrives. `React` and `Unreact`
add and take back your reaction, `Join` and `Leave` make you a member of a
room or no longer one. Each answers `Accepted`, or `Rejected` with why, such
as for a room you haven't joined; `ListRooms` answers `{"Rooms": [Room]}`.
The mock provider keeps three rooms, one a forum, where its agents type and
then answer when a message mentions them.

### Tickets

`tickets.v1` is the issues and tickets of the trackers providers reach,
GitHub Issues and Linear first, merged: every ticket names its `provider`,
its `source` (a repository's issues, a team's tickets) and its `url` back
there. A source tells whom it knows the user as, the people its tickets can
be assigned to, and the statuses they move between, each of a `kind`,
`Open`, `Started`, `Done` or `Canceled`, whatever the source calls it:

```json
{ "id": "thebrandonlucas/liton", "provider": "github", "name": "thebrandonlucas/liton", "url": "https://github.com/thebrandonlucas/liton",
  "me": { "id": "ada", "name": "Ada" }, "people": [{ "id": "ada", "name": "Ada" }],
  "statuses": [{ "id": "open", "name": "Open", "kind": "Open" }, { "id": "closed", "name": "Closed", "kind": "Done" }] }
```

The `list` topic holds the sources and their tickets, each a summary:

```json
{ "id": "liton#3", "provider": "github", "source": "thebrandonlucas/liton", "key": "#3", "title": "Track issues and tickets",
  "url": "https://github.com/thebrandonlucas/liton/issues/3", "status": { "id": "open", "name": "Open", "kind": "Open" },
  "assignees": [{ "id": "ada", "name": "Ada" }], "labels": ["enhancement"], "waiting_on": [], "updated": "2026-01-01T09:00:00.000Z" }
```

`key` is how its source names it (`#3`, `LIN-12`); `waiting_on` the ids of
the people it waits on, such as for an answer or a review; `branch`, left out
when the source suggests none, the branch to work on it in. A ticket's
`ticket/<ticket_id>` topic adds its `body` and its `comments`, oldest first,
each `{"id", "author", "body", "created"}`, bodies in Markdown.

```json
{ "capability": "tickets.v1", "request": { "ListTickets": { "sources": [], "kinds": ["Open", "Started"], "assignee": "Me", "label": "", "text": "login" } } }
{ "capability": "tickets.v1", "request": { "GetTicket": { "ticket_id": "liton#3" } } }
{ "capability": "tickets.v1", "request": { "Comment": { "ticket_id": "liton#3", "body": "On it." } } }
{ "capability": "tickets.v1", "request": { "SetStatus": { "ticket_id": "liton#3", "status_id": "closed" } } }
{ "capability": "tickets.v1", "request": { "SetAssignees": { "ticket_id": "liton#3", "person_ids": ["ada"] } } }
{ "capability": "tickets.v1", "request": { "Link": { "session_id": "fix-auth", "ticket_id": "liton#3" } } }
{ "capability": "tickets.v1", "request": { "Unlink": { "session_id": "fix-auth" } } }
```

`ListTickets` answers `{"Listed": {"sources", "tickets"}}`, the tickets that
pass its filter: of the `sources` named (all for none), of the `kinds` named
(any for none), assigned to `"Anyone"`, `"Me"`, `"Nobody"` or
`{"Person": id}`, with the `label` (`""` for any), and whose key or title has
`text`, ignoring case (`Tickets.matches`, which clients use on the `list`
topic too). `GetTicket` answers `{"Ticket": ticket}`. `Comment`, `SetStatus`
(one of its source's statuses) and `SetAssignees` (of its source's people,
none to unassign) change a ticket where its source keeps it and answer
`Accepted`; the next poll of its topics shows it. A status or person its
source hasn't is `BadRequest`, a ticket no provider has `NotFound`. Creating
tickets comes later.

`links` links each session to the ticket it works for: one linked by hand,
`Link`, or else the one its branch names (`"inferred": true`), the ticket
its source suggests the branch for, or else the first whose key is in it:
`lin-12-fix-login` for LIN-12, `3-tickets`, `issue-3` or `gh-3` for #3
(`Tickets.inferred`). `Unlink` unlinks a session by hand, so no branch links
it either; `Link` links it again. The daemon keeps the links set by hand,
whichever provider has the session or the ticket.

The mock provider offers it with scripted tickets of two sources, one
shaped as GitHub's issues and one as a Linear team's, and keeps the changes
calls make; its LIT-12 suggests the branch the mock's fix-auth session works
on, so that session links to it.

A provider's credentials are the daemon's alone, read from its environment
as Paseo's password is, and never reach a client.

### Schedules

`schedules.v1` runs prompts on a cadence, as Paseo's schedules do. A
schedule sends its `prompt` either to a session that exists, a heartbeat,
or to a new session each run:

```json
{ "id": "h1", "provider": "mock", "name": "Check CI", "prompt": "Is CI green?",
  "cadence": { "Every": 1800000 }, "target": { "Session": "fix-auth" },
  "status": "Active", "next_run": "2026-01-01T09:30:00.000Z", "last_run": "2026-01-01T09:00:00.000Z" }
{ "id": "n1", "provider": "mock", "name": "", "prompt": "Update the deps",
  "cadence": { "Cron": { "expression": "0 3 * * *", "timezone": "Europe/Berlin" } },
  "target": { "NewSession": { "place": { "Workspace": "main" }, "agent": "claude", "model": "opus", "isolation": "Worktree", "archive_on_finish": true } },
  "status": "Paused", "max_runs": 10, "expires": "2026-02-01T00:00:00.000Z" }
```

A cadence is `{"Every": ms}` or `{"Cron": {"expression", "timezone"}}`, the
time zone UTC when left out. A new session is started as chat.v1's `Create`
starts one, in a workspace or a directory, with the agent and, left out for
the defaults, its model, mode and thinking level; `isolation` `Local` works
in the place itself and `Worktree` in a worktree of its own, and
`archive_on_finish` archives it once its run is done. `status` is `Active`,
`Paused` or `Completed`, once it ran `max_runs` times or `expires` passed.
`next_run`, `last_run`, `max_runs` and `expires` are left out when there is
none.

A run is `{"id", "scheduled_for", "started", "ended", "status",
"session_id", "output", "error"}`, `status` `Running`, `Succeeded` or
`Failed`, `ended` left out while it runs, and the session it prompted, what
the agent answered and why it failed when its provider tells.

```json
{ "capability": "schedules.v1", "request": "ListSchedules" }
{ "Ok": { "Schedules": [ … ] } }
{ "capability": "schedules.v1", "request": { "Inspect": { "schedule_id": "h1" } } }
{ "Ok": { "Inspected": { "schedule": { … }, "runs": [ … ] } } }
{ "capability": "schedules.v1", "provider": "mock", "request": { "Create": { "name": "Check CI", "prompt": "Is CI green?", "cadence": { "Every": 1800000 }, "target": { "Session": "fix-auth" } } } }
{ "Ok": { "Created": { "schedule_id": "h2" } } }
{ "capability": "schedules.v1", "request": { "Update": { "schedule_id": "h1", "draft": { … } } } }
{ "capability": "schedules.v1", "request": { "Pause": { "schedule_id": "h1" } } }
{ "Ok": "Accepted" }
```

`Create` takes a draft, `{"name", "prompt", "cadence", "target",
"max_runs", "expires"}`, for the provider the call names, or the one that
offers schedules; a heartbeat's goes to its session's. `Update` changes a
schedule to a draft. `Pause` stops one until `Resume`, `RunOnce` runs it
now, besides its cadence, and `Delete` forgets it with its runs. Each
answers `Accepted` or `Rejected` with why, or an error, and the next poll of
`schedules` shows it.

From Paseo, each call is its `schedule/list`, `schedule/inspect`,
`schedule/create`, `schedule/update`, `schedule/pause`, `schedule/resume`,
`schedule/run-once` or `schedule/delete`, one write over a connection of
its own; a heartbeat is its `agent` target, a new session its `new-agent`
config in the directory of the place named, and a run's session its
`agentId`. The `schedules` topic is its `schedule/list`, and
`runs/<schedule_id>` its `schedule/inspect`, asked in the daemon's cycle
while polls watch them. Paseo lists no feature for schedules: each Paseo
liton speaks (0.9.2 to 0.15.3) has them, as Paseo has since well before
0.9. Paseo's schedules of a new session start it in a directory, so one
made in a workspace reads back as made in its directory.

The mock's schedules run by the daemon's clock, each due one run when a
poll or call finds it due, prompting its session or starting one in the
mock's workspaces; their cron expressions are of the minute and hour alone
(`0 9 * * *`, `*/15 * * * *`), in UTC, and their cadences every second at
most, and they don't archive the sessions they start. Its pure functions take the time, so its tests run them by a clock of
their own. A fresh mock has a schedule of a new session each night at 03:00.

### Hosts

`hosts.v1` lists and changes the daemons liton's daemon connects to: Paseo
daemons and other liton daemons (Providers outside the daemon). The daemon
offers it itself, as provider `hosts`, and keeps its hosts in its database:

```json
{ "name": "paseo", "kind": "Paseo", "target": "127.0.0.1:6767", "label": "",
  "enabled": true, "status": "Online", "version": "0.15.3",
  "last_online": "2026-01-01T09:00:00.000Z", "origin": "Environment" }
{ "name": "team", "kind": "Liton", "target": "https://liton.example", "label": "Team",
  "enabled": true, "status": { "Error": "the token was refused" }, "origin": "Added" }
```

A `Paseo` host's target is `host:port`, and it is reached over its WebSocket
with its password; a `Liton` host's is an `http://` or `https://` URL, reached
with the token it paired the daemon with (Authentication, Federation). A name
is 1 to 32 letters, digits, `-` and `_`, and names what the host offers:
`<name>/paseo` and `<name>/<id>` for a Paseo host's provider, sessions and
workspaces, and a liton host's as a remote's. The Paseo host `PASEO_*` sets
is called `paseo` and keeps bare ids, as before there were hosts. `status`
is `Connecting` until the daemon first hears from a host, then `Online`,
`Offline` when it can't be reached, `{"Error": why}` when it answers but
refuses, such as a wrong password, and `Disabled` while switched off.
`version` is what its server tells and `last_online` when it last answered,
each left out until known. `origin` is `Added` by a client, or
`Environment` or `Setup` for one the daemon's environment (`PASEO_*`,
`LITON_PROVIDERS` with `LITON_PROVIDER_TOKENS`) or setup sets again at each
start: such a host can be relabelled, disabled and enabled, but its target
and password are changed where they are set, and it can't be removed.

```json
{ "capability": "hosts.v1", "request": "ListHosts" }
{ "Ok": { "Hosts": [ … ] } }
{ "capability": "hosts.v1", "request": { "AddHost": { "name": "team", "kind": "Liton", "target": "https://liton.example", "label": "Team", "password": "…" } } }
{ "capability": "hosts.v1", "request": { "UpdateHost": { "name": "team", "label": "The team" } } }
{ "capability": "hosts.v1", "request": { "SetEnabled": { "name": "paseo", "enabled": false } } }
{ "capability": "hosts.v1", "request": { "RemoveHost": { "name": "team" } } }
{ "Ok": "Accepted" }
```

`AddHost`'s `password` is the Paseo password or the liton token, and is
written only: the daemon keeps it in its database, which it keeps readable by
its own user alone (mode 0600), and never answers or logs it. `UpdateHost`
changes the fields given and keeps the rest. Each change takes effect at
once, without a restart, and answers `Accepted` or `Rejected` with why; the
next poll of the topic `hosts` shows it.

Adding a host makes the daemon connect where it is told, from its own
machine and network, so `hosts.v1` answers only paired devices
(Authentication), and the daemon checks a target's form but not where it
leads: a paired device can point it at anything the daemon's machine
reaches. Relay pairing links and SSH tunnels to a Paseo daemon are later
work: today a Paseo host is reached directly.

### Usage

`usage.v1` tells what the accounts agents run under have used of their
plans, as their providers' usage reports tell: one report per account,
with its windows, such as a 5-hour and a weekly limit, and its balances.

```json
{ "provider": "paseo", "source": "claude", "account": "me@example.com", "plan": "Max", "status": "Available",
  "windows": [{ "id": "five_hour", "label": "Session", "short": "5h", "used_pct": 12.5, "resets_at": "2026-01-01T14:00:00.000Z" },
              { "id": "weekly", "label": "Weekly", "short": "wk", "used_pct": 41.0, "resets_at": "2026-01-05T09:00:00.000Z" }],
  "balances": [{ "id": "extra_usage", "label": "Extra usage", "used": 4.2, "limit": 50.0, "unit": "usd" }] }
{ "provider": "paseo", "source": "codex", "account": "", "plan": "", "status": { "Unavailable": "the login expired: run codex login" }, "windows": [], "balances": [] }
```

`source` is the kind of agent that runs under the account, as a session's
`agent` names it, so a client finds a session's account by its provider and
agent. A window's `id` is `weekly` for the week's; `short` is a label of a
few characters where space is tight, `""` for none; `used_pct` is a
percent, and it and `resets_at` are left out when not told. A balance's
`unit` is `usd`, `credits`, `requests` or `tokens`, and its `used`,
`remaining` and `limit` are left out when not told. `status` is
`Available`, or `{"Unavailable": why}`, such as a login that expired.

A provider asks its backend only while a poll follows `reports`, and not
more often than its backend allows. `Refresh` asks again at once:

```json
{ "capability": "usage.v1", "request": "Refresh" }
{ "Ok": "Accepted" }
```

From Paseo, the reports are its `usage.list_reports.request`'s, one
`usage.list_reports.update` per account (a source's `sourceId` its
`source`), from a Paseo whose `server_info` lists the `usageSources`
feature (0.11 and later), or else its `provider.usage.list.request`'s, from
one that lists `providerUsageList`; one that lists neither tells none. An
account whose report fails keeps the windows it last had, `Unavailable`
with why. The daemon asks in its cycle at most once a minute while a poll
follows `reports`, and at once after a `Refresh`.

The mock has an account for each kind of agent it starts, whose 5-hour and
weekly windows fill with each message its sessions are sent. Its sessions'
context grows with each message too, and a message `/compact` empties it,
as Claude's and Codex's own command does.

### Limits

`limits.v1` holds limits, each a percent: on how much of its context window
a session fills, and on how much of its weekly quota an account uses. The
`limits` transformer derives it from chat.v1's `sessions` and usage.v1's
`reports` (Transformers, below), and keeps the limits set:

```json
{ "capability": "limits.v1", "request": { "SetLimit": { "scope": { "Session": "fix-auth" }, "percent": 50 } } }
{ "capability": "limits.v1", "request": { "SetLimit": { "scope": "Week", "percent": 90 } } }
{ "capability": "limits.v1", "request": { "SetLimit": { "scope": "Default", "percent": 80 } } }
{ "capability": "limits.v1", "request": { "ClearLimit": { "scope": { "Session": "fix-auth" } } } }
{ "Ok": "Accepted" }
```

A limit's scope is one session's context window, `{"Session": id}`; every
account's weekly window, `Week`; or the context window of each session
without a limit of its own, `Default`. Setting a scope's limit replaces the
one it had, and a percent outside 1 to 100 is `Rejected` with why. The
topic `status` tells the limits set, and how near each is:

```json
{ "Limits": {
  "limits": [{ "scope": "Default", "percent": 80 }, { "scope": "Week", "percent": 90 }],
  "sessions": [{ "session_id": "fix-auth", "used_pct": 85, "limit_pct": 80, "state": "Over" }],
  "weeks": [{ "provider": "paseo", "source": "claude", "account": "me@example.com", "used_pct": 41, "limit_pct": 90, "state": "Ok", "resets_at": "2026-01-05T09:00:00.000Z" }] } }
```

A session is listed once its provider tells what its last turn used of its
context window (chat.v1's `usage`), `used_pct` rounded to a whole percent,
with the limit on it, its own or else the default, left out when there is
neither. An account is listed once its report tells its weekly window. Each
`state` is `Ok` below its limit or with none, `Near` within a tenth of it,
and `Over` at it or past it.

A limit set is enforced (Transformers, Guards). Past its context limit, a
session's `SendMessage`, a steer too, is `Refused` with
`"the session is over its context limit (85% of 80%): compact or start fresh"`,
except a message starting `/compact`, which makes room where its agent
compacts; past the weekly limit, a message to any session whose agent's
account it is, and a `Create` of an agent of its kind, are `Refused`, `"the
claude account is over its weekly limit (92% of 90%): raise the limit or
wait until it resets"`. A turn already running is never stopped: it ends as
it would. A session's account is the report of its provider whose `source`
is its agent. A provider's own limits, such as a hard cap within a turn or
when it compacts, are beyond liton's reach.

### Audio

`voice.v1` is dictation: speech to text ([research/voice.md](research/voice.md)).
Its audio travels outside JSON, in numbered chunks the daemon acknowledges, so
a dropped link loses nothing:

```
POST /liton/v1/audio/voice.v1/<utterance_id>/<seq>    body: audio/L16;rate=16000;channels=1
{"Ok": {"acked": 4}}
```

A chunk is raw 16 kHz 16-bit mono PCM, little-endian, best 1 s (32,000
bytes), at most 64 KiB (a bigger one is answered `413`). The client names the utterance, 1 to 64
letters, digits, `-` and `_`, and numbers its chunks from 0, at most 300 (5
minutes). The answer acks the highest seq the daemon holds with every one
before it, and leaves `acked` out until it holds chunk 0. A chunk sent again is
acked again and kept once, so a client resends until acked. Errors are a
call's: `BadRequest` for a bad address or an odd number of bytes,
`Unsupported` when the daemon offers no `voice.v1`.

```json
{ "capability": "voice.v1", "request": { "Begin": { "utterance_id": "u1", "purpose": "Dictation" } } }
{ "capability": "voice.v1", "request": { "Finish": { "utterance_id": "u1", "last_seq": 4 } } }
{ "capability": "voice.v1", "request": { "Cancel": { "utterance_id": "u1" } } }
```

`Begin` answers `Accepted` when the engine is up, else `Unavailable`, so a
client can say so before recording; its `purpose` is `Dictation` or
`{"Conversation": {"session_id"}}`. `Finish` transcribes chunks 0 to
`last_seq` once the daemon holds them all, `{"Transcript": {"text"}}`, or
answers `{"Missing": {"from_seq"}}`, the first it lacks, for the client to
send before finishing again. It keeps the transcript in place of the audio, so
a `Finish` asked again answers the same. An engine that can't be reached is
`Unavailable`. `Cancel` drops the audio held. The daemon keeps an utterance's
audio and transcript 10 minutes at most.

The daemon's `local-speech` provider offers `voice.v1` when `LITON_STT` names
a speech engine on its machine: `sherpa=ws://127.0.0.1:6006`,
sherpa-onnx's offline WebSocket server, or `whisper=http://127.0.0.1:8178`,
whisper.cpp's whisper-server (`rig/speech/` runs either).

## Providers outside the daemon

A provider outside the daemon speaks the protocol clients do: it serves
`/liton/v1` over HTTP (Wire, above), so it can be a small HTTP server in any
language, and a liton daemon is one already, which is how daemons federate.
The daemon is its client. `examples/provider-echo/` is the smallest one, in
Roc: chat.v1 for two scripted sessions.

The contract is the manifest's `protocol` and `providers` (a provider outside
the daemon may leave out the rest), `call` for the capabilities they list,
and `poll` for their topics. A daemon is given its providers outside it by its
setup's remotes (design.md, Setups), and by `LITON_PROVIDERS`, comma-separated,
whose remotes take the place of the setup's of the same name:

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
  (`chat.v1`, `workspaces.v1`, `workspace.git.v1`, `files.v1`). A remote's transformers
  are left out: the daemon's own derive from every provider (Transformers).
- **Calls.** A call to a remote's session (`SendMessage`, `WatchSession`,
  `AnswerPermission`, `Cancel`), or a `Create` in its workspace or project, is
  forwarded to it with the session, workspace or project and provider as it
  names them, and its answer returned as given, what it made named under its
  name. Lists (`ListSessions`,
  `ListWorkspaces`) merge the remotes' with the daemon's own.
- **Topics.** A topic of a remote's session or workspace
  (`timeline/team/fix-auth`, `changes/team/fix-auth/Uncommitted`,
  `tree/team/fix-auth/.`) follows the remote's own (`timeline/fix-auth`);
  `sessions`, `importable`, `agents` and `list` merge each remote's. A client's poll
  notes what it wants of each remote; the daemon asks a remote at most every
  `LITON_PROVIDERS_INTERVAL_MS` (default 1000), in one poll of all that
  clients watched of it within the last 10 s, after the cursors it has, and
  answers every client from what it kept. However many clients poll, a remote sees one poll per interval at most.
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
  state and the call's answer;
- `guards` and `guard`: the capabilities whose calls it may refuse, and from
  its inputs, its state and such a call's body, whether to let it through or
  why not.

The daemon hosts every transformer the same way, knowing none of them:

- **Offered.** A transformer is offered once the capabilities it uses are,
  by a provider or a transformer registered before it, so one may use
  another's output but never its own. The manifest lists it with the
  capabilities of the topics it uses.
- **Inputs.** A client's poll of a transformer's topic notes that the topics
  it `uses` are wanted, as a poll of those would, recursively for a
  transformer's output; the topics it `follows` are read from what the daemon
  keeps, with no work upstream. So a transformer adds little load beyond its
  `uses`: while a client watches attention, Paseo's cycle also fetches the
  timelines of its three most recently active sessions, and attention
  derives from what the daemon has of the rest.
- **Topics.** Each poll of an offered topic derives it again and answers it
  like any topic: a snapshot by its fingerprint, entries after their
  cursor. A topic it doesn't offer is `NotFound`.
- **Calls.** A call to the capability goes to `call`, whose answer is
  returned as given.
- **Guards.** Before the daemon answers a call of a capability an offered
  transformer `guards`, it asks the transformer's `guard`, and answers
  `Refused` with its reason should it refuse. A guard only refuses: it
  can't change or cancel what the call's provider already does.
- **State.** The daemon keeps each transformer's state, its own JSON, in
  SQLite, and stores a new one only if no other was stored since it read it;
  a call that loses is asked again. Attention's state is the settles and
  snoozes that still hold, the sessions seen, and when it saw a session
  change whose provider tells no `updated`.

A setup names the transformers the daemon hosts by id, and `LITON_TRANSFORMERS`
adds to them, comma-separated. There are three: `attention` and `limits`,
which liton's own setup names, and `needs-you`, attention's items that need
you as `needs-you.v1`, to show and check composition
(`LITON_TRANSFORMERS=needs-you`).
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

`liton pair`, run on the daemon's machine, prints a pairing code for a new
device (Authentication) and a link to pair a browser with it. It writes the
code in the daemon's database, at `LITON_DB` (default `liton.db`), as only
someone who can write it already holds the daemon's every secret. `liton
login <code>` pairs the CLI itself and keeps its token in
`$XDG_CONFIG_HOME/liton/tokens` (by default under `~/.config`), readable by
its owner alone, for the daemon at `LITON_URL`; `LITON_TOKEN` takes its
place when set.

`liton setup [path]` speaks no protocol: it runs a Litonfile (by default
`./Litonfile.roc`, or the one in a directory given) with `roc`, and writes the
setup it prints to `liton.setup.json` (design.md, Setups). It exits 1 when
the Litonfile fails or prints something other than a setup, and 2 when `roc`
can't be run.

## Agents

The daemon's MCP face offers each capability's calls as tools and its topics as
resources, so an agent works with the same capabilities as a person.

## Open questions

- Whether a capability's operations should be listed like its topics, so that
  an unknown one is `Unsupported` rather than `BadRequest`.

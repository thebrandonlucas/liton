# liton design

liton is a modular UI for working with AI agents, and the daemon behind it. You build your own interface from widgets. Each widget binds to a *capability*, which is any typed thing a connected backend advertises: chat, terminal, git, CI, tickets, rooms, review, environment. A backend can be Paseo, buzz, a raw ACP agent, GitHub, Radicle or a sandbox host. You save the result as a deterministic snapshot that anyone can load.

## Why

Every agent UI picks one kind of user. buzz picks non-programmers in rooms, but it can't see the code, CI, git history or worktrees. Paseo has the developer surface, but it's single-user and not social. liton doesn't pick. It ships sane presets, and you rebuild any of them from the same parts.

## Principles

- **Widgets bind to capabilities, never to providers.** This is what makes a layout portable across backends.
- **Deterministic.** A snapshot plus a pinned widget lockfile rebuilds the same UI.
- **Separate UI and daemon.** The UI only talks to a liton daemon.
- **Built in Roc.** The UI uses roc-signals. The daemon, provider plugins and tooling are Roc too.
- **No privileged organizing unit.** Workspace, room and ticket are all just contexts.
- **Instant.** A tap changes the UI in the same frame: the model applies what the user asked for at once and shows it pending until the daemon confirms, then settles or rolls back with a reason. No control waits on a round trip to show that it worked, and a spec asserts each change before answering its request.

## Architecture

liton is a protocol and a set of parts more than an app. Its narrow waist is the capability protocol ([protocol.md](protocol.md)): typed, versioned capabilities that sources provide and clients use. Everything above and below the waist is replaceable, the way anything can sit at either end of a Unix pipe.

```
 clients:   web UI (Workbench, Inbox, review, ...) · liton CLI · TUI · bots · agents over MCP
                         ▲  the same capabilities, the same wire  ▲
 ──────────── capability protocol: manifest · call · subscribe, versioned ────────────
                         ▼                                         ▼
 liton daemon (Roc)
   ├─ capability registry   what is offered, by whom, at which versions
   ├─ transformers          capabilities derived from others (attention from chat, ...)
   ├─ context graph         workspace ↔ agent ↔ room ↔ ticket ↔ PR ↔ sandbox
   └─ providers             in the daemon (Roc packages) or out of it (any language,
                            over the provider protocol): Paseo, ACP agents, GitHub,
                            Nostr rooms, other liton daemons ...
```

How the parts grow without the core growing:

- **Sources plug in from any language.** A provider compiled into the daemon is a pure Roc state machine; a provider outside it serves the same capability protocol clients use, `/liton/v1` over HTTP, with the daemon as its client, and later, once the daemon can hold connections, over stdio or a WebSocket, as language servers do. A remote liton daemon is a provider like any other, which is how daemons federate.
- **Transformers are pipes.** A transformer consumes capabilities and offers another: the inbox is attention derived from chat, a room's agent is chat routed by mentions. Like a provider compiled into the daemon, a transformer is pure: from the latest events of the topics it uses and its state, it derives its new state and its own topics, and the daemon hosts every one alike (protocol.md, Transformers). Users compose them in configuration.
- **Every client is equal.** The web UI is one client; the `liton` CLI speaks the same protocol as JSON lines, so `liton watch` piped into `jq` into `liton call` works, and agents use the same capabilities through an MCP face. Nothing is reachable only from the GUI.
- **A setup is a program that evaluates to data.** A `Litonfile.roc`, as a Kaifile is for kai, declares the daemons to connect, the transformers, presets, options and keys. It is pure Roc, so it does only what it declares; another setup imports it and overrides parts, pinned by a lockfile. A snapshot is an evaluated Litonfile.
- **Change is additive.** Capabilities version side by side and clients negotiate; a missing capability leaves a placeholder, not an error; parts describe themselves (capabilities, options, slots) so tools adapt to them. Each provider and transformer runs isolated, so one failing degrades only what depends on it.

What stays out: no plugin API into liton's internals (a part sees only the protocol), no untyped or Turing-complete configuration, and nothing in the core that could be a capability, a transformer or a client.

### Setups

A setup is what a daemon and its clients start from: the remotes to connect, the transformers to host, the presets and themes Settings offers, with the ones a new browser starts with. Its types are the `setup` package (`setup/Setup.roc`), which the daemon, the UI and the CLI share as they do `capabilities/`. Keys and options are still to come.

- **Declared in Roc.** A `Litonfile.roc` is an app on basic-cli whose `main!` prints a `Setup.Declared` as JSON; apart from that print it is pure, so it does only what it declares. liton's own setup is `setup/Default.roc`: no remotes, attention and limits, and the Developer, Inbox, Tiling, Chat, Rooms, Review and Board presets, Developer first. The `Litonfile.roc` at the root prints it as it is.
- **Built on another.** A setup imports another as a package and changes it with `Setup.with_remote`, `without_remote`, `with_transformer`, `without_transformer`, `with_preset`, `without_preset`, `with_default_preset`, their `_theme` counterparts and `merge`, which adds a second setup's remotes, presets and themes over the first's by name. `examples/litonfile-team/` builds on liton's. An app can't be imported, so what a setup shares is a module of a package, as `Default` is, with a Litonfile beside it that only prints it.
- **Evaluated once.** `liton setup [path]` runs a Litonfile with `roc`, reads back what it prints and writes it to `liton.setup.json`, its fields in order, so the same Litonfile gives the same bytes. That file is the setup evaluated.
- **Read by the daemon.** At start the daemon reads the setup `LITON_SETUP` names, by default `liton.setup.json` if there is one, and otherwise liton's own. The environment still overrides it: `LITON_PROVIDERS`'s remotes take the place of the setup's of the same name and add the rest, and `LITON_TRANSFORMERS` adds transformers. A setup that can't be read, or that names a transformer the daemon doesn't have or a malformed remote, stops the daemon with why.
- **Offered to clients.** The manifest's `setup` (protocol.md) holds the presets and themes and the defaults. The UI's preset picker shows them in place of liton's own, which it keeps while the daemon offers none, and a browser with no layout of its own starts with the default. A preset is a snapshot with a name, so loading one is loading a snapshot: the user changes it from there, and the browser keeps their layout. Settings offers the themes likewise.
- **Pinned.** A setup imported by URL is pinned by the hash in its URL, as every Roc package is, so a Litonfile's imports are its lockfile for now. A lockfile of its own waits on setups that pin what Roc doesn't, such as widget packages.

### Providers

A provider is a Roc package compiled into the daemon. It connects to a backend and implements one or more capabilities.

Providers are pure, following kai's plans pattern. A provider is a state machine: an event comes in, and the updated state plus a list of requested effects come out. The daemon host performs those effects. This makes every provider testable with recorded fixtures.

Examples:

- the Paseo provider talks to the running Paseo daemon API and supplies `chat`, `terminal` and `workspace.git`. liton does not run ptys itself: terminals come from providers and liton proxies their streams;
- the GitHub provider supplies `ci` (Actions) and `tickets`.

Several providers can serve the same capability. Their results are **merged**, and every item is tagged with its source.

### Capabilities

A capability is a versioned, typed interface made of queries, commands and event streams, for example `ci.v1: listRuns, watchRun, rerun`. Widgets compile against the interface. The v1 set:

| capability | purpose |
|---|---|
| `chat` | agent sessions as a rich timeline: messages, tool calls, diffs, permission prompts |
| `terminal` | pty in a workspace or sandbox |
| `workspace.git` | repos, worktrees, branches, history, diffs |
| `ci` | run graphs (jobs and steps), logs, rerun. GitHub Actions first |
| `tickets` | issues and tickets merged across providers (GitHub Issues, then Linear, then native tickets stored as Nostr events), each with its source and a URL back to it: listed and filtered, read with comments, commented on, moved between statuses and assignees, and linked to the sessions working on them, by branch name or by hand. Credentials stay in the daemon |
| `rooms` | people and agents together in channels, forums, direct conversations and announcements, with threads and reactions, from any NIP-29 relay or other source of rooms. Agents speak only when @mentioned |
| `review` | crit.md-style anchored line comments on diffs, files, agent output and docs. Comments are batched and submitted as one review, then the agent replies per thread and revises |
| `environment` | the sandbox's static definition (Nix closure, mounts, network policy, granted credentials), live resources, denials/audit, and lifecycle (create, snapshot, destroy) |
| `attention` | derived by the daemon from `chat` and later `tickets`, `review` and `ci`: an inbox of sessions, what needs you first and then the latest, each unread until you have seen it, with the responses it allows. Settle and snooze hide an item until something new happens |
| `schedules` | prompts that run on a cadence (every so long, or by cron in a time zone) in a session they keep prompting, a heartbeat, or in a new session each time, paused, resumed and run at once, with the runs each made, as Paseo's schedules |
| `discussions` | threaded comments anchored to any context (ticket, PR, file line, room, URL). `review` threads are discussions with a code anchor |
| `voice` | dictation into any composer, and a spoken conversation with an agent. Speech-to-text and text-to-speech come from a provider, private local models first (Paseo runs Parakeet, Kokoro and Silero VAD). Audio streams in numbered chunks the daemon acknowledges, so a dropped link loses nothing; talking over the agent interrupts it. Unlike Paseo, the agent's reply is spoken from its own text rather than a `speak` tool it must choose to call, voice turns on without reloading the session, and audio travels outside the JSON control channel |

### Context

Context is the entity a pane is pointed at: a workspace, agent, room, ticket, PR or sandbox. These form a graph. An agent runs *in* a workspace, *on* a sandbox, *for* a ticket, and is *discussed in* a room. The daemon resolves related entities.

The UI uses **linked focus with pinning**:
- there is one global selection signal;
- each pane derives what it needs from that selection (agent → workspace → branch → CI);
- any pane can be pinned to a fixed context.

Link groups (several independent selections) are a possible later extension.

A room can be attached to a context. Selecting the room then drives focus to that code.

### Identity and social

People and agents both have Nostr keypairs. Keys sign snapshots, room messages, native tickets and agent personas.

Hosting: each user runs a personal daemon, and a personal daemon can also join a shared team daemon. Rooms sync between daemons.

## UI

The UI is four layers. [docs/research/agent-ui-survey.md](research/agent-ui-survey.md) has the survey behind them, and [docs/research/surfaces.md](research/surfaces.md) the design of surfaces and parts.

- **Grid:** a layout is a CSS grid of tiles (`setup/Grid.roc`): column and row tracks with relative sizes, and tiles, each a rectangle of cells showing one or more panes as tabs. Splitting a tile cuts a track, closing one grows its neighbours over its cells, and tracks no tile needs apart merge again. A shell reads the grid:
  - *Workbench* (the Paseo one): its first column is the left drawer, its last the right drawer, and the tiles between the main area. On a narrow screen each drawer and the main area is a panel you swipe between or pick from a tab bar;
  - *Tiling*: free tiles, Hyprland-like.
- **Part:** one view bound to capabilities, in one role: a *navigator* sets the focus, a *view* shows what is focused, large, and an *inspector* shows details beside it. A part declares, as data apart from its code (`ui/Widgets.roc`), its role, the capabilities it needs, the slots it fits and its minimum width, the context kinds it sets and follows, which link the parts of a surface, its typed **options** from a closed set (Bool, Enum, Text, Int, CapabilityRef, ContextRef, ThemeToken) and its styleable **parts**.
- **Surface:** a preset grown up: a shell, the parts on its grid, their options and a default theme. Shipped ones are Developer (Paseo's workbench, the default), Inbox, Tiling, Chat, Rooms (Buzz), Review (crit.md) and Board (Linear); one is offered only while the daemon offers what its navigators and views need. A daemon's setup declares the presets its clients offer (Setups).
- **Escape hatches**, each a rung further from the presets: theme tokens; CSS per widget instance, targeting only its declared parts; a declarative widget loaded at runtime, which composes built-in pieces (list, card, text, badge, button, split, timeline) with capability queries and commands, and is safe to share in a snapshot because it does nothing beyond them; and a full Roc widget, compiled in.

Using it:

- **Settings, not chrome:** Settings is a page of its own, generated from parts' options: it picks the surface, swaps a part for another of the same role, sets options and theme, shows the host's providers and transformers, and holds the snapshot. The working UI shows no controls for adding or enabling widgets.
- **Editing:** dragging a pane by its tab or header previews the layout as if dropped and slides the tiles there, into a tile's tabs or beside it; dragging the line between tiles resizes them. Keys focus, move, swap, split, join and resize tiles too. Pointer positions during a drag and the slide are a JavaScript stopgap (`ui/ports.mjs`, a FIXME) until roc-signals offers them.
- **Commands and keys:** every action is a named command (`ui/Commands.roc`) that ⌘K's palette reaches, beside the places to go. A keymap (`ui/Keymap.roc`) binds keys or sequences to commands: ⌘ or Ctrl with a key, Linear's sequences such as `g` then `3` outside text fields, 1 to 9 to switch surfaces, and a surface's own keys, such as a Board's J and K. ? lists them. A terminal gets raw input.
- **Narrow screens:** each shell says how its slots collapse below a breakpoint. There is no separate mobile config.
- **Missing capability:** the pane stays in place as a placeholder. It names the missing capability and the providers that could supply it.
- **Theme:** a `Setup.Theme` record of tokens: light or dark, an accent and the color its focused edge fades to, text colors, the edges' strengths, the glass (tint, opacity, blur), the background (a gradient or a color), gap, radius, fonts and motion. The UI sets them as custom properties on its root, which the stylesheet alone uses, so widgets hold no theme code. A snapshot names its theme; setups declare and share themes as they do presets.

## Snapshot

A snapshot is a deterministic JSON file. It contains:
- named layouts, with pane widget types, pins and keybindings;
- the theme;
- a lockfile of pinned widget package versions;
- provider configs, with endpoints as variables and secrets referenced but never stored;
- agent definitions: persona, model, provider, tools and sandbox policy.

## Decisions

| topic | decision |
|---|---|
| plugin model | compile-time Roc packages |
| UI ↔ daemon | JSON-RPC over HTTP. Topics are polled (`POST /liton/v1/poll`, docs/protocol.md) until roc-signals has an SSE subscription; SSE streams then, possibly WebSocket later, behind the same capability types |
| daemon language | Roc, on roc-lang/basic-webserver (HTTP server, SSE, HTTP client). It has no WebSocket and no pty |
| first provider | Paseo, via its daemon API |
| first CI | GitHub Actions |
| identity | Nostr keypairs |
| native tickets | Nostr events |
| agents using liton | yes, through the daemon's MCP server |
| render targets | web first (roc-signals is browser-only). Native and TUI need other renderers |
| license | MIT / Apache-2.0 |
| hosting | local only for now: a personal daemon on the developer's machine |
| shared types | `capabilities/`: a platform-agnostic Roc package of types and JSON codecs, imported by the daemon and the UI |
| repo | monorepo |
| tooling | kai conventions: Kaifile dev env, `zig build <step>` tasks, pinned `.roc-version` (new compiler), AGENTS.md → docs/{rules,design,vision}.md, CHANGELOG.md; API docs from `##` comments by `roc docs` (`zig build docs`, served at /docs) |
| roc-signals | an SSE subscription effect, as an upstream PR to lukewilliamboswell/roc-signals. Until then the UI polls once a second |
| layout | a grid of tiles, not a tree: nested `Engine.each` contexts can't recurse, and a grid's rows and columns give the splits a tree would (docs/research/surfaces.md) |

## MVP

**Goal:** prove the capability → widget binding works.

- **Daemon:** runs on basic-webserver and hosts a **mock provider**. The mock provider plays back scripted agent sessions that include tool calls and a permission prompt, and it echoes what you send.
- **`chat.v1`:** `listSessions`, `watchSession` (polled, see Decisions), `sendMessage`, `answerPermission`.
- **UI:** web only (roc-signals). It has minimal tiling (columns of stacks or tabs) and a palette of widgets filtered by the capabilities the daemon advertises. One chat widget binds to `chat.v1`, and the session it shows follows linked focus. The snapshot is saved and loaded as JSON.
- **Widget declaration:** a Roc record `{ id, requires, context, config, view }`.
- **Tests:**
  - roc-signals `.scm` specs for the UI;
  - daemon contract tests (JSON-RPC and SSE fixtures);
  - end-to-end: browser → daemon → mock provider;
  - a snapshot round-trip that must produce identical JSON.
- **Dev:** a preview served from the developer's machine.

The order after the MVP: the Paseo provider (`chat`), then `workspace.git`, then `voice`, then `ci` (GitHub Actions), then `terminal` proxied through Paseo, then rooms, review and tickets.

## Open questions

- roc-signals: how a widget's view composes into the layout, and what an SSE subscription would look like as a `Req`/`Res` pair.
- basic-webserver: whether its no-background-work model can hold many long-lived SSE streams, and whether it can keep polling or pushing from upstream providers.
- Paseo's daemon API: how stable it is, how auth works, and how it maps onto `chat`, `terminal` and `workspace.git`.
- Capability schema format: Roc types as the source of truth, with JSON Schema generated for the wire?
- Room sync between daemons: Nostr relays or direct daemon-to-daemon.
- How the `environment` capability fits sandboxes where a remote daemon reads code and sandboxed agents make the changes.
- Snapshot format versioning and migrations.

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
- **Transformers are pipes.** A transformer consumes capabilities and offers another: the inbox is attention derived from chat, a room's agent is chat routed by mentions. Users compose them in configuration.
- **Every client is equal.** The web UI is one client; the `liton` CLI speaks the same protocol as JSON lines, so `liton watch` piped into `jq` into `liton call` works, and agents use the same capabilities through an MCP face. Nothing is reachable only from the GUI.
- **A setup is a program that evaluates to data.** A `Litonfile.roc`, as a Kaifile is for kai, declares the daemons to connect, the transformers, presets, options and keys. It is pure Roc, so it does only what it declares; another setup imports it and overrides parts, pinned by a lockfile. A snapshot is an evaluated Litonfile.
- **Change is additive.** Capabilities version side by side and clients negotiate; a missing capability leaves a placeholder, not an error; parts describe themselves (capabilities, options, slots) so tools adapt to them. Each provider and transformer runs isolated, so one failing degrades only what depends on it.

What stays out: no plugin API into liton's internals (a part sees only the protocol), no untyped or Turing-complete configuration, and nothing in the core that could be a capability, a transformer or a client.

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
| `tickets` | merged across providers, plus native tickets stored as Nostr events |
| `rooms` | people and agents together. Agents speak only when @mentioned |
| `review` | crit.md-style anchored line comments on diffs, files, agent output and docs. Comments are batched and submitted as one review, then the agent replies per thread and revises |
| `environment` | the sandbox's static definition (Nix closure, mounts, network policy, granted credentials), live resources, denials/audit, and lifecycle (create, snapshot, destroy) |
| `attention` | derived by the daemon from `chat` and later `tickets`, `review` and `ci`: what needs you, ranked (needs you > failed > working > done unseen > idle), each item with the responses it allows. Settle and snooze hide an item until something new happens |
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

The UI is four layers. [docs/research/agent-ui-survey.md](research/agent-ui-survey.md) has the survey behind them.

- **Shell:** an arrangement with named slots, laid over one deterministic tree of splits, tab groups and stacks with relative sizes. Shells constrain the tree rather than replace it:
  - *Workbench* (the Paseo one): a left drawer of contexts, a main area of tabs on splits, a right drawer of git, diff and files. On a narrow screen the three are panels you swipe between;
  - *Inbox*: the `attention` list beside the detail of the item it opens;
  - *Room*: people and agents together, with code panes following the room's focus;
  - *Tiling*: free splits and tabs, Hyprland-like.
- **Widget:** one view bound to capabilities. A widget declares, as data apart from its code, the capabilities it needs, the slots it fits and its minimum size, when it is relevant (a small expression over the focus), its typed **options** from a closed set (Bool, Enum, Text, Int, CapabilityRef, ContextRef, ThemeToken) and its styleable **parts**.
- **Preset:** a shell, the widgets in its slots, their options and a theme. A snapshot holds presets; shipped ones are Developer (Workbench, the default), Inbox and Team (Room).
- **Escape hatches**, each a rung further from the presets: theme tokens; CSS per widget instance, targeting only its declared parts; a declarative widget loaded at runtime, which composes built-in pieces (list, card, text, badge, button, split, timeline) with capability queries and commands, and is safe to share in a snapshot because it does nothing beyond them; and a full Roc widget, compiled in.

Using it:

- **Settings, not chrome:** a settings sidebar, generated from widgets' options, picks the preset, places widgets and sets options. The working UI shows no controls for adding or enabling widgets.
- **Editing:** dragging a widget snaps it to the slots it fits, previewing the drop and animating the move (waiting on pointer positions and view transitions in roc-signals); the leader-key palette, the snapshot file with live reload, and agents through the daemon's MCP server make the same tree edits.
- **Named layouts:** you switch between layouts such as `1:code`, `2:team` and `3:ops`.
- **Keys:** a modal leader key (tmux/i3-like) for layout operations. Panes keep their own keys, and a terminal gets raw input.
- **Narrow screens:** each shell says how its slots collapse below a breakpoint. There is no separate mobile config.
- **Missing capability:** the pane stays in place as a placeholder. It names the missing capability and the providers that could supply it.
- **Theme:** color, spacing and font tokens in light and dark. Themes are shareable like layouts.

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
| tooling | kai conventions: Kaifile dev env, `zig build <step>` tasks, pinned `.roc-version` (new compiler), AGENTS.md → docs/{rules,design,vision}.md, CHANGELOG.md |
| roc-signals | an SSE subscription effect, as an upstream PR to lukewilliamboswell/roc-signals. Until then the UI polls once a second |
| layout tree | shells constrain one tree. It is two levels deep for now (columns of stacks or tab groups), since nested `Engine.each` contexts can't recurse; deeper splits wait on a way to compose views recursively |

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

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

## Architecture

```
 UI (roc-signals: web, native, TUI)
   │  WebSocket + JSON-RPC (queries, commands, event streams)
 liton daemon (Roc)
   ├─ capability registry  (typed, versioned interfaces)
   ├─ context graph        (workspace ↔ agent ↔ room ↔ ticket ↔ PR ↔ sandbox)
   ├─ providers (compile-time Roc packages)
   │    paseo · github · nostr · sandbox · acp · radicle · buzz …
   └─ MCP server: the same capabilities exposed to agents
```

### Providers

A provider is a Roc package compiled into the daemon. It connects to a backend and implements one or more capabilities. Examples:

- the Paseo provider talks to the running Paseo daemon API and supplies `chat`, `terminal` and `workspace.git`;
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

- **Layout:** deterministic i3-style tiling. Every node is a split (horizontal or vertical), a tab group or a stack. Sizes are relative.
- **Named layouts:** you switch between layouts such as `1:code`, `2:team` and `3:ops`.
- **Editing:** the leader-key command palette, drag and drop, editing the snapshot file with live reload, or asking an agent to change it. All four produce the same tree edits.
- **Keys:** a modal leader key (tmux/i3-like) for layout operations. Panes keep their own keys, and a terminal gets raw input.
- **Mobile:** the same tree, collapsed into tabs or a stack below a width breakpoint. There is no separate mobile config.
- **Missing capability:** the pane stays in place as a placeholder. It names the missing capability and the providers that could supply it.
- **Theme:** color, spacing and font tokens in light and dark. Themes are shareable like layouts.
- **Default preset:** Developer, the Paseo-like one: workspace list | agent chat | terminal + diff + CI. Team (rooms-first) and Task (ticket-first) presets come later.

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
| UI ↔ daemon | WebSocket + JSON-RPC |
| daemon language | Roc |
| first provider | Paseo, via its daemon API |
| first CI | GitHub Actions |
| identity | Nostr keypairs |
| native tickets | Nostr events |
| agents using liton | yes, through the daemon's MCP server |
| render targets | web, native and TUI eventually |
| license | MIT / Apache-2.0 |
| hosting | local only for now: a personal daemon on the developer's machine |

## Open questions

- roc-signals: what renderers it has today, and how a widget package declares its view, its capability needs and its config.
- The Roc platform for the daemon: WebSocket server, processes, pty, and an HTTP client for providers.
- Paseo's daemon API: how stable it is, how auth works, and how it maps onto `chat`, `terminal` and `workspace.git`.
- Capability schema format: Roc types as the source of truth, with JSON Schema generated for the wire?
- Room sync between daemons: Nostr relays or direct daemon-to-daemon.
- How the `environment` capability fits tee8z's Voltage sandbox work.
- Snapshot format versioning and migrations.

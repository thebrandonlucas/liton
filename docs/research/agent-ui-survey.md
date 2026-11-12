# Survey: how tools let people work with agents

A survey made in November 2026 to shape liton's layout, widget and capability
model. It covers developer workbenches, team, attention and inbox tools,
tickets and discussions, and customizable widget architectures. Claims are from
public docs, or from Paseo 0.9.2's own code, unless marked *(inferred)*.

## Developer workbenches

**Paseo** (the north star). A daemon with web, desktop, mobile and CLI clients.
- Layout: a left sidebar of projects and workspaces (group by project or status,
  filter by host, project or label; pinned, labels, unread). The center is a
  workspace header over tabs on a split tree (agent, terminal, browser, file,
  diff, PR, subagent, plugin), with a focus mode that hides the sidebars. A right
  explorer has Changes (branch, file tree, unified or split diff, commit/PR/merge
  actions, commits), Files and PR (checks, approvals) tabs, remembering the tab
  per checkout. A command center jumps anywhere.
- Mobile: three anchored panels, agent list (-1), agent (0) and file explorer
  (+1), swiped between.
- Attention: a ranked state bucket, needs input > failed > running > attention >
  done (`protocol/dist/agent-state-bucket.js`), drives sidebar dots, the favicon
  and desktop notifications.
- Agent work: grouped tool badges, plan cards, permission and question forms, a
  context meter, a chat outline rail to jump between prompts, rewind
  (conversation, files or both), fork into a new tab or workspace, subagent
  tracks, dictation and voice.
- Customization: plugins add screens, panels and settings; no user-defined
  layouts or presets.

**Conductor**: a workspace (worktree) per task; chat tabs; a right sidebar with
diff, terminal and Run. Inline diff comments become composer attachments; diffs
per turn; a Checks tab gathers git, CI, deployments, comments and todos with a
suggested next action (create PR → fix checks → merge). conductor.build/docs

**Vibe Kanban**: issues spawn workspaces. Four toggleable panels: workspaces |
conversation | context (Changes, Logs, Preview) | details (git, terminal,
notes), saved per workspace. Batched inline comments with a count badge. Each
ticket has many attempts, each its own branch and worktree. The company shut
down in April 2026; the project continues as open source. vibekanban.com/docs

**Claude Code desktop**: draggable, resizable, pop-out panes (chat, diff,
browser, terminal, file, plan, tasks, subagent); a session rail; Normal,
Thinking and Verbose chat views; + beside a line to comment, Cmd-Enter to send
them all; a PR card with CI, auto-fix and merge when ready.
code.claude.com/docs/en/desktop

**Codex app**: threads in Local, Worktree or Cloud mode; a review pane scoped to
unstaged, staged, commit, branch or last turn; stage or revert by file or hunk.
developers.openai.com/codex/app

**Zed agent panel**: threads by project; "Review Changes" opens a multibuffer
to accept or reject hunks; notify when waiting or done; agent profiles choose
tools. zed.dev/docs/ai/agent-panel

**Also**: Claude Squad (TUI list with Preview and Diff tabs), Sculptor (agents in
containers, pairing mode syncs the branch locally), Cursor 2 (up to 8 parallel
agents on one prompt), Copilot Agent HQ (sessions on every GitHub page; steer
mid-run; "watch and fix" CI), OpenHands (chat plus Changes, VS Code, Terminal,
App and Browser tabs), Superset (a terminal per worktree; an MCP server lets
agents make workspaces). Crystal was deprecated in Feb 2026.

## Team, attention and inbox

**buzz** (Block): a Nostr-based Slack-like workspace. A short-lived channel per
feature holds the talk, code, CI, review and signed merge ("branch as room").
Agents are channel members with their own keypairs and a scoped, revocable
delegation from their owner; `buzz-acp` turns @mentions into ACP sessions and
answers only its owner by default. engineering.block.xyz/blog/buzz,
github.com/block/buzz

**herdr** (herdr.dev): a Rust terminal multiplexer that tracks agent state. Its
hierarchy is session → workspace (repo; worktrees as children) → tab → pane. A
sidebar shows each agent's state: working, blocked, done (finished while you
weren't looking; cleared when viewed), idle, unknown, read from the screen,
with `herdr agent explain` saying why. Blocked states roll up to the tab and
workspace. Toasts go in the app, to the terminal, to the OS or nowhere, and
skip what you're watching. A socket and CLI let agents drive it, and the desktop
app's layouts, mods and themes are files an agent may edit. herdr.dev/docs

**Omarchy** (DHH): agents are terminal programs in tmux layout presets, such as
`tdl` (editor | agent / terminal), `tdlm` (one per subdirectory) and `tsl N`
(a grid of N agents). The Omarchy skill lets agents restyle the system, with
`omarchy reinstall configs` as the undo. No triage of its own.
learn.omacom.io/2/the-omarchy-manual/107/ai

**crit** (crit.md): local review of agent output like a PR, for plans, diffs,
"story mode" (hunks grouped into chapters), live apps (comments on DOM
elements) and HTML. Line comments collect into one review sent to the agent,
which replies per thread; each round reloads, comments follow their lines,
there's a diff between rounds, and threads stay open until resolved. Plain
files, so any agent can take part. github.com/tomasz-tomczyk/crit

**Paseo inbox plugins** (likely what the user saw): wangfh5's *agent inbox*
(Needs attention, Working, Snoozed, Settled; settle and snooze are keyed to an
"attention signature" of pending permissions, error and last message, so only
something new revives an agent), 508-dev's *action inbox* (questions, tool
approvals, failures, ready to review; unread by content fingerprint; inline
approval rechecks the request first), and fullstackhouse's *PR inbox* (rules
over GitHub searches start one agent per PR; reviews post only on a click).
paseo.sh/plugins/category/orchestration

**LangChain Agent Inbox**: an inbox item is an interrupt whose agent declares
the allowed responses: accept, edit, respond or ignore.
github.com/langchain-ai/agent-inbox

**Mobile**: Happy (end-to-end encrypted; push on permission, error or done;
multiplayer steering) and Omnara (alerts only when input is needed).

**Devin in Slack**: the thread is the session, synced with the web app; silent
by default, with reactions as status (👀 working, ✅ PR landed, 💤 asleep);
stop or sleep mutes it until the next mention. docs.devin.ai/integrations/slack

## Tickets, ideas and discussions

**Linear**: an issue has a human `assignee` and an agent `delegate`. An
AgentSession per task is pending, active, awaiting input, error, complete or
stale, derived from typed activities (thought, action, elicitation, response,
error), and has a plan checklist and links such as the PR. Agents are summoned
by assignment, @mention or rules, and must acknowledge within 10 s. Linear Asks
files a request from Slack into Triage with a two-way synced thread.
linear.app/developers/agents

**GitHub**: assign Copilot to an issue; it takes a snapshot of the issue, reacts
👀, and works in one branch and one PR, where `@copilot` comments steer it.
Copilot can draft sub-issues. Discussions have no agent support.
docs.github.com/en/copilot

**Jira** (Rovo agents): agents can be assignees; a board column can assign an
agent to every card dragged into it.

**Radicle**: issues and patches are signed collaborative objects in git. An issue
closes as solved or other; each patch update is an immutable revision. No agent
support. radicle.dev/guides

**Nostr NIP-34 and NIP-22**: issue kind `1621`, status as separate events
(`1630` open, `1631` resolved, `1632` closed, `1633` draft; the latest from the
author or a maintainer wins), and NIP-22 kind `1111` comments threaded by root
and parent tags, which can also point at a URL. Clients include gitworkshop.dev
and ngit. nips.nostr.com/34, nips.nostr.com/22

**Spec to tasks**: Kiro's requirements → design → tasks.md with a "start task"
button per item; Spec Kit can turn tasks.md into GitHub issues.

## Customizable widget architectures

**Home Assistant dashboards** (the closest analogue): cards are YAML objects by
`type`, or custom elements. A card declares its grid size range and an options
schema from which the visual editor is generated, with YAML as the fallback.
Views are masonry, sidebar, panel or sections; sections support drag to move.
card-mod adds per-card CSS, but it targets internal DOM and breaks with
frontend releases. home-assistant.io/dashboards

**Grafana**: panels with typed options; dashboards are JSON with a
`schemaVersion` and migrate on load. Schema v2 has four layout kinds (grid,
auto grid, rows, tabs) in one document. grafana.com/docs

**VS Code**: static contribution points declare views, where they go and
`when` they're relevant (an expression over context keys), and settings, from
which the settings UI is generated. Extensions run with full permissions.

**Raycast**: a small closed set of preference types gives a polished generated
settings form. developers.raycast.com/information/manifest

**i3 and Hyprland**: i3 has one tree of splits, tabs and stacks; dragging edits
the same tree as the keyboard (drop in the center to join, near an edge to
split), and saved layouts use placeholders that "swallow" matching windows
later. Hyprland's dwindle picks the split side from the cursor's triangle in
the target. i3wm.org/docs/userguide.html

**Drag and drop on the web**: pointer events with pointer capture suit dragging
inside an app; HTML drag and drop suits things dragged in from outside. The
View Transitions API animates a DOM change, so panes slide into place.

**roc-signals today**: handlers can listen for pointer events, but only input,
change, focus and key events carry a payload, so a handler knows that the
pointer moved but not where. A drag-and-drop gap list for an upstream PR:
1. pointer payloads: id, type, buttons, modifiers, and the position relative to
   the handler's element and its size, so drop zones are pure arithmetic;
2. a `:capture` policy that calls `setPointerCapture` during the event;
3. pointermove coalesced to one turn per frame;
4. a `:stop` policy (stopPropagation), already a target in its design;
5. modifiers on key events;
6. a request that wraps the next DOM update in `document.startViewTransition`;
7. spec steps for pointer down, move and up.

## Patterns, and where each lands in liton

| Pattern | Seen in | liton |
|---|---|---|
| Three-column workbench: contexts, then agent, then git | Paseo, Conductor, Vibe Kanban, Claude | the Developer preset |
| Swipe between the same columns on a phone | Paseo | a shell's narrow-screen rule |
| A few ranked attention states (needs you, failed, working, done unseen, idle) | Paseo, herdr, inbox plugins, Linear, Zed | an `attention` capability derived from `chat` |
| Settle and snooze until something new happens | inbox plugins | `attention` commands, stored per user |
| An inbox item carries its allowed responses | LangChain, Linear, Asks, Happy | the `attention` item schema |
| Inbox list beside a detail view | inbox plugins, herdr mobile | the Inbox preset |
| State rolls up from agent to workspace to host | herdr, Paseo | an option on list widgets |
| Notifications that skip what you're watching | herdr, Happy, Paseo | a notifier on `attention` |
| Diff with scopes, hunk staging | Codex, Paseo, Zed | a diff widget on `workspace.git` |
| Batched, anchored, multi-round review | crit, Vibe Kanban, Conductor, Claude, Codex | `review` |
| Merge readiness: CI, threads, conflicts, next action | Conductor, Claude, Copilot | a widget over `ci`, `review` and `workspace.git` |
| Send to chat from anywhere (terminal, element, file, review) | Conductor, Paseo, Cursor | an attachment type on `chat` |
| Rewind, fork, steer while running | Paseo, Conductor, Copilot | `chat` commands |
| Mention to summon; silent by default; the thread is the session | buzz, Devin, Linear, Copilot | `rooms`, with a room thread ↔ session edge |
| Agent as delegate, a human as owner; runs per ticket | Linear, GitHub, Jira, Vibe Kanban | `tickets` |
| Status as its own event, latest wins | NIP-34, Radicle | native tickets on Nostr |
| Layout presets as one word | Omarchy, herdr | presets |
| Agents edit the UI, with undo | herdr, Omarchy | snapshot editing through the daemon's MCP server |
| Live preview of a dev server | Vibe Kanban, Claude, Cursor, OpenHands | a new `preview` capability |
| Scheduled and rule-driven agents | Paseo, Codex, Copilot, PR inbox | a new `automations` capability |

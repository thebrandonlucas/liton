# Changelog

All notable changes to liton are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and liton follows [Semantic Versioning](https://semver.org/) (before 1.0, a minor or patch release may still break things).

## [Unreleased]

### Added

- `zig build run` serves liton at http://127.0.0.1:8095 (`LITON_HOST` and `LITON_PORT` change it): a row of panes, each a widget bound to a capability the daemon advertises. Add panes from the toolbar; a widget whose capability no provider supplies shows what it needs.
- Sessions, Chat and Capabilities widgets on chat.v1. Chat panes follow the session selected in Sessions, or are pinned to one; they show the agent's messages, tool calls and results, and ask you to allow or deny what it requests.
- Snapshot shows the layout as JSON to copy or to paste and load; the browser keeps the last layout.
- A mock provider of scripted agents, so all of this works without a real backend.
- Panes tile in columns. Move a pane into the column beside it with its ← and → buttons (past the edge it gets a column of its own), switch a column between a stack and tabs, and make it narrower or wider. The Developer preset gives the chat a column twice as wide.
- On a phone, a strip of tabs above the panes picks the one column shown.
- Sessions waiting for you to allow or deny something stand out: Sessions shows each status as a badge, and a chat pane showing such a session says "waiting for you" in its header, next to the session's title.
- A tool call shows as one card with its result: the tool and whether it is running, done or failed, its input, and its output, with all but the first 4 lines folded away until you open them.
- Connect a running Paseo daemon by setting `PASEO_PASSWORD` (and `PASEO_HOST` or `PASEO_PORT` if it isn't at 127.0.0.1:6767): its agents show up as sessions, and you can chat with them and allow or deny what they ask. `LITON_MOCK=off` hides the scripted mock agents.

### Changed

- Sending a message or allowing or denying a request shows at once: the message appears as "Sending…" and the prompt gives way to "Allowing…" or "Denying…" until the agent has it. A message the agent did not take stays, with why and a Retry button; an answer it did not take brings the prompt back. A chat pane says "Loading…" until its session's timeline arrives.
- Layouts saved by an earlier version, in the browser or as a snapshot, load as one column per pane.

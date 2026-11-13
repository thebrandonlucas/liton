# Changelog

All notable changes to liton are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and liton follows [Semantic Versioning](https://semver.org/) (before 1.0, a minor or patch release may still break things).

## [Unreleased]

### Added

- `zig build run` serves liton at http://127.0.0.1:8095 (`LITON_HOST` and `LITON_PORT` change it): panes, each a widget bound to a capability the daemon advertises. Add panes from Settings; a widget whose capability no provider supplies shows what it needs.
- Sessions, Chat and Capabilities widgets on chat.v1. Chat panes follow the session selected in Sessions, or are pinned to one; they show the agent's messages, tool calls and results, and ask you to allow or deny what it requests.
- Settings, behind the toolbar's one button, picks the Developer or Tiling preset, adds widgets (marking those no provider supports yet) and shows the layout as a snapshot, JSON to copy or to paste and load; the browser keeps the last layout. The working UI shows no buttons for adding widgets.
- The Developer preset, the default, is a workbench like Paseo's: Sessions in a left drawer, the chat in the middle, and Changes (once a provider supplies `workspace.git`) and Capabilities as tabs in a right drawer. The ◧ and ◨ buttons in the toolbar hide and show the drawers. On a phone the three are full-width panels you swipe between, opening on the chat; the strip above them shows which is in view and jumps to one when tapped.
- A mock provider of scripted agents, so all of this works without a real backend.
- The Tiling preset tiles panes in columns. Move a pane into the column beside it with its ← and → buttons (past the edge it gets a column of its own), switch a column between a stack and tabs, and make it narrower or wider. It gives the chat a column twice as wide.
- In Tiling on a phone, a strip of tabs above the panes picks the one column shown.
- Sessions waiting for you to allow or deny something stand out: Sessions shows each status as a badge, and a chat pane showing such a session says "waiting for you" in its header, next to the session's title.
- A tool call shows as one card with its result: the tool and whether it is running, done or failed, its input, and its output, with all but the first 4 lines folded away until you open them.
- Connect a running Paseo daemon by setting `PASEO_PASSWORD` (and `PASEO_HOST` or `PASEO_PORT` if it isn't at 127.0.0.1:6767): its agents show up as sessions, and you can chat with them and allow or deny what they ask. `LITON_MOCK=off` hides the scripted mock agents.
- An Inbox widget lists every session by what it needs from you: Needs you, then Failed, Done and Working, each with its agent, state and the agent's last message. Click one to open it in the chat (on a phone, it jumps to the chat). Allow or deny what a session asks for right in the inbox.
- Settle an inbox item, or snooze it for an hour, to move it to Later until something new happens in that session or the hour is up. It moves at once, and comes back with why if the daemon refuses.
- The Inbox preset, in Settings: a workbench with the Inbox in the left drawer, the chat in the middle, and the right drawer hidden. Paseo agents that finished since you last looked show as done.
- The browser tab's title counts the sessions that need you, as in "(2) liton", and so does the Inbox's tab.
- Settings is now a sidebar that slides over the panes from the right (the whole screen on a phone). Besides the preset, it lists each drawer's or column's panes: move a pane to another drawer it fits, remove it, or open it to set its options. Adding a widget offers only those that fit. Every change shows at once.
- Per-pane options, set in Settings: a chat shows tool output in full, folded or not at all, and shows or hides status lines; Sessions shows or hides each session's agent; the Inbox can list idle sessions too, and snoozes for an hour, a day or a week (its Snooze button says which).
- The right drawer's Changes shows the focused session's branch, how far it is ahead of and behind its base, and its changed files, uncommitted or against the base; click a file to see its diff, unified or split (an option in Settings), and open the branch's commits to see each one's files. It works with Paseo or any provider of `workspace.git`, and asks for updates every 2 seconds only while it is on screen.

### Changed

- Sending a message or allowing or denying a request shows at once: the message appears as "Sending…" and the prompt gives way to "Allowing…" or "Denying…" until the agent has it. A message the agent did not take stays, with why and a Retry button; an answer it did not take brings the prompt back. A chat pane says "Loading…" until its session's timeline arrives.
- The browser remembers which drawers you hid, and each pane's options. Layouts saved before options existed load with every option at its default.
- Paseo works over its WebSocket alone, with Paseo 0.9 through 0.15: agents of every provider show up, not only Claude, Codex and OpenCode, and a password Paseo refuses shows as a failed "Paseo refused the password in PASEO_PASSWORD" session, retried every minute.
- Layouts saved by an earlier version, in the browser or as a snapshot, load in Tiling, the oldest with one column per pane. One that is just the old default of Sessions, Chat and Capabilities loads as the new Developer workbench instead.

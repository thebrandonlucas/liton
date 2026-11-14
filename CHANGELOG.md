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
- The right drawer's Changes shows the focused session's branch, how far it is ahead of and behind its base, and its changed files, uncommitted or against the base; click a file to see its diff, unified or split (an option in Settings), and open the branch's commits to see each one's files. It works with Paseo or any provider of `workspace.git`, and asks for updates only while it is on screen.
- Connect a Paseo daemon reached through a relay with pairing, end-to-end encrypted: run `bridges/paseo-relay/bridge.mjs` with the pairing offer and the password, and point `PASEO_HOST` and `PASEO_PORT` at it. It keeps one connection to the daemon however many liton daemons use it.
- The daemon offers its capabilities through one documented protocol at `/liton/v1` (docs/protocol.md): `GET /liton/v1/manifest` lists its providers, transformers and topics, `POST /liton/v1/call` calls chat.v1, attention.v1 and workspaces.v1 with one set of error codes, and `POST /liton/v1/poll` follows sessions, timelines, the inbox, workspaces and git changes at once, each from a cursor.
- `/liton/v1/poll` follows the hunks of a changed file (`workspace.git.v1`'s `file/<context>/<scope>/<path>` topic) and the sessions Paseo's providers keep that Paseo doesn't run (`chat.v1`'s `importable` topic).
- The `liton` command line (`zig build cli`) speaks that protocol and prints JSON lines: `liton manifest`, `liton call chat.v1 '"ListSessions"'` (the request also from stdin; exits 1 on an error), and `liton watch chat.v1 timeline/<session>`, one event per line until interrupted, for piping into `jq` and other tools. It finds the daemon at `LITON_URL` (default http://127.0.0.1:8095).
- Add providers outside the daemon, written in any language, or other liton daemons, with `LITON_PROVIDERS="name=http://host:port,…"`: each serves the same `/liton/v1` protocol, and its sessions, workspaces and timelines show up beside your own, named `<name>/…`, and take your messages. The daemon asks each at most once a second (`LITON_PROVIDERS_INTERVAL_MS`) however many clients poll, and one that is down leaves out only its own sessions until it answers again. `examples/provider-echo/` is the smallest such provider.
- Describe a setup in a `Litonfile.roc`, a Roc program: the providers outside the daemon to connect, the transformers it runs and the presets Settings offers. It builds on liton's own, or on another setup it imports, and changes what it needs (`examples/litonfile-team/`). `liton setup [path]` evaluates it to `liton.setup.json`, the same file every time.
- The daemon starts from `liton.setup.json`, or the setup `LITON_SETUP` names: its remotes and transformers, with `LITON_PROVIDERS` and `LITON_TRANSFORMERS` added over them, and its presets in the manifest.
- Settings offers the presets of the daemon's setup, and a browser with no layout of its own starts with the setup's default. Change it from there, and the browser keeps your layout. A preset shows as picked while the layout is still its own.
- A new look: each pane is a glass tile with rounded corners, evenly spaced over a dark gradient. The pane you last clicked in has a bright edge and the others dim a little. Panes and Settings fade in when they open, and buttons respond as you hover and press them. All motion stops when your system asks for reduced motion.
- A bar across the top replaces the toolbar. On the left are your setup's presets as numbered workspaces, with the one shown marked: click one, or press Alt+1 to Alt+9 outside a text box. On the right are how many sessions need you, how many agents are running, the drawer buttons and Settings. Escape closes Settings.
- Themes: Pastoral, gold on a dark gradient (the default); Hypr, with an edge that fades from teal to violet; and Plain, light and calm with nothing moving. Pick one in Settings. The browser keeps it with your layout, and a snapshot carries it. A setup declares its themes and its default one (`Setup.with_theme`, `with_default_theme`), and Settings offers the daemon's.
- A Glass switch in Settings turns off the blur behind the tiles, which saves work on a slow device's graphics card.
- Stop a running agent with chat.v1's `Cancel` call (`liton call chat.v1 '{"Cancel":{"session_id":"…"}}'`), for Paseo's agents, the mock's and those of providers outside the daemon.
- Each chat.v1 session tells, when its provider knows, the model it runs, the directory and workspace it works in, its branch, and when its running turn started and it last changed, for an agent's header to show.
- Browse the files of a session's or workspace's directory with the new `files.v1` capability: `/liton/v1/poll` follows a directory's entries (`tree/<context>/<path>`) and a file's text, up to its first 256 KiB, or whether it is binary or too large (`file/<context>/<path>`). Paseo, the mock and providers outside the daemon offer it; the daemon asks Paseo for a directory or file when it is first watched and again at most every 10 s while it is.
- The daemon transcribes dictation on your own machine: set `LITON_STT=sherpa=ws://127.0.0.1:6006` (Parakeet in sherpa-onnx) or `LITON_STT=whisper=http://127.0.0.1:8178` (whisper.cpp), which `rig/speech/` runs, and it offers `voice.v1`. Clients post the audio in acknowledged 1 s chunks to `/liton/v1/audio/voice.v1/<utterance>/<seq>`, so a dropped link loses nothing, and `Finish` answers the transcript (docs/protocol.md, Audio).

### Changed

- Sending a message or allowing or denying a request shows at once: the message appears as "Sending…" and the prompt gives way to "Allowing…" or "Denying…" until the agent has it. A message the agent did not take stays, with why and a Retry button; an answer it did not take brings the prompt back. A chat pane says "Loading…" until its session's timeline arrives.
- The browser remembers which drawers you hid, and each pane's options. Layouts saved before options existed load with every option at its default.
- Paseo works over its WebSocket alone, with Paseo 0.9 through 0.15: agents of every provider show up, not only Claude, Codex and OpenCode, and a password Paseo refuses shows as a failed "Paseo refused the password in PASEO_PASSWORD" session, retried every minute.
- Layouts saved by an earlier version, in the browser or as a snapshot, load in Tiling, the oldest with one column per pane. One that is just the old default of Sessions, Chat and Capabilities loads as the new Developer workbench instead.
- Switching sessions, picking a file or a scope in Changes, or showing a pane brings what it shows faster: the UI asks the daemon at once instead of on its next once-a-second update, which now asks for everything on screen in one request.
- Without an Inbox in the layout, the browser tab's title counts the sessions waiting for you.
- Layouts saved before themes existed show the setup's default theme. A `liton.setup.json` evaluated before then still loads, and offers no themes of its own.

### Fixed

- The page title's count of what needs you now leaves out sessions you settled or snoozed, and is the same whatever the layout, not only when an Inbox pane is open.
- Sending a message by pressing Enter clears the message box, so the next message no longer starts with the text of the last.

### Removed

- **Breaking:** the daemon's `/api` endpoints are gone; use `/liton/v1` (docs/protocol.md).

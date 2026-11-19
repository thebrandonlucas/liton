# Surfaces: parts linked by focus, in designed layouts

A proposal, for review before any code. It replaces "a widget in a slot, added with +" as the way liton's UI is built.

The reference screenshots and analyses are kept outside the repo, in `liton-ui-research/<product>/` (`paseo`, `crit`, `buzz`, `linear`), each with SOURCES.md and ANALYSIS.md.

## The problem

Each widget does its own navigation inside one pane:
- Rooms swaps between the room list, a room and a thread.
- Tickets swaps between the list and a ticket.
- Review sits inside Changes and Files.

So a room can't fill the middle while its list stays on the left. A ticket can't be a board. A file can't be reviewed in the centre while the tree stays beside it.

The products we're matching split the same work across the screen:

| Product | Left | Centre | Right |
|---|---|---|---|
| Paseo | workspaces | the workspace's tabs: agents, terminal, browser, diff, PR | Files, Changes, PR |
| Buzz | rooms | the conversation | the thread |
| crit.md | changed files | every file's diff, with comments | all comment threads |
| Linear | teams and views | list or board | issue properties |

Choosing on the left changes the centre, and choosing in the centre changes the right.

Two further problems:
- Only sessions drive focus today.
- The layout is stuck in columns, because it is two levels deep and roc-signals' `Engine.each` can't recurse.

## Concepts

| Term | What it is | Examples |
|---|---|---|
| **Capability** | data and its protocol | `chat.v1`, `rooms.v1`, `tickets.v1` |
| **Part** | one view of one kind of context, in one role | the room list, a conversation, a thread |
| **Surface** | a designed composition of parts, with its layout, focus links, keys and default theme | Developer (Paseo), Rooms (Buzz), Review (crit.md), Board (Linear) |

### The roles of a part

- **Navigator:** chooses what's in focus. It sets focus and follows nothing, or only its scope.
- **View:** shows the focused thing, large. It follows focus and can set a sub-focus, such as a thread or a line.
- **Inspector:** details beside the view. It follows the focus or the sub-focus.
- **Overlay:** the command palette, pickers and dialogs. They act on the focus.

A part declares which context kinds it sets and which it follows, beside what it already declares (capabilities, options, minimum size). That declaration is what lets parts "work as a set": a room list and a conversation fit together because one sets `room` and the other follows `room`. A conversation that follows `session`, `room` or `thread` works in any surface.

### Surfaces are presets, grown up

A surface is a snapshot with a name, as presets are today, plus:
- the areas of its layout (see Layout);
- which parts may go in which area;
- how its parts' focus links;
- its keymap;
- its default theme.

You open a surface and then change it: swap a part for another of the same role, set options, resize. You don't build one from an empty "+" list.

Which surfaces and parts are offered depends on the capabilities your daemon advertises. Without `rooms.v1` there's no Rooms surface, and no room parts to swap in.

### More than one surface

**For now:** each window shows one surface, and the operating system does the switching. macOS Spaces, Hyprland workspaces and a second monitor each hold a liton window, for example Developer on one and Rooms on another. This doesn't fight the user's tiling manager or swipe gestures.

**Later, as an option:** an in-app list of surfaces you switch between with keys or a swipe, for a single window or a phone. It needs a name other than "workspace", which already means a Paseo or git workspace (`workspaces.v1`). "Deck" or "screens" are candidates.

## Focus

The design already calls for one selection signal from which each pane derives what it needs. This proposal makes that selection typed and deeper.

```
Focus : {
  context : [Workspace(Str), Session(Str), Room(Str), Ticket(Str), Pr(Str), …],
  sub : [None, Thread(Str), Message(Str), File(Str), Lines({ path, start, end }), ReviewThread(Str), Tab(Str)],
}
```

**How it flows:**
- A navigator sets `context`.
- A view follows `context` and sets `sub`.
- An inspector follows either.
- The daemon's context graph fills in related contexts: a session's workspace, a room's linked workspace, a ticket's linked session. So a Changes inspector can follow a room through the workspace linked to it.

**Pinning** stays per part, as the design says.

**Link groups** are separate focus signals, so two surfaces, or two halves of one, don't steer each other. A window has one group per surface. A group inside a surface is a later option.

**History:** back and forward move through focus. Buzz and Linear both have them.

## Layout: a grid, not a tree

The layout tree is limited to two levels because a view can't contain itself. A flat grid avoids that.

- **Areas:** a surface's layout is a CSS grid with named areas, such as `nav | view | inspector`, or `nav | view-a view-b | inspector` when split.
- **Tiles:** each tile occupies one area. Splitting a tile adds rows or columns to the grid and gives the halves to areas.
- **Tabs:** a tile can hold several parts as tabs.
- **Data:** the whole layout is a flat list of areas and tiles, so a snapshot stays plain data.
- **Drag:**
  - **Preview:** the dropped-into layout is just another grid, so the UI swaps the grid while you hold a tile, which shows the drop live.
  - **Snapping:** zones are the edges of a tile (split there) and its middle (join its tabs).
  - **Animation:** the browser's View Transitions animate every tile to its new place.
  - **Ghost:** a picture of the tile follows the pointer.
- **Keys:** the same operations as named commands: focus, move or swap left, right, up or down; split; join as tabs; resize; close.
- **Phone:** the areas become panels you swipe between, as now.

**A JavaScript stopgap.** roc-signals has neither pointer positions during a drag nor view transitions. A small module in `ui/ports.mjs` will feed pointer positions to Roc and call `document.startViewTransition` around the layout change. It will carry a FIXME naming what roc-signals needs, and both gaps go to the roc-issues repo as drafts.

## Commands, keys and the palette

Every action is a named command: focus a part, open a surface, toggle the inspector, send, resolve a thread, change a ticket's status, and so on.

**Commands take arguments from focus.** "Set status" acts on the focused ticket, and "Resolve" on the focused thread.

**One list, many entry points:**
- Keys, the ⌘K palette, the ⋮ menus, drag and the MCP face all run the same commands.
- A keymap is data in the snapshot, so it can be rebound.
- `⇧?` lists what's bound.

**Defaults follow each reference within its surface:**
- crit's `j/k`, `]/[`, `c`, `⇧F`;
- Linear's `C`, `S`, `A`, `⌘B`;
- Paseo's `⌘1–9` for workspaces, `⌘T`/`⌘W` for tabs, `⌘⇧`+arrows for panes.

Keys global to liton: `⌘K`, `⌘,`, `⌘B`/`⌘E` for the drawers, and `⇧?`.

**The browser's limits:**
- A browser tab can't take `⌘W`, `⌘T`, `⌘N` or `⌘1–9`. In a tab, liton uses Ctrl+Alt or a leader key for those. An installed app window gets them.
- `⌘⇧`+arrows selects text in text fields, so pane movement doesn't apply while one has focus.

## Shared parts

Built once and used by every surface:

- **Conversation:** a timeline, a composer and threads, with renderers for each kind of item.
  - Chat adds tool cards, permission prompts, plans and subagents.
  - Rooms adds reactions, @mentions, agent badges and typing.
  - Today chat and rooms each have their own, so this means merging them.
- **List rows:** title, a second line, status, age and a ⋮ menu. Used by sessions, workspaces, rooms, tickets and files.
- **Properties:** label and value rows, editable. Used by tickets, PRs and sessions.
- **States:** empty, loading, error with retry, and read-only. One look, one wording style. Buzz's ui.md is a good model for the wording.
- **Diff with inline threads:** used by Changes, Review and PRs.

## The surfaces

### Developer, modelled on Paseo (the pilot)

```
nav: workspaces             view: workspace                         inspector
 New workspace · History    header: title · project · ▷ run ·        Files · Changes · PR
 Pinned                       editor · Commit ▾ (View/Merge PR) · ±  (+ Tickets)
 Needs input / Ready to     tabs: agent · agent · terminal · diff ·  follows the
 review / Working / Done      file · PR · +                          workspace,
 (rows: title, host, PR,    pane: conversation (chat) + chips +      not the tab
  CI, ±)                      composer
```

- **Focus:**
  - The navigator sets `Workspace`.
  - The view's tabs are the workspace's sessions and opened views, and the tab sets `sub = Tab`.
  - The inspector follows the workspace.
- **Theme:** a flat neutral theme as the default (`#1b1d1c` / `#1E2120` / `#272A29`, 14px system font, no glass), with Pastoral kept as an option.
- **What it needs that liton lacks:**
  - the workspace view with tabs;
  - the header's git actions, which need commit, push and PR commands (`workspace.git` or a forge capability);
  - terminals;
  - the palette;
  - the Pinned section, and rows with a second line;
  - the composer's chips (tasks, subagents, ±).

Paseo's ANALYSIS.md, sections 4 and 5, lists every gap in order.

### Rooms, modelled on Buzz

```
nav: rooms                  view: room                    inspector: thread
 Search · Inbox · Agents    header: #name · members ·     root, replies,
 sections, channels, DMs      ⋯                           own composer
 unread dot, @ count        timeline (bottom-anchored),   (overlays when
                              thread summaries, working   narrow)
                              badge, reactions
                            typing · agents working · composer
```

- **Focus:** the navigator sets `Room`, and the view sets `sub = Thread`, which the inspector follows. A room's linked workspace drives Changes and Files when they're present.
- **Theme:** a light theme with a soft backdrop, close to Buzz and to Pastoral's character.

### Review, modelled on crit.md

```
nav: changed files          view: review                       inspector: threads
 Review conversation (n)    top: against main · n/m viewed ·    all threads,
 commits ▾ · scope ▾          ]/[ n comments · Finish (round n) filter, jump
 tree: status, ±, comment   every file as a card: diff,
  badges, viewed              threads inline, composer under
                              the picked lines
```

- **Focus:** the navigator sets `File`, synced both ways with the view's scroll. The view sets `Lines` and `ReviewThread`, which the inspector follows. Finish sends the round, and the round's state follows the agent's chat.
- **New capability work:** the diff between rounds. `review.v1` already numbers rounds.

### Board, modelled on a simplified Linear

```
nav: scopes                 view: tickets (List | Board ⌘B)    inspector: properties
 Mine · Unassigned ·        grouped by status kind, counts     status · assignees ·
 sources · saved filters    rows/cards: key, title, labels,      labels · source link ·
                              assignee, linked session           linked sessions (open)
```

- **Focus:** the navigator sets a scope, which stays local to the surface. The view sets `Ticket`, which the inspector follows. Opening a ticket in the view replaces the list, with `1 / n` stepping.
- **What it leaves out:** cycles, projects, roadmaps and sub-issues. Priority could become an optional field of `tickets.v1`.

## Settings, as a page

Settings becomes its own surface, laid out as a list with a detail beside it, like Paseo's:

- **App:** appearance, keys, voice, notifications, about.
- **Host,** for each daemon: providers, capabilities, projects, connections, usage.
- **Surface:** the open surface's parts, their options and its theme. This is today's settings sheet, cut down to what belongs to a surface.

You don't add widgets here any more. You open surfaces, then swap parts in place while editing the layout. The "+ widget" list goes away.

## How we build and check the look

1. **References first:** before building a surface, its screenshots and ANALYSIS.md are agreed. That's done for the four above.
2. **Screenshot checks:** each surface gets screenshots taken by the e2e harness against the mock daemon, at 1440×900 and 390×844, light and dark. They're kept as review artefacts beside the references, so a person can compare them. They are not pixel-diffed in CI.
3. **Briefs describe the surface, not a widget:** the parts, the focus links, the keys and the states, with the reference images attached.

## What has to change in roc-signals or the platform

Each item below will be filed as a draft in the roc-issues repo; a JavaScript stopgap with a FIXME goes in until it's available.

- **Pointer positions during a drag**, for the ghost and live preview.
- **View transitions:** a way to animate layout changes.
- **Global key handling with chords and a leader key.** Liton already uses `Engine.on_document_key`; check whether chords need more.
- **A recursive view** (an `each` that contains itself). The grid layout no longer needs it, but trees of threads and folders do.

## Plan

Each step is its own small stack of PRs, with screenshots checked against the references.

1. **Foundations:**
   - typed `Focus` with set/follow declarations for parts;
   - the grid layout, migrating snapshots from columns;
   - commands and a keymap, with the ⌘K palette;
   - the drag stopgap.
2. **Developer (Paseo) surface:**
   - the workspace view with tabs, the header and the inspector following the workspace;
   - the flat theme;
   - the Pinned section and second-line rows;
   - the palette.
3. **Shared conversation part:** chat and rooms on one timeline and composer.
4. **Rooms surface.**
5. **Review surface:** split out of Changes, with the diff between rounds.
6. **Board surface.**
7. **Settings page;** the "+ widget" list goes away.
8. **Later:** an in-app list of surfaces, link groups inside a surface, terminals, a PR inspector and hosts.

## Decisions (2026-11-18)

The developer accepted these recommendations:

1. **Names:** part, surface, navigator, view, inspector and overlay. When the later list of surfaces arrives, it's a **deck**.
2. **Layout:** a grid, not a tree. Arbitrary nesting goes away.
3. **Keys that ⌘ can't take in a browser tab:** use sequences outside text fields, in Linear's style. For example, `g` then `3` goes to workspace 3; `t` then `n` opens a new tab.
   - ⌘K reaches everything, everywhere.
   - An installed app window also gets the real ⌘ bindings.
   - Ctrl+Alt is avoided, because Linux desktops use Ctrl+Alt with the arrows to switch workspaces.
4. **Developer's tabs are per workspace,** as in Paseo.
5. **"Ready to review"** (done, unread, with changes) becomes an attention rank, so the navigator groups by Needs input, Ready to review, Working and Done.

## Questions for review

1. Are the names right: part, surface, navigator, view, inspector? And for the later list of surfaces: deck, screens, or something else?
2. Grid instead of tree: is giving up arbitrary nesting acceptable, since splits become rows and columns of the grid?
3. Keys in a browser tab: Ctrl+Alt, or a leader key such as Space in non-text focus, for what ⌘ can't take?
4. Should the Developer surface's tabs be per workspace, as Paseo's are, or per session as today?
5. Should "Ready to review" ("done, unread, with changes") become an attention rank, so the navigator can group by Paseo's four statuses?

# UX sweep: liton's Developer preset against Paseo's web client

November 2026. Paseo 0.15.3's web client and liton's Developer preset (Pastoral
theme) ran side by side on one throwaway Paseo daemon with its mock provider:
three git repos (`api-server`, `web-app`, `infra`) with uncommitted changes and
six agents (one running, one waiting on a plan approval, one failed, three
finished with read, grep, edit and bash calls). Both were shot at 1440×900 and
390×844, dark, in the same states. The screenshots (`paseo-*.png`,
`liton-*.png`) are not committed. Paseo's sizes and tokens come from its web
bundle. The mock's bash commands are short, so long ones were checked in the
bundle, not on screen.

The goal: look and feel like Paseo first, then better, never worse.

## By area

### Sidebar

**Paseo.** A flat `#141716` panel, 320px (200 to 600, resizable), no glass.
- **Top:** 28px icon rows for New workspace, History, Search and Schedules.
- **List:** "Workspaces" has a display menu (group by Project, Status or
  Labels; sort; title as branch or title). Project rows are 36px: a lettered
  tile, a muted name, and `+` and `⋮` on hover. Under each is **one 36px row
  per workspace**: a 20px status slot, the title at 76% opacity, and "3m"
  trailing, which turns into `⋮` on hover. Right-click opens the same menu.
  Agents are tabs, not rows.
- **Footer:** 28px icons, with **settings at the bottom right**.
- **Selection:** a lighter surface (`#272A29`, radius 8), with no border.

**liton.**
- **Rows:** three kinds.
  - Projects: uppercase mono, a count and `+`.
  - Workspaces: a dot, `main`, `+14 −3` in gold or the word "changed", and `+`.
  - Sessions, indented: a dot, the title and a status word.
- **Selection:** a gold tint plus a 2px gold inset bar.
- **Dots:** six looks (pulsing green, gold with a halo, red, faded green, grey,
  pulsing gold). Unread adds a gold ring and a bold title.
- **Menus:** the pane's `⋯` holds only "Close pane", and rows have none.

**Change.**
- Make each session one row: status, title, time since its last activity. The
  branch goes on a muted meta line, shown only off the default branch.
- Show a workspace row only when it holds two or more sessions.
- Write project headers in sentence case, with `+` and `⋮` on hover.
- Show selection as a neutral surface.
- Give every row and project a `⋮`, also on right-click.

### Chat timeline

**Paseo.**
- Content is centred at 820px max, with 15/21 text.
- The user bubble is `#434645`, radius 16 except a 2px top-right corner. Its
  time, copy and rewind show on hover.
- While a turn runs, a 14px six-dot loader and a live "3m 46s" sit at the
  bottom, with no word.
- When it ends, the default "Collapse turns" folds **the whole turn, text
  included**, into one muted line ("Edited 1 file, ran 3 commands, read 1 file,
  and searched 3 times"). The final message follows, then a copy, fork,
  "Worked for 9s" footer.
- A plan approval is a card: the plan, "How would you like to proceed?", and
  **Implement** and **Dismiss** buttons.

**liton.**
- The timeline is full width, with 14px text and a gold-tinted user bubble.
- Finished turns keep every tool card.
- A mono "running" line shows while a turn runs.
- A plan request shows "asks to MockPlanApproval: Plan" and a bottom bar,
  "Allow MockPlanApproval: Plan? Allow / Deny". **The plan isn't shown**, and
  the provider's choices become a generic Allow and Deny.

**Change.**
- Centre the timeline at 820px, with 15px text and a neutral bubble.
- Add the loader with an elapsed timer, and a footer when a turn ends.
- Collapse finished turns, as an option.
- Show permissions as cards: the body as Markdown, with the provider's own
  choices.

### Tool calls

**Paseo.** Each call is one 32px line with no box:
- a 12px icon (terminal, eye, pencil, search), a muted verb ("Shell", "Read")
  and the target on one ellipsised line;
- on hover the icon becomes a chevron that opens the output in a mono box;
- runs of calls group behind one wrench line;
- a running label shimmers (a gradient sweep of 1 to 2.3s), and an error shows
  a red triangle.

**liton.** Each call is a boxed card: a gold name, a "done" pill, the input,
five lines of output and "N more lines". A diff's headers print as text. The
cards dominate finished turns.

**Change.** Use Paseo's muted, grouped one-liners: an icon, a verb and the
target, with the output behind a chevron. Running shimmers, failed is red, and
done says nothing.

### Header and status

**Paseo.**
- **Header (36px):** the panel-left toggle, the branch and project, and `⋯`.
  On the right, a **Commit** split button and the panel-right toggle.
- **Tab row (36px):** agent tabs (an icon with a status dot, the title and a
  hover `×`), `+` (Agent / Terminal / Diff / providers), and the pane's `⋯`
  (Split right / Split down).
- **Stop** is the composer's send button turned into a red square.

**liton.** A dot, the title, a coloured word ("running", "waiting for you"), a
red-bordered **Stop** text button, `⋯`, and a meta line: `mock ·
thirty-minute-stream · api-server · main`.

**Change.**
- Replace the word with the status icon, keeping the word as its tooltip and
  accessible name.
- Move Stop into the composer.
- Keep the meta line: it says more than Paseo's header.

### Composer

**Paseo.** A rounded box: radius 16, a 1px border, `#1E2120`, at the timeline's
width. The placeholder is "Message the agent, tag @files, or use /commands and
/skills". A bottom row holds attach `+`, model, thinking and mode chips, a
context meter, a mic, voice, and a 28px round send button (arrow up), which
becomes a red square stop while a turn runs.

**liton.** A flat full-width textarea and a gold "Send" text button, with the mic
beside it.

**Change.** Use the same box, with a model chip (read-only at first), the voice
controls in the bottom row, and one send/stop icon button.

### Right drawer

**Paseo.** 320px, with icon tabs Files and Changes. Changes holds:
- a branch switcher, an "All changes" dropdown, and `+14 −3` in green and red;
- a **folder tree** with per-folder and per-file stats and status squares;
- Commits, folded.

A file opens a **Diff tab in the main area** (split or unified; whitespace and
wrap toggles).

**liton.**
- Text tabs, and an always-shown "Review: no drafts / Send review" panel.
- "0 ahead / 0 behind main", plus Uncommitted and Against base buttons.
- A flat file list with "modified" and "added" pills.
- The diff sits inside the 380px drawer and scrolls sideways.

**Change.**
- Show a folder tree with status icons and green and red stats.
- Make the scope a dropdown.
- Show the review panel only when a draft exists.
- Add "Open diff in main area", the default on a wide screen.

### Panes, tabs and menus

**Paseo.**
- Sidebars **toggle**: Ctrl+B, Ctrl+E, or Ctrl+. for both.
- Tabs have a hover `×` and a context menu: resume command, id, rename, close
  to the left, right or others, reload, close.
- Tabs drag between panes, splits come from a menu, and handles resize.

**liton.**
- `⋯` offers "following …", Pin, "← Move left / Move right →", and **Close
  pane** in red.
- A drawer widget, once closed, comes back only through Settings → Add a
  widget.
- A column of two panes grows "Stack/Tabs" and "+/−" buttons.

**Change.**
- Workbench slots hide and show; "Close pane" leaves their menus.
- Tabs get icons and a hover `×`.
- Stack/Tabs moves into `⋯` and Settings, and a column-edge handle replaces
  +/−.
- Moves name a target ("Move to right drawer").
- Drag and drop waits on pointer positions in roc-signals.

### Top bar and settings

**Paseo.** There is no top bar. Settings is the footer gear (Ctrl+,), which opens
a page with a section rail.

**liton.** A 2.4rem glass bar: the brand, a notice, "1 need you", "1
running", ◧ ◨ and "⚙ Settings".

**Change.** Drop the bar from the Workbench on a wide screen:
- the drawer toggles go to the chat header's two ends;
- the needs-you count goes into the Workspaces header and the page title,
  `(1) liton`;
- Settings becomes a 28px gear at the sidebar's bottom left;
- notices become toasts.

Tiling, which has no sidebar, keeps a slim bar. The brand lives in the title and
the favicon.

### Phone

**Paseo.** Below 600px:
- a 56px header: a hamburger, the branch and project, a tab switcher, `⋯` and
  the explorer toggle;
- drawers slide over a backdrop, from a swipe that starts within 32px of the
  edge;
- menus are bottom sheets, and rows are 44px;
- there is no bottom bar.

**liton.** A 60px brand bar, the panel, and a bottom tab bar (Workspaces, Chat,
Changes · Files) with swipes between panels.

**Change.**
- Drop the brand bar, which frees about 60px, and put the gear in the
  Workspaces header.
- **Keep the tab bar**: it is in thumb reach and carries the needs-you badge,
  which makes it better than Paseo's.
- Make Send and Stop 44px icons.

### Motion and feedback

**Paseo** animates only work in progress:
- a 12px ring turning once per 900ms;
- the loader and live timer while a turn runs;
- the tool shimmer;
- hover reveals for `+`, `⋮` and `×`.

**liton** pulses dots and slides panes, menus and sheets in.

**Change.**
- Replace the pulse with the ring.
- Add the loader, timer and shimmer.
- Keep everything under `--motion` and reduced motion.

### Icons

Paseo uses lucide (ISC licence) everywhere, at 12 to 16px on desktop and 18 to
24px on a phone. liton uses glyphs (◧ ◨ ⚙ ⋯ ▾) and words ("Stop", "Send",
"Settings", "running", "done"), although it already draws its phone tab icons
as SVG masks.

**Change.** Vendor about 20 lucide paths as CSS mask variables, each icon
button keeping an `aria-label`:

> panel-left, panel-right, settings, more, plus, x, chevron, arrow-up,
> square, loader, circle-alert, triangle-alert, check, terminal, eye, pencil,
> search, wrench, git-branch, folder, file

### Colours

**Paseo** uses neutral surfaces (`#181B1A`, `#1E2120`, `#272A29`), text
`#fafafa`, muted `#A1A5A4`, and a green accent used rarely. **Status has its
own tokens**:
- running: blue `#5caaf6`;
- success: `#35c264`;
- warning: `#db932e`;
- danger: `#f7796d`;
- diff: `#4ade80` and `#ef4444`.

**liton** uses gold for nearly everything: titles, tool names, the selected
row, the focused edge, diff counts, unread, waiting, tabs, the user bubble and
Send.

**Change.**
- Derive `--running`, `--ok`, `--warn`, `--fail`, `--added` and `--removed` in
  style.css, overridable by a theme.
- Keep the accent for focus and the primary action. Gold becomes the theme's
  character, not a signal.

## The complaints, answered

- **Panes are clunky.**
  - Drawers toggle instead of closing.
  - Tabs get a `×`.
  - Stack/Tabs and +/− go.
  - Moves name their target, and drag waits on roc-signals.
- **Two rows per workspace, and a `+`.** Use one row per session. A workspace
  shows only as meta, or as a header when it holds two or more. `+` shows on a
  project's hover only.
- **Titles look like stale subjects.** They are the first prompt's title. Add
  "3m" for the last activity and Rename in `⋮`, and later a "last action"
  hover preview.
- **Dots and gold rings.** Five states, each an icon:
  - a blue spinning ring (running);
  - an amber alert (needs you);
  - a red triangle (failed);
  - a solid green dot (done, unread);
  - a faint dot (done, read).

  Idle shows nothing. Unread is the green dot and a bold title, with no ring.
- **`+N −M` in gold.** Green and red, in two spans. Drop the "changed"
  placeholder, which flips to the counts once they load.
- **No `⋯` per workspace.**
  - A project's: New workspace, Project settings, Hide.
  - A workspace's: Copy path, Copy branch, Rename, Pin, Mark read/unread,
    Archive.

  Items whose capability is missing are left out.
- **A fading dot and "running".** Use the spinner ring, with no word.
- **The gold left borders.** Remove them, from rows and the inbox alike.
- **Tool calls stand out.** Muted grouped one-liners, the output folded, a
  shimmer while running, and finished turns collapsed.
- **Text instead of icons.** Stop, Send, Settings, the drawer toggles and the
  status words all become icons.
- **The top bar.** Drop it from the Workbench; the gear goes to the bottom of
  the sidebar.
- **The gold gradient.** See Themes.

## Better than Paseo, never worse

- **Rows say what the agent does.** Paseo's six rows here all read `main`.
- **The phone tab bar**, with its badge and swipes.
- **The chat header's meta line.**
- **Collapsed turns that stay legible.** liton can show "4 steps · 12s" with
  the last target inline, instead of hiding the text.
- **The inbox, presets, glass themes and review comments.**
- **Speed.** All of this is CSS and small view changes, which keeps the
  benchmark lead.

## To-do (highest impact first, in reviewable steps)

**Step 1: quiet the chrome**

1. **S.** Neutral selection, with no gold bar (rows and inbox).
   *ui/style.css*
2. **S.** Semantic status and diff tokens, used by the dots, badges and diffs.
   *ui/style.css*, *ui/Themes.roc*
3. **S.** `+N` green and `−M` red, with no "changed" placeholder.
   *ui/Model.roc* (`Row.counts` as a record), *ui/Liton.roc* `tree`,
   *ui/style.css*

**Step 2: status as icons**

4. **M.** The five-state status icon replaces the words in rows and the header;
   the words stay as accessible names. *ui/style.css*, *ui/Liton.roc*
   (`tree`, `agent_header`), *ui/Model.roc* `attention_dot`
5. **M.** The icon set as CSS masks; Settings, the drawer toggles, `⋯` and `+`
   become icon buttons. *ui/style.css*, *ui/Liton.roc*
6. **S.** Stop and Send become one round icon in the composer, still showing
   pending at once (rules.md). *ui/Liton.roc* (`chat`, `agent_header`),
   *ui/style.css*, *ui/specs/*

**Step 3: tool calls and turns**

7. **M.** One muted line per tool call, with a chevron, a shimmer and red on
   failure. *ui/Liton.roc* `tool_card`, *ui/style.css*
8. **M.** Group consecutive calls into one summary line. *ui/Model.roc*,
   *ui/Liton.roc*
9. **M.** The working loader and elapsed timer, and the end-of-turn footer.
   *ui/Model.roc*, *ui/Liton.roc*; the turn's start may need *capabilities/*
   and *providers/paseo*
10. **M.** A chat option "Collapse": Full, Tools (the default) or Turns.
    *ui/Widgets.roc*, *ui/Model.roc*, *ui/Liton.roc*
11. **M.** Permission cards with the body as Markdown and the provider's own
    choices. *capabilities/* (chat permission), *providers/paseo*,
    *ui/Liton.roc*

**Step 4: the sidebar**

12. **M.** One row per session; a workspace row only when it holds two or
    more; "3m" trailing; sentence-case projects. *ui/Model.roc*
    (`workspace_rows`), *ui/Liton.roc*, *ui/style.css*
13. **M.** `⋮` menus per project and per workspace or session, also on
    right-click. *ui/Model.roc*, *ui/Liton.roc*, *capabilities/* (rename, pin,
    archive)

**Step 5: top bar and settings**

14. **M.** No bar in the Workbench on a wide screen: toggles in the chat
    header, the count in the Workspaces header and title, the gear in the
    sidebar footer, toasts for notices. *ui/Liton.roc* (`page`, `bar`),
    *ui/style.css*, *setup/Default.roc*
15. **S.** Keys: Ctrl+B and Ctrl+E (drawers), Ctrl+, (Settings), Esc (stop).
    *ui/Model.roc*

**Step 6: composer and layout**

16. **S.** An 820px centred column, 15px text, a neutral bubble.
    *ui/style.css*
17. **M.** The composer box, with a model chip and the voice controls in its
    bottom row. *ui/Liton.roc*, *ui/style.css*, *ui/Microphone.roc*

**Step 7: drawer and panes**

18. **M.** Changes: a folder tree, a scope dropdown, a review panel only with
    drafts, and "Open diff in main area". *ui/Liton.roc* (`changes`,
    `git_diff`), *ui/Model.roc*
19. **L.** Workbench panes hide instead of closing; tabs get icons and `×`;
    Stack/Tabs moves into `⋯`; moves name targets; drag comes later.
    *ui/Model.roc*, *ui/Liton.roc*, *ui/style.css*

**Step 8: phone**

20. **S.** No brand bar, the gear in the Workspaces header, icon Send and Stop.
    *ui/style.css*, *ui/Liton.roc*

**Step 9: themes**

21. **M.** An `Image` background in `Setup.Theme` and Settings (below).
    *setup/Setup.roc*, *setup/Default.roc*, *ui/Themes.roc*, *ui/Liton.roc*,
    the daemon's static files

## Themes

**Pastoral painting under glass.** Thomas Cole's "The Arcadian or Pastoral
State" (1834, public domain), as kai uses it. A mock-up
(`liton-desktop-pastoral.png`) used these settings:
- a radial dim from 45% black at the centre to 75% at the edges;
- glass `#0c0c0c` at 55% with a 5px blur;
- a 1px text shadow on Markdown and rows.

Text stayed readable, and the gold reads better than on the gradient.

- **Contrast.** Check muted text at 4.5:1 against the dimmed painting's
  brightest region, not its average. With Glass off the tint is opaque, so the
  painting shows only in the gaps.
- **Performance.**
  - Put the image on a fixed layer, so it isn't repainted on scroll.
  - Give each pane its own compositor layer (`translateZ(0)`, as kai does), so
    its blur isn't recomputed.
  - Keep pane blur at 5px or less.
  - Keep the Glass toggle for slow devices.
- **Size and format.**
  - Use `image-set()` in the order AVIF, WebP, JPEG: 1920px (about 200 KB AVIF)
    by default, 2560px above 1100px, and 3840px only on high-DPI screens over
    1700px.
  - Show a 140-byte WebP placeholder while it loads.
  - Use a hashed, immutable URL.
  - Load it after first paint, so `bench/` cold-load numbers don't move.
- **Backgrounds users choose.**
  - Add `Image({ url, dim })` to `Setup.Theme.background`; setups ship images
    in the daemon's static files.
  - Settings → Theme gets a Background choice (none, the theme's, a URL or a
    file) and a dim slider.
  - A picked file goes to IndexedDB, and the snapshot names it rather than
    holding its bytes.
  - The dim can follow the image's luminance.

**Experiments** (tokens plus an optional overlay, status colours kept):
- **Matrix:** black, a `#00ff41` accent, all mono. An optional glyph-rain
  canvas is off by default and under reduced motion.
- **Retro CRT:** an amber or green phosphor glow, a 4% scanline gradient and a
  vignette, with no blur.
- **Paper:** light, a `#f4efe4` ground, ink text, a serif display font,
  hairlines, no glass.
- **Nord:** `#2e3440` and `#88c0d0`, with aurora status colours (`#a3be8c`,
  `#ebcb8b`, `#bf616a`).

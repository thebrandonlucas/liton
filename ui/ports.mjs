// liton: what the app (app.wasm, from ui/) asks of the page that
// roc-signals does not model. The ports are declared in ui/Ports.roc.

// A chat shows its latest entries; scrolling up to within a screen of its
// Show earlier button presses it, so earlier entries come as they are read.
document.addEventListener("scroll", (event) => {
  const box = event.target;
  const earlier = box.matches?.(".timeline-scroll") && box.querySelector(":scope > .earlier > .show-earlier");
  if (earlier && earlier.getBoundingClientRect().bottom > box.getBoundingClientRect().top - box.clientHeight) earlier.click();
}, { capture: true, passive: true });

// FIXME: roc-signals's boot doesn't tell the platform, so the page writes
// whether it is a Mac, whose keys liton writes as ⌘B, for the app to read
// at boot (`Liton.platform_key`). Drop this once the boot carries it.
try {
  const platform = navigator.userAgentData?.platform ?? navigator.platform ?? "";
  sessionStorage.setItem("liton.platform", /^(mac|iphone|ipad|ipod)/i.test(platform) ? "mac" : "other");
} catch {}

// FIXME: a JavaScript stopgap for two things roc-signals does not offer.
// Once it does, this becomes Roc in ui/Drag.roc and ui/Liton.roc:
// - Pointer positions during a drag: a pointer's moves and release in page
//   coordinates wherever it goes, not only within the zone it is over, and
//   hit-testing against the layout as it was when the drag began (or zone
//   boxes taken then), so a layout previewed under the pointer doesn't
//   change what it is over.
// - Moving an element with the pointer at the frame, on the compositor.
// - View transitions: a way for an update to ask that the DOM change it
//   makes be animated with `document.startViewTransition`, applying it
//   within the transition's update rather than at a frame the update holds
//   back (here the app's report drain falls back to its 100 ms timer).
// While a pane's tab or header is held (`Drag.pointer`), this reports the
// pointer: once it has moved 4 pixels, its first move and each move to
// another part of a tile, as ui/Drag.roc's `drop_at` tells them apart, with
// the tile (`data-tile`) and tab (`data-tab`) under it as they were at the
// press, and how far across and down that tab or tile it is in ten
// thousandths; then the release, or a cancel for Escape, a cancelled
// pointer or a press that never moved. The ghost (`.drag-ghost`) follows
// each move between reports. A move to another part of a tile, and a
// cancel or a release outside the tiles, are reported inside a view
// transition, so the tiles move to the layout previewed rather than jump,
// unless motion is reduced (the system's setting or the theme's). While a
// line between tiles is held (`column` or `row` names it), each move
// instead reports how far across the two tracks beside it the pointer is,
// the tracks measured from the grid's computed `grid-template-columns` or
// `-rows` at the press.
const boxes = (attribute) => [...document.querySelectorAll(`[${attribute}]`)].map((element) => ({ id: element.getAttribute(attribute), box: element.getBoundingClientRect() }));
const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches || getComputedStyle(document.querySelector(".liton") ?? document.body).getPropertyValue("--motion").trim() === "0";
// The page doesn't render while a transition's update runs, so the update
// ends when the grid changes, as the app draws the message `change` emits
// (its report drain then waits on a timer rather than a frame), or after a
// while if nothing changes. A transition skipped by the next is no error.
const transition = (change) => {
  if (!document.startViewTransition || reduced()) return change();
  const running = document.startViewTransition(() => new Promise((done) => {
    const grid = document.querySelector(".grid");
    const ended = () => { watch.disconnect(); clearTimeout(timer); done(); };
    const watch = new MutationObserver(ended), timer = setTimeout(ended, 300);
    if (grid) watch.observe(grid, { subtree: true, childList: true, attributes: true });
    change();
  }));
  for (const settled of [running.ready, running.finished, running.updateCallbackDone]) settled.catch(() => {});
};
// The ghost at the pointer, at the frame after the app's.
let ghost_frame = 0;
const follow = (x, y) => {
  cancelAnimationFrame(ghost_frame);
  ghost_frame = requestAnimationFrame(() => {
    const ghost = document.querySelector(".drag-ghost");
    if (ghost) ghost.style.transform = `translate(${x}px, ${y}px)`;
  });
};
// How far across the tracks beside `line` the point `at` is, in ten
// thousandths, by the grid's tracks as the browser laid them out.
const across_tracks = (axis, line) => {
  const grid = document.querySelector(".grid"), style = getComputedStyle(grid), box = grid.getBoundingClientRect();
  const sizes = style[axis === "column" ? "gridTemplateColumns" : "gridTemplateRows"].split(" ").map(parseFloat);
  const origin = axis === "column" ? box.left + parseFloat(style.paddingLeft) - grid.scrollLeft : box.top + parseFloat(style.paddingTop) - grid.scrollTop;
  const from = origin + sizes.slice(0, line - 1).reduce((sum, size) => sum + size, 0), both = sizes[line - 1] + sizes[line];
  return (at) => Math.max(0, Math.min(10000, Math.round((at - from) * 10000 / both)));
};
// The latest press and move of each pointer, so a drag whose report starts
// after the pointer has moved reports from the press.
const pointers = new Map();
for (const type of ["pointerdown", "pointermove"]) window.addEventListener(type, (event) => {
  const seen = pointers.get(event.pointerId);
  pointers.set(event.pointerId, { down: type === "pointerdown" || !seen ? { x: event.clientX, y: event.clientY } : seen.down, last: event });
}, true);
const drag = ({ pointer, column, row }, { emit }) => {
  const tiles = boxes("data-tile"), tabs = boxes("data-tab");
  const resizing = column > 0 ? across_tracks("column", column) : row > 0 ? across_tracks("row", row) : null;
  let start = null, moved = false, part = "";
  const under = (list, x, y) => list.find(({ box }) => x >= box.left && x < box.right && y >= box.top && y < box.bottom);
  const report = (phase, event) => {
    if (resizing) return { phase, x: Math.round(event.clientX), y: Math.round(event.clientY), tile: "", tab: "", across: column > 0 ? resizing(event.clientX) : 0, down: row > 0 ? resizing(event.clientY) : 0 };
    const x = event.clientX, y = event.clientY, tab = under(tabs, x, y), tile = tab ? null : under(tiles, x, y), hit = tab ?? tile;
    const share = (at, from, size) => Math.max(0, Math.min(10000, Math.round((at - from) * 10000 / size)));
    return { phase, x: Math.round(x), y: Math.round(y), tile: (tab ? under(tiles, x, y)?.id : tile?.id) ?? "", tab: tab?.id ?? "", across: hit ? share(x, hit.box.left, hit.box.width) : 0, down: hit ? share(y, hit.box.top, hit.box.height) : 0 };
  };
  // The tab's half, or the fifth by the nearest edge or the middle of the
  // tile, that the pointer is over, as ui/Drag.roc's `drop_at` tells them
  // apart.
  const part_of = ({ tile, tab, across, down }) => {
    if (tab) return `${tab}:${across < 5000}`;
    const [edge, away] = [["right", 10000 - across], ["up", down], ["down", 10000 - down]].reduce((closest, side) => (side[1] < closest[1] ? side : closest), ["left", across]);
    return `${tile}:${away < 2000 ? edge : "middle"}`;
  };
  const move = (event) => {
    if (event.pointerId !== pointer) return;
    start ??= { x: event.clientX, y: event.clientY };
    if (!moved && Math.hypot(event.clientX - start.x, event.clientY - start.y) < 4) return;
    moved = true;
    const at = report("Moved", event), now = part_of(at);
    if (resizing) return emit(at);
    if (now !== part) {
      part = now;
      transition(() => emit(at));
    }
    follow(at.x, at.y);
  };
  // A release over a tile drops the pane where the layout shows it already;
  // one outside the tiles puts the layout back, which a transition shows.
  const up = (event) => {
    if (event.pointerId !== pointer) return;
    const at = report(moved ? "Released" : "Cancelled", event);
    if (moved && !resizing && !at.tile) transition(() => emit(at));
    else emit(at);
  };
  const cancel = (event) => event.pointerId === pointer && transition(() => emit(report("Cancelled", event)));
  const key = (event) => {
    if (event.key !== "Escape" || !moved) return;
    event.stopImmediatePropagation();
    event.preventDefault();
    transition(() => emit({ phase: "Cancelled", x: 0, y: 0, tile: "", tab: "", across: 0, down: 0 }));
  };
  const seen = pointers.get(pointer);
  if (seen) {
    start = seen.down;
    if (seen.last.type === "pointermove") move(seen.last);
  }
  const listeners = [["pointermove", move], ["pointerup", up], ["pointercancel", cancel], ["keydown", key]];
  for (const [type, listener] of listeners) window.addEventListener(type, listener, true);
  return () => { for (const [type, listener] of listeners) window.removeEventListener(type, listener, true); };
};

// Voice (ui/Speech.roc) loads ui/voice.mjs and its worklet on first use only.
const voice = () => import("./voice.mjs");

export default {
  // Copies text, answering whether the browser let it. The clipboard API
  // needs a secure context; a page served over plain HTTP from another
  // machine falls back to the older copy command.
  "liton/copy": {
    call: async (text) => {
      try {
        await navigator.clipboard.writeText(text);
        return true;
      } catch {
        const area = Object.assign(document.createElement("textarea"), { value: text });
        area.style.position = "fixed";
        area.style.opacity = "0";
        document.body.append(area);
        area.select();
        const copied = document.execCommand("copy");
        area.remove();
        return copied;
      }
    },
  },
  "liton/drag/pointer": { subscribe: drag },
  "liton/voice/capture": {
    subscribe(asked, port) {
      let stop, gone;
      voice().then((v) => gone || (stop = v.capture(asked, port)), port.close);
      return () => (gone = true) && stop?.();
    },
  },
  "liton/voice/order": { command: (asked) => voice().then((v) => v.order(asked)) },
  "liton/voice/voices": { call: () => voice().then((v) => v.voices()) },
};

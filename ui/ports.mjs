// liton: what the app (app.wasm, from ui/) asks of the page that
// roc-signals does not model. The ports are declared in ui/Ports.roc.

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
// - Moving an element with the pointer at the frame, and animating where
//   elements were to where an update puts them, on the compositor and
//   without holding back the page's frames as a view transition does while
//   it captures the page before and after an update (roc-signals's
//   `ViewTransition`), the next change skipping the one running.
// While a pane's tab or header is held (`Drag.pointer`), this reports the
// pointer: once it has moved 4 pixels, its first move and each move to
// another part of a tile, as ui/Drag.roc's `drop_at` tells them apart, with
// the tile (`data-tile`) and tab (`data-tab`) under it as they were at the
// press, and how far across and down that tab or tile it is in ten
// thousandths; then the release, or a cancel for Escape, a cancelled
// pointer or a press that never moved. The ghost (`.drag-ghost`) follows
// each move between reports. The tiles slide from where they were to the
// layout a report previews, unless motion is reduced (the system's setting
// or the theme's). While a line between tiles is held (`column` or `row`
// names it), each move instead reports how far across the two tracks beside
// it the pointer is, the tracks measured from the grid's computed
// `grid-template-columns` or `-rows` at the press.
const boxes = (attribute) => [...document.querySelectorAll(`[${attribute}]`)].map((element) => ({ id: element.getAttribute(attribute), box: element.getBoundingClientRect() }));
const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches || getComputedStyle(document.querySelector(".liton") ?? document.body).getPropertyValue("--motion").trim() === "0";
// After `change`, at the frame the app draws it in, each tile moved slides
// from where it showed, mid-slide included, to its new place, and a new one
// fades in. Its frame is asked after `change`'s report, so it runs after the
// app's.
const slide = (change) => {
  if (reduced()) return change();
  const shown = new Map(boxes("data-tile").map(({ id, box }) => [id, box]));
  change();
  requestAnimationFrame(() => {
    for (const tile of document.querySelectorAll("[data-tile]")) {
      for (const running of tile.getAnimations()) running.cancel();
      const from = shown.get(tile.getAttribute("data-tile")), to = tile.getBoundingClientRect();
      const timing = { duration: 180, easing: "ease-out" };
      if (!from) tile.animate({ opacity: [0, 1] }, timing);
      else if (to.width > 0 && to.height > 0 && [from.left - to.left, from.top - to.top, from.width - to.width, from.height - to.height].some((moved) => Math.abs(moved) >= 1))
        tile.animate({ transformOrigin: ["0 0", "0 0"], transform: [`translate(${from.left - to.left}px, ${from.top - to.top}px) scale(${from.width / to.width}, ${from.height / to.height})`, "none"] }, timing);
    }
  });
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
      slide(() => emit(at));
    }
    follow(at.x, at.y);
  };
  // A release over a tile drops the pane where the layout shows it already;
  // one outside the tiles puts the layout back, the tiles sliding there.
  const up = (event) => {
    if (event.pointerId !== pointer) return;
    const at = report(moved ? "Released" : "Cancelled", event);
    if (moved && !resizing && !at.tile) slide(() => emit(at));
    else emit(at);
  };
  const cancel = (event) => event.pointerId === pointer && slide(() => emit(report("Cancelled", event)));
  const key = (event) => {
    if (event.key !== "Escape" || !moved) return;
    event.stopImmediatePropagation();
    event.preventDefault();
    slide(() => emit({ phase: "Cancelled", x: 0, y: 0, tile: "", tab: "", across: 0, down: 0 }));
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

// FIXME: a JavaScript stopgap, as roc-signals reports no wheel events, and
// so not a trackpad's swipe. Once it reports a wheel's deltaX and whether
// what is under the pointer scrolls across, this becomes Roc in
// ui/Liton.roc. A two-finger swipe across (`Ports.swipe`), more across than
// down, not over something that scrolls across, reports "next" or
// "previous" once 100 pixels have gone by, then nothing until the fingers
// rest for a quarter second. A three-finger swipe is the system's, and no
// page hears it. What is under the fingers is read once a swipe, as it
// begins, not at each of its events, which go on through the slide.
const swipe = (_, { emit }) => {
  let travelled = 0, rest = 0, spent = false, over_scroller = false;
  const scrolls_across = (element) => {
    for (let at = element; at instanceof Element && at !== document.body; at = at.parentElement)
      if (/(auto|scroll)/.test(getComputedStyle(at).overflowX) && at.scrollWidth > at.clientWidth) return true;
    return false;
  };
  const wheel = (event) => {
    if (event.ctrlKey || Math.abs(event.deltaX) <= Math.abs(event.deltaY)) return;
    if (travelled === 0 && !spent) over_scroller = scrolls_across(event.target);
    if (over_scroller) return;
    clearTimeout(rest);
    rest = setTimeout(() => { travelled = 0; spent = false; }, 250);
    travelled += event.deltaX;
    if (spent || Math.abs(travelled) < 100) return;
    spent = true;
    emit(travelled > 0 ? "next" : "previous");
  };
  window.addEventListener("wheel", wheel, { passive: true });
  return () => { clearTimeout(rest); window.removeEventListener("wheel", wheel); };
};

// Voice (ui/Speech.roc) loads ui/voice.mjs and its worklet on first use only.
const voice = () => import("./voice.mjs");

// Signing (ui/nostr.mjs, ui/secp256k1.mjs) loads on first use only.
const nostr = () => import("./nostr.mjs");

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
  "liton/deck/swipe": { subscribe: swipe },
  "liton/voice/capture": {
    subscribe(asked, port) {
      let stop, gone;
      voice().then((v) => gone || (stop = v.capture(asked, port)), port.close);
      return () => (gone = true) && stop?.();
    },
  },
  "liton/voice/order": { command: (asked) => voice().then((v) => v.order(asked)) },
  "liton/voice/voices": { call: () => voice().then((v) => v.voices()) },
  "liton/nostr/key": { call: () => nostr().then((n) => n.key()) },
  "liton/nostr/sign": { call: (unsigned) => nostr().then((n) => n.sign(unsigned)) },
};

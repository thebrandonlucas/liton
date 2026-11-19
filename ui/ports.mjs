// liton: what the app (app.wasm, from ui/) asks of the page that
// roc-signals does not model. The ports are declared in ui/Ports.roc.

// A chat shows its latest entries; scrolling up to within a screen of its
// Show earlier button presses it, so earlier entries come as they are read.
document.addEventListener("scroll", (event) => {
  const box = event.target;
  const earlier = box.matches?.(".timeline-scroll") && box.querySelector(":scope > .earlier > .show-earlier");
  if (earlier && earlier.getBoundingClientRect().bottom > box.getBoundingClientRect().top - box.clientHeight) earlier.click();
}, { capture: true, passive: true });

// FIXME: a JavaScript stopgap for two things roc-signals does not offer.
// Once it does, this becomes Roc in ui/Drag.roc and ui/Liton.roc:
// - Pointer positions during a drag: a pointer's moves and release in page
//   coordinates wherever it goes, not only within the zone it is over, and
//   hit-testing against the layout as it was when the drag began (or zone
//   boxes taken then), so a layout previewed under the pointer doesn't
//   change what it is over.
// - View transitions: a way for an update to ask that the DOM change it
//   makes be animated with `document.startViewTransition`.
// While a pane's tab or header is held (`Drag.pointer`), this reports the
// pointer: once it has moved 4 pixels, each move, with the tile
// (`data-tile`) and tab (`data-tab`) under it as they were at the press,
// and how far across and down that tab or tile it is in ten thousandths;
// then the release, or a cancel for Escape, a cancelled pointer or a press
// that never moved. A move to another part of a tile, and the release or
// cancel ending a drag, are reported inside a view transition, so the
// tiles move to the layout previewed rather than jump, unless motion is
// reduced (the system's setting or the theme's).
const boxes = (attribute) => [...document.querySelectorAll(`[${attribute}]`)].map((element) => ({ id: element.getAttribute(attribute), box: element.getBoundingClientRect() }));
const reduced = () => matchMedia("(prefers-reduced-motion: reduce)").matches || getComputedStyle(document.querySelector(".liton") ?? document.body).getPropertyValue("--motion").trim() === "0";
const transition = (change) => {
  if (!document.startViewTransition || reduced()) return change();
  document.startViewTransition(() => new Promise((done) => { change(); requestAnimationFrame(() => requestAnimationFrame(done)); }));
};
const drag = ({ pointer }, { emit }) => {
  const tiles = boxes("data-tile"), tabs = boxes("data-tab");
  let start = null, moved = false, part = "";
  const under = (list, x, y) => list.find(({ box }) => x >= box.left && x < box.right && y >= box.top && y < box.bottom);
  const report = (phase, event) => {
    const x = event.clientX, y = event.clientY, tab = under(tabs, x, y), tile = tab ? null : under(tiles, x, y), hit = tab ?? tile;
    const share = (at, from, size) => Math.max(0, Math.min(10000, Math.round((at - from) * 10000 / size)));
    return { phase, x: Math.round(x), y: Math.round(y), tile: (tab ? under(tiles, x, y)?.id : tile?.id) ?? "", tab: tab?.id ?? "", across: hit ? share(x, hit.box.left, hit.box.width) : 0, down: hit ? share(y, hit.box.top, hit.box.height) : 0 };
  };
  // The tab, or the fifth by an edge or the middle of the tile, that the
  // pointer is over, as ui/Drag.roc's `drop_at` tells them apart.
  const part_of = ({ tile, tab, across, down }) => tab ? `${tab}:${across < 5000}` : `${tile}:${across < 2000 ? "left" : across > 8000 ? "right" : down < 2000 ? "up" : down > 8000 ? "down" : "middle"}`;
  const move = (event) => {
    if (event.pointerId !== pointer) return;
    start ??= { x: event.clientX, y: event.clientY };
    if (!moved && Math.hypot(event.clientX - start.x, event.clientY - start.y) < 4) return;
    moved = true;
    const at = report("Moved", event), now = part_of(at);
    if (now === part) return emit(at);
    part = now;
    transition(() => emit(at));
  };
  const up = (event) => event.pointerId === pointer && (moved ? transition(() => emit(report("Released", event))) : emit(report("Cancelled", event)));
  const cancel = (event) => event.pointerId === pointer && transition(() => emit(report("Cancelled", event)));
  const key = (event) => {
    if (event.key !== "Escape" || !moved) return;
    event.stopImmediatePropagation();
    event.preventDefault();
    transition(() => emit({ phase: "Cancelled", x: 0, y: 0, tile: "", tab: "", across: 0, down: 0 }));
  };
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

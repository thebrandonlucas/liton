// The clients the benchmark drives, described by the same few selectors so
// one script runs the same tasks against each. Agent k's prompt starts with
// `Bench task k:`; a timeline counts as shown when its own prompt is the only
// one visible and an answer ending with the mock's closing line is.
import { ports } from "./stack.mjs";

export const end_marker = "end of synthetic stream";

export const clients = {
  liton: {
    origin: () => `http://127.0.0.1:${ports.liton_for_browser}`,
    // liton opens on the chat of the most recently active session.
    load_path: () => "/",
    user_messages: 'section[aria-label="Chat"] .entry.user',
    answers: 'section[aria-label="Chat"] .entry',
    session_rows: 'section[aria-label="Workspaces"] .tree-session button',
    row_text: (k) => `Bench agent ${k}`,
    composer: 'section[aria-label="Chat"] textarea[aria-label="Message"]',
    long_row_text: (j) => `Long agent ${j}`,
    // On a phone, the tab that shows the session list.
    sidebar_toggle: '[data-testid="show-left"]',
  },
  paseo: {
    origin: () => `http://127.0.0.1:${ports.paseo_for_browser}`,
    // Paseo opens on its home screen; an agent's own URL opens its timeline.
    load_path: (agents) => `/h/${agents.server_id}/agent/${agents.ids[0]}`,
    user_messages: '[data-testid="user-message"]',
    answers: '[data-testid="assistant-message"]',
    // Each agent runs in its own directory, so it is its own workspace row.
    session_rows: '[data-testid^="sidebar-workspace-row-"]',
    row_text: (k) => `project-${k}`,
    composer: "textarea[data-composer-input]",
    long_row_text: (j) => `long-${j}`,
    sidebar_toggle: '[data-testid="menu-button"]',
  },
};

// The probe, run in the page before any of its scripts: records input event
// times and resolves waits on the frame after their condition first holds.
// All times are performance.now(), whose zero is navigation start.
export const probe = `(() => {
  const B = (window.__bench = { last_input: null, waits: [], done: {} });
  for (const type of ["pointerdown", "keydown"])
    addEventListener(type, (e) => { B.last_input = { type, time: e.timeStamp }; }, true);
  // Event timing: each input event's time to the next paint after its
  // handlers ran, the browser's own measure of responsiveness.
  B.event_times = [];
  if (PerformanceObserver.supportedEntryTypes?.includes("event"))
    new PerformanceObserver((l) => { for (const e of l.getEntries()) if (e.interactionId) B.event_times.push({ start: e.startTime, duration: e.duration }); }).observe({ type: "event", durationThreshold: 16 });
  // Frame gaps: the time between animation frames for the time asked.
  B.frames = (ms) => new Promise((resolve) => {
    const gaps = [];
    let last = performance.now();
    const end = last + ms;
    const frame = (now) => { gaps.push(now - last); last = now; if (now < end) requestAnimationFrame(frame); else resolve(gaps); };
    requestAnimationFrame(frame);
  });
  const holds = (test) => { try { return !!test(); } catch (_) { return false; } };
  let queued = false;
  const check = () => {
    queued = false;
    const now = performance.now();
    for (const w of B.waits) {
      if (w.found === undefined && holds(w.test)) {
        w.found = now;
        w.input = B.last_input;
        requestAnimationFrame(() => {
          B.done[w.name] = { found: w.found, frame: performance.now(), input: w.input };
        });
      }
    }
    B.waits = B.waits.filter((w) => w.found === undefined);
    if (B.waits.length) requestAnimationFrame(check);
  };
  const soon = () => { if (!queued) { queued = true; queueMicrotask(check); } };
  // A wait's input is the last input event before its condition held.
  B.watch = (name, test) => { delete B.done[name]; B.waits.push({ name, test }); soon(); };
  new MutationObserver(soon).observe(document, { subtree: true, childList: true, characterData: true, attributes: true });
  addEventListener("input", soon, true);
  // Conditions over the DOM, by the client's selectors.
  const visible = (e) => e.checkVisibility ? e.checkVisibility() : e.offsetParent !== null;
  B.texts = (selector) => [...document.querySelectorAll(selector)].filter(visible).map((e) => e.textContent);
  B.timeline_of = (c, k) => () => {
    const users = B.texts(c.user_messages);
    const prompts = users.filter((t) => /Bench task \\d+:/.test(t));
    return prompts.length > 0 && prompts.every((t) => t.includes("Bench task " + k + ":")) &&
      B.texts(c.answers).some((t) => t.includes(${JSON.stringify(end_marker)}));
  };
  B.list_shown = (c, n) => () => B.texts(c.session_rows).length >= n;
  B.message_shown = (c, text) => () => B.texts(c.user_messages).some((t) => t.includes(text));
  // Paseo keeps screens it left mounted but hidden, each with its composer.
  B.composer_has = (c, text) => () => [...document.querySelectorAll(c.composer)].find(visible)?.value === text;
  // Load conditions from the client, set before navigation.
  const load = window.__bench_load;
  if (load) {
    B.watch("list", B.list_shown(load.client, load.agents));
    B.watch("timeline", B.timeline_of(load.client, 0));
  }
})();`;

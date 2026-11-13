// node bench/bench.mjs [CDP] [options]: runs the same scripted tasks against
// liton and Paseo 0.15.3's web client, both on one throwaway Paseo daemon
// seeded with mock agents, and writes a JSON file and a markdown table to
// bench/results/. CDP is roc-signals's DevTools client (tests/browser/cdp.mjs,
// which `zig build e2e` fetches; found in zig-pkg/ when left out). CHROME
// names the browser (default `chromium` on PATH). See bench/README.md.
//
// It reruns itself in a private network namespace (`unshare -rn`), so nothing
// it starts can reach, or be reached from, any daemon outside it.
import { spawnSync, execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { parseArgs } from "node:util";
import { fileURLToPath, pathToFileURL } from "node:url";

if (!process.env.LITON_BENCH_NETNS) {
  const r = spawnSync("unshare", ["-rn", "sh", "-c", 'ip link set lo up && exec "$@"', "sh", process.execPath, ...process.argv.slice(1)], {
    stdio: "inherit",
    env: { ...process.env, LITON_BENCH_NETNS: "1" },
  });
  if (r.error) console.error(`could not open a private network namespace (unshare -rn): ${r.error.message}`);
  process.exit(r.status ?? 1);
}

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const { values: options, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    runs: { type: "string", default: "5" },
    "phone-runs": { type: "string", default: "3" },
    agents: { type: "string", default: "5" },
    rounds: { type: "string", default: "1" },
    sends: { type: "string", default: "3" },
    "idle-seconds": { type: "string", default: "60" },
    clients: { type: "string", default: "liton,paseo" },
    profiles: { type: "string", default: "desktop,phone" },
    "liton-www": { type: "string", default: path.join(repo, "zig-out/www") },
    precompressed: { type: "boolean", default: false },
    label: { type: "string", default: "baseline" },
    out: { type: "string", default: path.join(repo, "bench/results") },
  },
});
const number = (name) => Number(options[name]);
const agent_count = number("agents");
if (agent_count < 2 || agent_count > 9) throw new Error("--agents takes 2 to 9");

const default_cdp = () => {
  const zon = fs.readFileSync(path.join(repo, "build.zig.zon"), "utf8");
  const hash = zon.match(/roc_signals_source = \.\{[^}]*\.hash = "([^"]+)"/)[1];
  return path.join(repo, "zig-pkg", hash, "tests/browser/cdp.mjs");
};
const cdp_path = positionals[0] ?? default_cdp();
if (!fs.existsSync(cdp_path)) throw new Error(`no DevTools client at ${cdp_path}: run \`zig build --fetch\` first`);
const { launch } = await import(pathToFileURL(cdp_path).href);
const S = await import("./stack.mjs");
const { clients, probe } = await import("./clients.mjs");
const { precompressed_server } = await import("./static.mjs");

// Lighthouse's mobile settings: a mid-range phone on a slow 4G network.
const profiles = {
  desktop: { cpu: 1, network: null, runs: number("runs"), timeout: 60000 },
  phone: { cpu: 4, network: { offline: false, latency: 150, downloadThroughput: (1638.4 * 1024) / 8, uploadThroughput: (750 * 1024) / 8 }, runs: number("phone-runs"), timeout: 240000 },
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const scratch = S.make_scratch();
const log = fs.createWriteStream(path.join(scratch, "daemons.log"));
let failures = 0;
const say = (...a) => console.log(`[${new Date().toISOString().slice(11, 19)}]`, ...a);

// The rig: Paseo, its seeded agents, liton's daemon and the counting proxies.
const workspace = path.join(scratch, "workspace");
for (let k = 0; k < agent_count; k++) fs.mkdirSync(path.join(workspace, `project-${k}`), { recursive: true });
const proxies = {
  paseo_for_browser: await S.counting_proxy(S.ports.paseo_for_browser, S.ports.paseo),
  paseo_for_liton: await S.counting_proxy(S.ports.paseo_for_liton, S.ports.paseo),
};
say("starting Paseo");
const paseo = await S.start_paseo({ repo, scratch, log });
const list_agents = async () => JSON.parse(await paseo.cli("ls", "--json"));
const until_idle = (timeout = 60000) =>
  S.until("the agents to finish their turns", async () => (await list_agents()).every((a) => a.status === "idle"), timeout, 500);
// Agent 0, the one messages go to, finishes its turn last, so both clients
// open on it: liton follows the session updated last.
say(`seeding ${agent_count} mock agents`);
const seed = (k, model) => paseo.cli("run", "--provider", model, "--no-wait", "--title", `Bench agent ${k}`, "--cwd", path.join(workspace, `project-${k}`), `Bench task ${k}: tidy the module and report back`);
for (let k = agent_count - 1; k >= 1; k--) await seed(k, "mock/ten-second-stream");
await until_idle();
await seed(0, "mock/e2e-fast-stream");
await until_idle();
const agents = { ids: [] };
for (const a of await list_agents()) agents.ids[Number(a.name.replace("Bench agent ", ""))] = a.id;

say("starting liton's daemon");
await S.start_liton({ repo, scratch, log, www: options["liton-www"] });
if (options.precompressed) {
  await precompressed_server(S.ports.liton_static, options["liton-www"], S.ports.liton);
  proxies.liton_for_browser = await S.counting_proxy(S.ports.liton_for_browser, S.ports.liton_static);
} else {
  proxies.liton_for_browser = await S.counting_proxy(S.ports.liton_for_browser, S.ports.liton);
}

const browser = await launch({ executablePath: process.env.CHROME || "chromium" });
const browser_version = (await browser.conn.send("Browser.getVersion")).product;

// Paseo's web client asks for the daemon's password once and keeps it in
// localStorage; connect once through its form, untimed, and give every
// measured context that saved host, as a returning user has.
say("connecting Paseo's web client once");
const paseo_registry = await (async () => {
  const page = await browser.newPage();
  await page.goto(clients.paseo.origin() + "/");
  await page.waitForSelector('[data-testid="welcome-direct-connection"]');
  await page.click('[data-testid="welcome-direct-connection"]');
  await page.waitForSelector('[data-testid="direct-host-input"]');
  for (const [id, text] of [["direct-host-input", "127.0.0.1"], ["direct-port-input", String(S.ports.paseo_for_browser)], ["direct-password-input", S.password]]) {
    // Replacing what the field holds, as the port field is prefilled.
    await page.evaluate((id) => document.querySelector(`[data-testid="${id}"]`).select(), id);
    await page.insertText(text);
  }
  await page.click('[data-testid="direct-host-submit"]');
  await page.waitForSelector('[data-testid^="sidebar-workspace-row-"]');
  const registry = await page.evaluate(() => localStorage.getItem("@paseo:daemon-registry"));
  await page.close();
  return registry;
})();
agents.server_id = JSON.parse(paseo_registry)[0].serverId;

// --- Measurement -----------------------------------------------------------

const pss_kib = (pid) => {
  try {
    return Number(fs.readFileSync(`/proc/${pid}/smaps_rollup`, "utf8").match(/^Pss:\s+(\d+)/m)[1]);
  } catch (_) {
    return 0;
  }
};

async function open_page(name, profile) {
  const context = await browser.createBrowserContext();
  const page = await context.newPage();
  const client = clients[name];
  await page.send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 800, deviceScaleFactor: 1, mobile: false });
  await page.send("Network.enable");
  await page.send("Performance.enable");
  if (profile.network) await page.send("Network.emulateNetworkConditions", profile.network);
  if (profile.cpu > 1) await page.send("Emulation.setCPUThrottlingRate", { rate: profile.cpu });
  // Workers too, for their JS heaps.
  page.workers = new Set();
  page.conn.on(page.sessionId, "Target.attachedToTarget", (p) => {
    if (p.targetInfo.type.includes("worker")) page.workers.add(p.sessionId);
  });
  page.conn.on(page.sessionId, "Target.detachedFromTarget", (p) => page.workers.delete(p.sessionId));
  await page.send("Target.setAutoAttach", { autoAttach: true, waitForDebuggerOnStart: false, flatten: true });
  // Every response, for download sizes; `page.responses` is reset per load.
  const pending = new Map();
  page.responses = [];
  const sent = new Map();
  page.conn.on(page.sessionId, "Network.requestWillBeSent", (p) => sent.set(p.requestId, p.timestamp));
  page.conn.on(page.sessionId, "Network.responseReceived", (p) => pending.set(p.requestId, { url: p.response.url, mime: p.response.mimeType, status: p.response.status, encoding: p.response.headers["content-encoding"] ?? p.response.headers["Content-Encoding"] ?? "", decoded: 0, sent: sent.get(p.requestId) }));
  page.conn.on(page.sessionId, "Network.dataReceived", (p) => {
    const r = pending.get(p.requestId);
    if (r) r.decoded += p.dataLength;
  });
  page.conn.on(page.sessionId, "Network.loadingFinished", (p) => {
    const r = pending.get(p.requestId);
    if (r) page.responses.push({ ...r, transferred: p.encodedDataLength, finished: p.timestamp });
    pending.delete(p.requestId);
  });
  const config = { client: { ...client }, agents: agent_count };
  await page.evaluateOnNewDocument(`window.__bench_client = ${JSON.stringify(client)}; window.__bench_load = ${JSON.stringify(config)};`);
  if (name === "paseo") {
    await page.evaluateOnNewDocument(`localStorage.getItem("@paseo:daemon-registry") || localStorage.setItem("@paseo:daemon-registry", ${JSON.stringify(paseo_registry)})`);
  }
  await page.evaluateOnNewDocument(probe);
  return { page, context, url: client.origin() + client.load_path(agents) };
}

const wait_done = (page, name, timeout) =>
  S.until(`${name} in the page`, () => page.evaluate((n) => !!window.__bench?.done[n], name), timeout, 20).then(() => page.evaluate((n) => window.__bench.done[n], name));

const kind_of = (r) =>
  /\.wasm(\?|$)/.test(r.url) || r.mime === "application/wasm" ? "wasm"
  : /javascript/.test(r.mime) ? "js"
  : /css/.test(r.mime) ? "css"
  : /html/.test(r.mime) ? "html"
  : /json/.test(r.mime) ? "api"
  : "other";

// One page load: navigation start to first paint, to the agent list and to
// agent 0's timeline, each the frame after it first shows; and what came over
// the network for it.
async function load(page, url, timeout) {
  page.responses = [];
  await page.goto(url);
  const list = await wait_done(page, "list", timeout);
  const timeline = await wait_done(page, "timeline", timeout);
  await sleep(500);
  const timing = await page.evaluate(() => {
    const paint = Object.fromEntries(performance.getEntriesByType("paint").map((e) => [e.name, e.startTime]));
    const nav = performance.getEntriesByType("navigation")[0];
    return { first_paint: paint["first-paint"], first_contentful_paint: paint["first-contentful-paint"], dom_content_loaded: nav.domContentLoadedEventEnd, load_event: nav.loadEventEnd };
  });
  const download = {};
  for (const r of page.responses) {
    const d = (download[kind_of(r)] ??= { requests: 0, transferred: 0, decoded: 0, encodings: [] });
    d.requests++;
    d.transferred += r.transferred;
    d.decoded += r.decoded;
    if (r.encoding && !d.encodings.includes(r.encoding)) d.encodings.push(r.encoding);
  }
  // When each of the first requests was sent and finished, from the page's own.
  const zero = page.responses.find((r) => r.mime === "text/html")?.sent ?? Math.min(...page.responses.map((r) => r.sent));
  const waterfall = page.responses.slice(0, 12).map((r) => ({ path: new URL(r.url).pathname, sent: Math.round((r.sent - zero) * 1000), finished: Math.round((r.finished - zero) * 1000), transferred: r.transferred }));
  download.total = Object.values(download).reduce((t, d) => ({ requests: t.requests + d.requests, transferred: t.transferred + d.transferred, decoded: t.decoded + d.decoded }), { requests: 0, transferred: 0, decoded: 0 });
  return { ...timing, list_shown: list.frame, timeline_shown: timeline.frame, download, waterfall };
}

async function memory(page) {
  await page.send("HeapProfiler.collectGarbage").catch(() => {});
  for (const worker of page.workers) await page.conn.send("HeapProfiler.collectGarbage", {}, worker).catch(() => {});
  await sleep(300);
  const metrics = Object.fromEntries((await page.send("Performance.getMetrics")).metrics.map((m) => [m.name, m.value]));
  let worker_heap = 0;
  for (const worker of page.workers) worker_heap += (await page.conn.send("Runtime.getHeapUsage", {}, worker).catch(() => ({ usedSize: 0 }))).usedSize;
  const processes = (await browser.conn.send("SystemInfo.getProcessInfo")).processInfo;
  const renderers = processes.filter((p) => p.type === "renderer").map((p) => pss_kib(p.id));
  return {
    js_heap_page: metrics.JSHeapUsedSize,
    js_heap_workers: worker_heap,
    dom_nodes: metrics.Nodes,
    // The page's renderer is the largest: one page is open at a time.
    renderer_pss: Math.max(0, ...renderers) * 1024,
    chromium_pss: processes.reduce((t, p) => t + pss_kib(p.id), 0) * 1024,
  };
}

// The center of the first visible element matching selector whose text
// includes text, scrolled into view.
const center_of = (page, selector, text = "") =>
  page.evaluate(
    (selector, text) => {
      const e = [...document.querySelectorAll(selector)].find((e) => (e.checkVisibility ? e.checkVisibility() : true) && e.textContent.includes(text));
      if (!e) return null;
      e.scrollIntoView({ block: "nearest" });
      const r = e.getBoundingClientRect();
      return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
    },
    selector,
    text,
  );

// From the input event's own timestamp to the frame after the result shows.
async function timed(page, name, condition, act, timeout) {
  await page.evaluate(`window.__bench.watch(${JSON.stringify(name)}, ${condition})`);
  await act();
  const done = await wait_done(page, name, timeout);
  return done.frame - done.input.time;
}

async function interact(page, name, profile, run) {
  const client = clients[name];
  const timeout = profile.timeout;
  const clicks = [];
  const targets = [];
  for (let round = 0; round < number("rounds"); round++) for (let k = 1; k <= agent_count; k++) targets.push(k % agent_count);
  for (const k of targets) {
    let at = null;
    await S.until(`the row of agent ${k}`, async () => (at = await center_of(page, client.session_rows, client.row_text(k))), timeout);
    clicks.push(await timed(page, "click", `__bench.timeline_of(__bench_client, ${k})`, () => page.clickAt(at), timeout));
  }
  const keys = [];
  const sends = [];
  for (let j = 1; j <= number("sends"); j++) {
    const text = `Bench task 0: note ${run}.${j}`;
    await page.clickAt(await center_of(page, client.composer));
    // liton leaves a message sent with Enter in its focused input (roc-signals
    // defers a controlled value while its input has focus), so clear it first.
    await page.keyboard.down("Control");
    await page.keyboard.press("a");
    await page.keyboard.up("Control");
    await page.keyboard.press("Backspace");
    for (let i = 1; i <= text.length; i++) {
      keys.push(await timed(page, "key", `__bench.composer_has(__bench_client, ${JSON.stringify(text.slice(0, i))})`, () => page.keyboard.press(text[i - 1]), timeout));
    }
    sends.push(await timed(page, "send", `__bench.message_shown(__bench_client, ${JSON.stringify(text)})`, () => page.keyboard.press("Enter"), timeout));
    // The turn the message started: wait for it to begin, then to end.
    await S.until("the turn to start", async () => !(await list_agents()).every((a) => a.status === "idle"), 3000, 200).catch(() => {});
    await until_idle(timeout);
  }
  return { click_to_timeline: clicks, keystroke_to_frame: keys, send_to_message: sends };
}

const counter_names = { liton: ["liton_for_browser", "paseo_for_liton"], paseo: ["paseo_for_browser"] };
const snapshot = (name) => Object.fromEntries(counter_names[name].map((p) => [p, proxies[p].snapshot()]));
const since = (name, before) => Object.fromEntries(counter_names[name].map((p) => [p, S.delta(proxies[p].snapshot(), before[p])]));

async function measure(name, profile, run) {
  const { page, context, url } = await open_page(name, profile);
  try {
    const before_load = snapshot(name);
    const cold = await load(page, url, profile.timeout);
    const load_traffic = since(name, before_load);
    const warm = await load(page, url, profile.timeout);
    const memory_after_load = await memory(page);
    const before = snapshot(name);
    const started = Date.now();
    const input = await interact(page, name, profile, run);
    const active_traffic = { ...since(name, before), seconds: (Date.now() - started) / 1000 };
    const memory_after_input = await memory(page);
    if (page.errors.length) say(`  ${name}: page errors: ${page.errors.slice(0, 3).join(" | ")}`);
    return { cold, warm, memory_after_load, memory_after_input, input, load_traffic, active_traffic };
  } catch (error) {
    const shot = await page.send("Page.captureScreenshot", { format: "png" }).catch(() => null);
    failures++;
    const file = path.join(scratch, `failed-${name}-${run}.png`);
    if (shot) fs.writeFileSync(file, Buffer.from(shot.data, "base64"));
    say(`  ${name} run ${run} failed: ${error.message} (screenshot ${file})`);
    return { error: error.message };
  } finally {
    await context.close();
  }
}

// --- Runs ------------------------------------------------------------------

const names = options.clients.split(",");
const results = {};
for (const profile_name of options.profiles.split(",")) {
  const profile = profiles[profile_name];
  results[profile_name] = Object.fromEntries(names.map((n) => [n, []]));
  for (let run = 1; run <= profile.runs; run++) {
    // Alternate which client goes first, against drift.
    for (const name of run % 2 ? names : [...names].reverse()) {
      say(`${profile_name} run ${run}/${profile.runs}: ${name}`);
      results[profile_name][name].push(await measure(name, profile, run));
    }
  }
}

// Daemon load at rest: liton's daemon with no page open, then each client
// open on agent 0 and left alone.
const idle_seconds = number("idle-seconds");
const daemon_load = {};
say(`daemon load: liton's daemon alone for ${idle_seconds} s`);
{
  const before = proxies.paseo_for_liton.snapshot();
  await sleep(idle_seconds * 1000);
  daemon_load.liton_daemon_no_page = { paseo_for_liton: S.delta(proxies.paseo_for_liton.snapshot(), before), seconds: idle_seconds };
}
say(`daemon load: both clients open and idle for ${idle_seconds} s`);
{
  const open = [];
  for (const name of names) {
    const opened = await open_page(name, profiles.desktop);
    await load(opened.page, opened.url, 60000).catch((error) => say(`  ${name} did not finish loading: ${error.message}`));
    open.push({ name, ...opened });
  }
  await sleep(5000);
  const before = Object.fromEntries(names.map((n) => [n, snapshot(n)]));
  await sleep(idle_seconds * 1000);
  for (const { name, context } of open) {
    daemon_load[`${name}_idle`] = { ...since(name, before[name]), seconds: idle_seconds };
    await context.close();
  }
}
await browser.close();

// --- Report ----------------------------------------------------------------

const stats = (samples) => {
  const xs = samples.filter((x) => typeof x === "number" && Number.isFinite(x)).sort((a, b) => a - b);
  if (!xs.length) return null;
  const rank = (q) => xs[Math.min(xs.length - 1, Math.ceil(q * xs.length) - 1)];
  return { n: xs.length, median: xs.length % 2 ? xs[(xs.length - 1) / 2] : (xs[xs.length / 2 - 1] + xs[xs.length / 2]) / 2, p95: rank(0.95), min: xs[0], max: xs[xs.length - 1] };
};
const metrics = {
  "cold: first contentful paint (ms)": (r) => [r.cold.first_contentful_paint],
  "cold: agent list shown (ms)": (r) => [r.cold.list_shown],
  "cold: agent timeline shown (ms)": (r) => [r.cold.timeline_shown],
  "warm: first contentful paint (ms)": (r) => [r.warm.first_contentful_paint],
  "warm: agent list shown (ms)": (r) => [r.warm.list_shown],
  "warm: agent timeline shown (ms)": (r) => [r.warm.timeline_shown],
  "click session to timeline (ms)": (r) => r.input.click_to_timeline,
  "keystroke to frame (ms)": (r) => r.input.keystroke_to_frame,
  "send to message shown (ms)": (r) => r.input.send_to_message,
  "JS heap after load, page + workers (MB)": (r) => [(r.memory_after_load.js_heap_page + r.memory_after_load.js_heap_workers) / 1e6],
  "renderer memory (PSS) after load (MB)": (r) => [r.memory_after_load.renderer_pss / 1e6],
  "JS heap after input (MB)": (r) => [(r.memory_after_input.js_heap_page + r.memory_after_input.js_heap_workers) / 1e6],
  "renderer memory (PSS) after input (MB)": (r) => [r.memory_after_input.renderer_pss / 1e6],
  "cold download, transferred (MB)": (r) => [r.cold.download.total.transferred / 1e6],
  "cold download, decoded (MB)": (r) => [r.cold.download.total.decoded / 1e6],
  "cold load: requests": (r) => [r.cold.download.total.requests],
};
const summary = {};
for (const [profile_name, by_client] of Object.entries(results)) {
  summary[profile_name] = {};
  for (const [name, runs] of Object.entries(by_client)) {
    const ok = runs.filter((r) => !r.error);
    summary[profile_name][name] = Object.fromEntries(Object.entries(metrics).map(([metric, pick]) => [metric, stats(ok.flatMap(pick))]));
    summary[profile_name][name].failed_runs = runs.length - ok.length;
  }
}

const git = (...a) => {
  try {
    return execFileSync("git", ["-C", repo, ...a], { encoding: "utf8" }).trim();
  } catch (_) {
    return null;
  }
};
const wasm = path.join(options["liton-www"], "app.wasm");
const meta = {
  date: new Date().toISOString(),
  label: options.label,
  liton_commit: git("rev-parse", "--short", "HEAD"),
  liton_dirty: !!git("status", "--porcelain", "--untracked-files=no"),
  liton_wasm_bytes: fs.existsSync(wasm) ? fs.statSync(wasm).size : null,
  liton_precompressed: options.precompressed,
  paseo_version: "0.15.3",
  browser: browser_version,
  node: process.version,
  agents: agent_count,
  clicks_per_run: number("rounds") * agent_count,
  sends_per_run: number("sends"),
  profiles: Object.fromEntries(options.profiles.split(",").map((p) => [p, profiles[p]])),
};
const round = (x) => Math.round(x * 10) / 10;
const per_minute = (counts, seconds) => counts && Object.fromEntries(["http_requests", "ws_connections", "ws_messages_up", "ws_messages_down", "ws_bytes_up", "ws_bytes_down"].map((k) => [k, round((counts[k] * 60) / seconds)]));
const daemon_summary = {
  "liton daemon -> Paseo, no page open": per_minute(daemon_load.liton_daemon_no_page?.paseo_for_liton, idle_seconds),
  "liton idle: browser -> liton daemon": per_minute(daemon_load.liton_idle?.liton_for_browser, idle_seconds),
  "liton idle: liton daemon -> Paseo": per_minute(daemon_load.liton_idle?.paseo_for_liton, idle_seconds),
  "Paseo idle: browser -> Paseo": per_minute(daemon_load.paseo_idle?.paseo_for_browser, idle_seconds),
};
for (const [profile_name, by_client] of Object.entries(results)) {
  for (const [name, runs] of Object.entries(by_client)) {
    const ok = runs.filter((r) => !r.error);
    for (const p of counter_names[name]) {
      const rates = ok.map((r) => per_minute(r.active_traffic[p], r.active_traffic.seconds));
      if (rates.length) daemon_summary[`${name} active (${profile_name}): ${p.replaceAll("_", " ")}`] = Object.fromEntries(Object.keys(rates[0]).map((k) => [k, round(stats(rates.map((x) => x[k])).median)]));
    }
  }
}

fs.mkdirSync(options.out, { recursive: true });
const stem = path.join(options.out, `${meta.date.slice(0, 10)}-${options.label}`);
fs.writeFileSync(`${stem}.json`, JSON.stringify({ meta, summary, daemon_load: daemon_summary, raw: { results, daemon_load } }, null, 1) + "\n");

const fmt = (s) => (s ? `${s.median < 10 ? s.median.toFixed(2) : Math.round(s.median)} / ${s.p95 < 10 ? s.p95.toFixed(2) : Math.round(s.p95)}` : "n/a");
let md = `# liton vs Paseo: ${options.label}\n\n`;
md += `${meta.date.slice(0, 10)}, liton ${meta.liton_commit}${meta.liton_dirty ? " (uncommitted changes)" : ""}, app.wasm ${(meta.liton_wasm_bytes / 1e6).toFixed(1)} MB${meta.liton_precompressed ? " served precompressed (Brotli)" : ""}, Paseo ${meta.paseo_version} web client, ${meta.browser} headless. ${agent_count} mock agents; median / p95.\n`;
for (const [profile_name, by_client] of Object.entries(summary)) {
  const p = profiles[profile_name];
  md += `\n## ${profile_name}${p.cpu > 1 ? ` (CPU ${p.cpu}x slower, ${p.network.latency} ms latency, ${Math.round((p.network.downloadThroughput * 8) / 1024)} kbit/s down)` : ""}, ${p.runs} runs\n\n`;
  md += `| metric | ${names.join(" | ")} |\n|---|${names.map(() => "---|").join("")}\n`;
  for (const metric of Object.keys(metrics)) md += `| ${metric} | ${names.map((n) => fmt(by_client[n]?.[metric])).join(" | ")} |\n`;
  const failed = names.filter((n) => by_client[n]?.failed_runs).map((n) => `${n}: ${by_client[n].failed_runs}`);
  if (failed.length) md += `\nFailed runs: ${failed.join(", ")}\n`;
}
md += `\n## Daemon load, per minute\n\n| traffic | HTTP requests | WS connections | WS messages up | WS messages down | WS KB down |\n|---|---|---|---|---|---|\n`;
for (const [what, r] of Object.entries(daemon_summary)) if (r) md += `| ${what} | ${r.http_requests} | ${r.ws_connections} | ${r.ws_messages_up} | ${r.ws_messages_down} | ${(r.ws_bytes_down / 1000).toFixed(1)} |\n`;
md += `\n## Cold download by kind (first run, desktop): requests, transferred / decoded KB\n\n| kind | ${names.join(" | ")} |\n|---|${names.map(() => "---|").join("")}\n`;
const first_cold = (n) => Object.values(results)[0]?.[n]?.find((r) => !r.error)?.cold;
for (const kind of ["html", "js", "css", "wasm", "api", "other", "total"]) {
  md += `| ${kind} | ${names.map((n) => { const d = first_cold(n)?.download[kind]; return d ? `${d.requests}: ${Math.round(d.transferred / 1000)} / ${Math.round(d.decoded / 1000)}${d.encodings?.length ? ` (${d.encodings.join(", ")})` : ""}` : "-"; }).join(" | ")} |\n`;
}
for (const n of names) {
  const cold = first_cold(n);
  if (!cold) continue;
  md += `\n### ${n}: first cold load, ms from the page request (first paint ${Math.round(cold.first_paint)}, list ${Math.round(cold.list_shown)}, timeline ${Math.round(cold.timeline_shown)})\n\n| request | sent | finished | KB |\n|---|---|---|---|\n`;
  for (const w of cold.waterfall) md += `| ${w.path.length > 60 ? "…" + w.path.slice(-59) : w.path} | ${w.sent} | ${w.finished} | ${Math.round(w.transferred / 1000)} |\n`;
}
fs.writeFileSync(`${stem}.md`, md);
console.log(md);
say(`wrote ${stem}.json and ${stem}.md`);
if (failures) say(`kept ${scratch} for the failed runs' screenshots and the daemons' log`);
else fs.rmSync(scratch, { recursive: true, force: true });
process.exit(0);

// node e2e/federation.mjs, after `zig build daemon example-provider`: checks
// providers outside the daemon (docs/protocol.md, Providers outside the
// daemon). A daemon's setup (LITON_SETUP) points it at the example echo
// provider, and LITON_PROVIDERS at a second daemon serving the mock provider
// and at a port nothing listens on, each on a free port with a fresh
// database.
import { spawn } from "node:child_process";
import assert from "node:assert/strict";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const freePort = () =>
  new Promise((resolve) => {
    const probe = net.createServer().listen(0, "127.0.0.1", () => {
      const { port } = probe.address();
      probe.close(() => resolve(port));
    });
  });
const [echoPort, peerPort, mainPort, downPort] = [await freePort(), await freePort(), await freePort(), await freePort()];
let check = "the daemons answer";
const fail = (error) => {
  console.log(`FAIL ${check}: ${String(error?.message ?? error).split("\n")[0]}`);
  process.exit(1);
};
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "liton-federation-"));
const started = [];
// Starts a binary of zig-out/bin with env, collecting its stderr.
const start = (binary, env) => {
  const child = spawn(path.join(repo, "zig-out/bin", binary), { cwd: repo, stdio: ["ignore", "ignore", "pipe"], env: { ...process.env, PASEO_PASSWORD: "", ...env } });
  child.stderrText = "";
  child.stderr.on("data", (chunk) => (child.stderrText += chunk));
  child.on("error", fail);
  child.on("exit", (code) => fail(`${binary} exited with ${code}`));
  started.push(child);
  return child;
};
process.on("exit", () => {
  for (const child of started) if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
  fs.rmSync(scratch, { recursive: true, force: true });
});
const until = async (what, find, ms = 10000) => {
  for (const begin = Date.now(); ; await new Promise((r) => setTimeout(r, 100))) {
    const found = await find().catch(() => null);
    if (found) return found;
    if (Date.now() - begin > ms) throw new Error(`no ${what} after ${ms / 1000} s`);
  }
};

const echo = start("provider-echo", { ECHO_PORT: String(echoPort), ECHO_DB: path.join(scratch, "echo.db") });
// The peer's setup is its own, not one liton.setup.json may hold.
fs.writeFileSync(path.join(scratch, "peer.setup.json"), JSON.stringify({ remotes: [], transformers: ["attention"], presets: [], default_preset: "" }));
start("liton-daemon", { LITON_PORT: String(peerPort), LITON_DB: path.join(scratch, "peer.db"), LITON_SETUP: path.join(scratch, "peer.setup.json") });
const answering = (port) => until(`answer on ${port}`, () => fetch(`http://127.0.0.1:${port}/liton/v1/manifest`).then((r) => r.ok));
await answering(echoPort);
await answering(peerPort);
const interval = 1000;
// A setup as `liton setup` writes one, with a preset of its own.
const review = { name: "Review", snapshot: { version: 4, shell: "Tiling", collapsed: [], columns: [{ id: "column-1", size: 1, tabbed: false, active: "pane-1", panes: [{ id: "pane-1", widget: "chat", pinned: "", options: [] }] }] } };
const setup = { remotes: [{ name: "echo", url: `http://127.0.0.1:${echoPort}` }], transformers: ["attention", "needs-you"], presets: [review], default_preset: "Review" };
fs.writeFileSync(path.join(scratch, "liton.setup.json"), JSON.stringify(setup));
const main = start("liton-daemon", {
  LITON_PORT: String(mainPort),
  LITON_DB: path.join(scratch, "main.db"),
  LITON_SETUP: path.join(scratch, "liton.setup.json"),
  LITON_PROVIDERS: `peer=http://127.0.0.1:${peerPort}/,down=http://127.0.0.1:${downPort}`,
  LITON_PROVIDERS_INTERVAL_MS: String(interval),
});

const base = `http://127.0.0.1:${mainPort}/liton/v1`;
const post = async (what, body) => (await fetch(`${base}/${what}`, { method: "POST", body: JSON.stringify(body) })).json();
const call = (capability, request, provider) => post("call", { capability, request, ...(provider && { provider }) });
const poll = async (topics) => (await post("poll", { topics: topics.map((t) => (typeof t === "string" ? { capability: "chat.v1", topic: t, after: "" } : t)) })).topics;
const upstreamPolls = () => echo.stderrText.split("\n").filter((line) => line.endsWith("POST /liton/v1/poll")).length;
const step = async (name, run) => {
  check = name;
  await run();
};

try {
  const manifest = await until("manifest", () => fetch(`${base}/manifest`).then((r) => r.json()));
  await step("the manifest adds the remotes' providers under their names, and leaves out one that is down", () => {
    assert.deepEqual(manifest.providers.map((p) => p.id), ["mock", "echo/echo", "peer/mock"]);
    assert.deepEqual(manifest.providers[1].capabilities, [{ name: "chat", version: 1 }]);
  });
  await step("the manifest offers the setup's presets", () => assert.deepEqual(manifest.setup, { default_preset: "Review", presets: [review] }));
  await step("ListSessions merges every provider's sessions, named under their remotes", async () => {
    const sessions = await until("remote sessions", async () => {
      const listed = (await call("chat.v1", "ListSessions")).Ok.Sessions;
      return listed.some((s) => s.id === "echo/echo") && listed.some((s) => s.id === "peer/flaky-ci") && listed;
    });
    assert.ok(sessions.some((s) => s.id === "flaky-ci" && s.provider === "mock"));
    assert.ok(sessions.some((s) => s.id === "peer/flaky-ci" && s.provider === "peer/mock"));
    assert.ok(sessions.some((s) => s.id === "echo/hello" && s.provider === "echo/echo"));
    assert.equal(new Set(sessions.map((s) => s.id)).size, sessions.length);
    assert.ok((await call("chat.v1", "ListSessions", "peer/mock")).Ok.Sessions.every((s) => s.provider === "peer/mock"));
  });
  await step("calls to a remote's session reach it, as it names it", async () => {
    assert.deepEqual(await call("chat.v1", { SendMessage: { session_id: "echo/echo", text: "hi" } }), { Ok: "Accepted" });
    assert.deepEqual(await call("chat.v1", { SendMessage: { session_id: "peer/notes", text: "hi peer" } }, "peer/mock"), { Ok: "Accepted" });
    assert.equal((await call("chat.v1", { SendMessage: { session_id: "echo/hello", text: "hi" } })).Err.code, "Refused");
    assert.equal((await call("chat.v1", { SendMessage: { session_id: "echo/echo", text: "hi" } }, "mock")).Err.code, "NotFound");
    assert.equal((await call("chat.v1", { WatchSession: { session_id: "echo/echo", after: 0 } })).Ok.Entries[0].sequence, 1);
  });
  await step("a remote's timeline, workspaces and git are polled through it", async () => {
    const echoed = await until("the echo", async () => {
      const [timeline] = await poll(["timeline/echo/echo"]);
      return timeline.events.some((e) => e.Entry.event.AgentMessage?.text === "You said: hi") && timeline;
    });
    assert.equal(echoed.cursor, String(echoed.events.at(-1).Entry.sequence));
    const [again] = await poll([{ capability: "chat.v1", topic: "timeline/echo/echo", after: echoed.cursor }]);
    assert.deepEqual(again.events, []);
    const peerTopics = ["timeline/peer/flaky-ci", { capability: "workspace.git.v1", topic: "changes/peer/fix-auth/Uncommitted", after: "" }, { capability: "workspaces.v1", topic: "list", after: "" }];
    const [timeline, changes, list] = await until("the peer's topics", async () => {
      const topics = await poll(peerTopics);
      return topics[0].events.length && topics[1].events.length && topics[2].events[0].Listed.workspaces.some((w) => w.id.startsWith("peer/")) && topics;
    });
    assert.equal(timeline.events[0].Entry.sequence, 1);
    assert.equal(changes.events[0].Changes.workspace.Known.provider, "peer/mock");
    assert.ok(list.events[0].Listed.workspaces.find((w) => w.id === "peer/fix-auth").session_ids.includes("peer/fix-auth"));
    assert.equal((await poll([{ capability: "workspace.git.v1", topic: "changes/echo/echo/Uncommitted", after: "" }]))[0].error.code, "Unsupported");
    assert.ok((await call("attention.v1", "ListItems")).Ok.Items.some((item) => item.session_id === "echo/echo"));
  });
  await step("a transformer uses another's output: needs-you.v1 from attention.v1, across remotes", async () => {
    assert.deepEqual(manifest.transformers.map((t) => [t.id, t.offers.name, t.uses.map((u) => u.name)]), [["attention", "attention", ["chat"]], ["needs-you", "needs-you", ["attention"]]]);
    assert.deepEqual(manifest.topics.find((t) => t.capability.name === "needs-you").patterns, ["items"]);
    const [needing, attention] = await poll([{ capability: "needs-you.v1", topic: "items", after: "" }, { capability: "attention.v1", topic: "items", after: "" }]);
    const ids = needing.events[0].Items.map((i) => i.session_id);
    assert.ok(ids.includes("flaky-ci") && ids.includes("peer/flaky-ci"), ids.join());
    assert.deepEqual(needing.events[0].Items, attention.events[0].Items.filter((i) => i.state === "NeedsYou"));
    assert.deepEqual((await call("needs-you.v1", "ListItems")).Ok.Items.map((i) => i.session_id), ids);
    assert.equal((await poll([{ capability: "needs-you.v1", topic: "items", after: needing.cursor }]))[0].events.length, 0);
  });
  await step("a remote that is down fails only its own topics, and is logged once", async () => {
    const [down, local] = await poll(["timeline/down/s1", "timeline/fix-auth"]);
    assert.equal(down.error.code, "Unavailable");
    assert.ok(local.events.length > 0);
    assert.equal((await call("chat.v1", { SendMessage: { session_id: "down/s1", text: "hi" } })).Err.code, "Unavailable");
    assert.equal(main.stderrText.split("\n").filter((line) => line.includes("provider down")).length, 1);
  });
  let measured;
  await step("many clients' polls cost at most one upstream poll per interval", async () => {
    const topics = ["sessions", "timeline/echo/echo", "timeline/echo/hello"];
    const before = upstreamPolls();
    const begin = Date.now();
    await Promise.all(Array.from({ length: 10 }, () => poll(topics)));
    let clientPolls = 10;
    for (; Date.now() - begin < 2500; clientPolls++) {
      await Promise.all([poll(topics), poll(topics)]);
      clientPolls++;
      await new Promise((r) => setTimeout(r, 50));
    }
    const elapsed = Date.now() - begin;
    const upstream = upstreamPolls() - before;
    measured = `${clientPolls} client polls in ${elapsed} ms cost ${upstream} upstream polls`;
    assert.ok(upstream <= Math.floor(elapsed / interval) + 1, measured);
    assert.ok(upstream >= 1, measured);
  });
  console.log(`PASS providers outside the daemon (${measured})`);
  process.exit(0);
} catch (error) {
  fail(error);
}

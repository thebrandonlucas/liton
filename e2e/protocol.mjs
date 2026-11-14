// node e2e/protocol.mjs, after `zig build daemon cli`: checks /liton/v1 (see
// docs/protocol.md), and the liton CLI on it, against a daemon serving the
// mock provider, on a free port with a fresh database, and the setup `liton
// setup` evaluates of liton's Litonfile (roc on PATH).
import { execFile, spawn } from "node:child_process";
import assert from "node:assert/strict";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const port = await new Promise((resolve) => {
  const probe = net.createServer().listen(0, "127.0.0.1", () => {
    const { port } = probe.address();
    probe.close(() => resolve(port));
  });
});
let check = "liton setup evaluates liton's Litonfile";
const fail = (error) => {
  console.log(`FAIL ${check}: ${String(error?.message ?? error).split("\n")[0]}`);
  process.exit(1);
};
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "liton-protocol-"));
process.on("exit", () => fs.rmSync(scratch, { recursive: true, force: true }));
const cli = path.join(repo, "zig-out/bin/liton");
// The setup `liton setup` writes of a Litonfile, from a directory of its own: its text.
const evaluated = (litonfile, directory) =>
  new Promise((resolve, reject) => {
    fs.mkdirSync(directory);
    execFile(cli, ["setup", litonfile], { cwd: directory }, (error, _, stderr) =>
      error ? reject(new Error(`liton setup ${litonfile}: ${stderr}`)) : resolve(fs.readFileSync(path.join(directory, "liton.setup.json"), "utf8")),
    );
  });
const own = await evaluated(path.join(repo, "Litonfile.roc"), path.join(scratch, "own")).catch(fail);
check = "the daemon answers";
const daemon = spawn(path.join(repo, "zig-out/bin/liton-daemon"), {
  cwd: repo,
  stdio: ["ignore", "ignore", "inherit"],
  env: { ...process.env, PASEO_PASSWORD: "", LITON_HOST: "127.0.0.1", LITON_PORT: String(port), LITON_DB: path.join(scratch, "liton.db"), LITON_SETUP: path.join(scratch, "own/liton.setup.json") },
});
process.on("exit", () => {
  if (daemon.exitCode === null && daemon.signalCode === null) daemon.kill("SIGKILL");
});
daemon.on("error", fail);
daemon.on("exit", (code) => fail(`the daemon exited with ${code}`));

const base = `http://127.0.0.1:${port}/liton/v1`;
const post = async (what, body) => (await fetch(`${base}/${what}`, { method: "POST", body: JSON.stringify(body) })).json();
const call = (capability, request, provider) => post("call", { capability, request, ...(provider && { provider }) });
const cliOptions = { env: { ...process.env, LITON_URL: `http://127.0.0.1:${port}` } };
// liton run with args and, if given, input on stdin: its exit code, stdout and stderr.
const liton = (args, input) =>
  new Promise((resolve) => {
    const run = execFile(cli, args, cliOptions, (error, stdout, stderr) => resolve({ code: error?.code ?? 0, stdout, stderr }));
    run.stdin.end(input);
  });
const step = async (name, run) => {
  check = name;
  await run();
};

try {
  let manifest;
  for (const start = Date.now(); !manifest; await new Promise((r) => setTimeout(r, 50))) {
    manifest = await fetch(`${base}/manifest`).then((r) => r.json()).catch(() => null);
    if (Date.now() - start > 10000) throw new Error("no manifest after 10 s");
  }
  await step("the manifest lists the mock, attention as a transformer, and topics", () => {
    assert.equal(manifest.protocol, 1);
    assert.deepEqual(manifest.providers.map((p) => p.id), ["mock"]);
    assert.deepEqual(manifest.transformers.map((t) => [t.id, t.offers.name, t.uses[0].name]), [["attention", "attention", "chat"]]);
    assert.deepEqual(manifest.topics.find((t) => t.capability.name === "chat").patterns, ["sessions", "timeline/<session_id>", "importable"]);
    assert.ok(manifest.topics.find((t) => t.capability.name === "workspace.git").patterns.includes("file/<session_id>/<scope>/<path>"));
  });
  await step("each capability answers a call", async () => {
    const flaky = (await call("chat.v1", "ListSessions")).Ok.Sessions.find((s) => s.id === "flaky-ci");
    assert.deepEqual([flaky.model, flaky.workspace, flaky.branch, typeof flaky.updated], ["gpt-5-codex", { id: "main", directory: "/mock/liton" }, "main", "string"]);
    assert.equal((await call("chat.v1", "ListSessions", "mock")).Ok.Sessions.length, 3);
    assert.ok((await call("attention.v1", "ListItems")).Ok.Items.length > 0);
    assert.ok((await call("workspaces.v1", "ListWorkspaces")).Ok.Listed.workspaces.length > 0);
    assert.deepEqual(await call("chat.v1", { SendMessage: { session_id: "notes", text: "hi" } }), { Ok: "Accepted" });
  });
  await step("failed calls answer their error codes", async () => {
    const code = async (...args) => (await call(...args)).Err?.code;
    assert.equal(await code("chat.v1", { SendMessage: { session_id: "nope", text: "hi" } }), "NotFound");
    assert.equal(await code("chat.v1", "ListSessions", "elsewhere"), "NotFound");
    assert.equal(await code("chat.v1", "Bogus"), "BadRequest");
    assert.equal(await code("workspace.git.v1", "Anything"), "Unsupported");
    assert.equal(await code("tickets.v1", "ListTickets"), "Unsupported");
    assert.equal((await post("call", { nothing: 1 })).Err.code, "BadRequest");
  });
  await step("a poll answers each topic, and again after its cursors with nothing new", async () => {
    const topics = [
      { capability: "chat.v1", topic: "sessions", after: "" },
      { capability: "chat.v1", topic: "timeline/flaky-ci", after: "" },
      { capability: "attention.v1", topic: "items", after: "" },
      { capability: "workspaces.v1", topic: "list", after: "" },
      { capability: "workspace.git.v1", topic: "changes/fix-auth/Uncommitted", after: "" },
      { capability: "workspace.git.v1", topic: "file/fix-auth/Uncommitted/src%2FAuth.roc", after: "" },
      { capability: "chat.v1", topic: "importable", after: "" },
      { capability: "chat.v1", topic: "nothing", after: "" },
    ];
    const first = (await post("poll", { topics })).topics;
    assert.deepEqual(first.map((t) => t.events.length), [1, 6, 1, 1, 1, 1, 1, 0]);
    assert.equal(first[1].cursor, "6");
    assert.equal(first[4].events[0].Changes.changes.files[0].path, "src/Auth.roc");
    assert.deepEqual([first[5].events[0].File.path, first[5].events[0].File.hunks[0].old_start], ["src/Auth.roc", 40]);
    assert.deepEqual(first[6].events[0], { Importable: [] });
    assert.equal(first[7].error.code, "NotFound");
    const again = (await post("poll", { topics: first.map(({ capability, topic, cursor }) => ({ capability, topic, after: cursor })) })).topics;
    assert.deepEqual(again.map((t) => t.events.length), [0, 0, 0, 0, 0, 0, 0, 0]);
    assert.deepEqual(again.map((t) => t.cursor), first.map((t) => t.cursor));
  });
  await step("files.v1 lists a workspace's directories and reads its files, by session or workspace", async () => {
    assert.deepEqual(manifest.topics.find((t) => t.capability.name === "files").patterns, ["tree/<session_id>/<path>", "tree/workspace:<workspace_id>/<path>", "file/<session_id>/<path>", "file/workspace:<workspace_id>/<path>"]);
    assert.ok(manifest.providers[0].capabilities.some((c) => c.name === "files"));
    const files = (topic) => ({ capability: "files.v1", topic, after: "" });
    const topics = [files("tree/fix-auth/."), files("tree/workspace:main/src"), files("file/fix-auth/src%2FGenerated.roc"), files("file/workspace:main/assets%2Flogo.png"), files("file/fix-auth/AGENTS.md"), files("file/fix-auth/nope"), files("tree/nobody/."), files("tree/fix-auth")];
    const [root, src, long, logo, link, missing, nobody, nameless] = (await post("poll", { topics })).topics;
    assert.deepEqual(root.events[0].Tree.listing.Listed.map((e) => [e.name, e.kind]), [["README.md", "File"], ["AGENTS.md", "Symlink"], ["src", "Directory"], ["assets", "Directory"]]);
    assert.deepEqual(src.events[0].Tree.listing.Listed.map((e) => e.name), ["Auth.roc", "Generated.roc"]);
    const text = long.events[0].Contents.read.Text;
    assert.deepEqual([text.truncated, new TextEncoder().encode(text.text).length, text.size > 262144], [true, 262144, true]);
    assert.equal(logo.events[0].Contents.read.Binary.size, 4096);
    assert.ok(link.events[0].Contents.read.Text.text.startsWith("# liton"));
    assert.equal(missing.events[0].Contents.read.Unreadable, "no file nope");
    assert.equal(nobody.events[0].Tree.listing, "Unknown");
    assert.equal(nameless.error.code, "NotFound");
    const again = (await post("poll", { topics: [root, long].map(({ capability, topic, cursor }) => ({ capability, topic, after: cursor })) })).topics;
    assert.deepEqual(again.map((t) => t.events.length), [0, 0]);
  });
  await step("attention.v1's transformer sets an item aside until unsettled, and keeps it", async () => {
    const item = async () => (await call("attention.v1", "ListItems")).Ok.Items.find((i) => i.session_id === "fix-auth");
    const { signature } = await item();
    assert.deepEqual(await call("attention.v1", { Settle: { session_id: "fix-auth", signature } }), { Ok: "Accepted" });
    assert.equal((await item()).set_aside, "Settled");
    const [items] = (await post("poll", { topics: [{ capability: "attention.v1", topic: "items", after: "" }] })).topics;
    assert.equal(items.events[0].Items.find((i) => i.session_id === "fix-auth").set_aside, "Settled");
    assert.deepEqual(await call("attention.v1", { Snooze: { session_id: "fix-auth", signature, minutes: 5 } }), { Ok: "Accepted" });
    assert.equal((await item()).set_aside, "Snoozed");
    assert.deepEqual(await call("attention.v1", { Unsettle: { session_id: "fix-auth" } }), { Ok: "Accepted" });
    assert.equal((await item()).set_aside, "No");
    assert.equal((await call("attention.v1", { Settle: { session_id: "nope", signature } })).Err.code, "NotFound");
    assert.equal((await call("attention.v1", { Settle: {} })).Err.code, "BadRequest");
  });
  await step("Cancel stops a running session's turn, and leaves one that isn't running be", async () => {
    const events = async () => (await call("chat.v1", { WatchSession: { session_id: "fix-auth", after: 0 } })).Ok.Entries.map((e) => e.event);
    const pause = (ms) => new Promise((r) => setTimeout(r, ms));
    assert.deepEqual(await call("chat.v1", { SendMessage: { session_id: "fix-auth", text: "Take your time" } }), { Ok: "Accepted" });
    for (const start = Date.now(); (await events()).at(-1).StatusChanged !== "Running"; await pause(100)) {
      if (Date.now() - start > 3000) throw new Error("fix-auth isn't running after 3 s");
    }
    assert.deepEqual(await call("chat.v1", { Cancel: { session_id: "fix-auth" } }), { Ok: "Accepted" });
    const stopped = await events();
    assert.deepEqual(stopped.slice(-2), [{ AgentMessage: { text: "Stopped." } }, { StatusChanged: "Idle" }]);
    await pause(4200);
    assert.equal((await events()).length, stopped.length);
    assert.deepEqual(await call("chat.v1", { Cancel: { session_id: "fix-auth" } }), { Ok: "Accepted" });
    assert.equal((await events()).length, stopped.length);
    assert.equal((await call("chat.v1", { Cancel: { session_id: "nope" } })).Err.code, "NotFound");
  });
  await step("the old /api endpoints are gone", async () => {
    assert.equal((await fetch(`http://127.0.0.1:${port}/api/manifest`)).status, 404);
  });
  await step("the liton CLI prints the manifest and answers, and exits 1 on an error", async () => {
    assert.deepEqual(JSON.parse((await liton(["manifest"])).stdout), manifest);
    const listed = await liton(["call", "chat.v1", '"ListSessions"']);
    assert.equal(listed.code, 0);
    assert.ok(JSON.parse(listed.stdout).Ok.Sessions.some((s) => s.id === "flaky-ci"));
    const refused = await liton(["call", "chat.v1", "-"], '{"SendMessage":{"session_id":"nope","text":"hi"}}');
    assert.deepEqual([refused.code, JSON.parse(refused.stdout).Err.code, refused.stderr], [1, "NotFound", "liton: NotFound: no session nope\n"]);
    assert.equal((await liton(["call"])).code, 2);
  });
  await step("liton watch prints a timeline's events as lines a filter reads, until interrupted", async () => {
    const watch = spawn(cli, ["watch", "chat.v1", "timeline/flaky-ci", "--interval", "200"], cliOptions);
    const filter = spawn("grep", ["StatusChanged"], { stdio: ["pipe", "pipe", "inherit"] });
    watch.stdout.pipe(filter.stdin);
    let filtered = "";
    filter.stdout.on("data", (chunk) => (filtered += chunk));
    await new Promise((r) => setTimeout(r, 2000));
    watch.kill("SIGINT");
    await Promise.all([new Promise((r) => watch.on("exit", r)), new Promise((r) => filter.on("exit", r))]);
    assert.equal(watch.signalCode, "SIGINT");
    const lines = filtered.trim().split("\n").map((line) => JSON.parse(line));
    assert.deepEqual(lines.slice(0, 2).map((line) => line.Entry.sequence), [2, 6]);
  });
  await step("liton setup evaluates a Litonfile to the same JSON each time, which the manifest offers", async () => {
    assert.equal(await evaluated(path.join(repo, "Litonfile.roc"), path.join(scratch, "again")), own);
    const setup = JSON.parse(own);
    assert.deepEqual([setup.remotes, setup.transformers, setup.presets.map((p) => p.name), setup.default_preset], [[], ["attention"], ["Developer", "Inbox", "Tiling"], "Developer"]);
    assert.deepEqual(manifest.setup, { default_preset: setup.default_preset, presets: setup.presets, themes: setup.themes, default_theme: setup.default_theme });
    assert.deepEqual([setup.themes.map((t) => t.name), setup.default_theme], [["Pastoral", "Hypr", "Plain"], "Pastoral"]);
  });
  await step("a Litonfile that imports liton's changes parts of it", async () => {
    const team = JSON.parse(await evaluated(path.join(repo, "examples/litonfile-team"), path.join(scratch, "team")));
    assert.deepEqual([team.remotes.map((r) => r.name), team.transformers, team.presets.map((p) => p.name), team.default_preset], [["team"], [], ["Developer", "Tiling", "Review"], "Review"]);
  });
  console.log("PASS /liton/v1");
  process.exit(0);
} catch (error) {
  fail(error);
}

// node e2e/protocol.mjs, after `zig build daemon cli`: checks /liton/v1 (see
// docs/protocol.md), and the liton CLI on it, against a daemon serving the
// mock provider, on a free port with a fresh database, and `liton setup` on
// liton's Litonfile (roc on PATH).
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
  env: { ...process.env, PASEO_PASSWORD: "", LITON_HOST: "127.0.0.1", LITON_PORT: String(port), LITON_DB: path.join(scratch, "liton.db") },
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
    assert.ok((await call("chat.v1", "ListSessions")).Ok.Sessions.some((s) => s.id === "flaky-ci"));
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
  await step("liton setup evaluates a Litonfile to the same JSON each time", async () => {
    assert.equal(await evaluated(path.join(repo, "Litonfile.roc"), path.join(scratch, "again")), own);
    const setup = JSON.parse(own);
    assert.deepEqual([setup.remotes, setup.transformers, setup.presets.map((p) => p.name), setup.default_preset], [[], ["attention"], ["Developer", "Inbox", "Tiling"], "Developer"]);
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

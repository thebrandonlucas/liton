// node e2e/protocol.mjs, after `zig build daemon`: checks /liton/v1 (see
// docs/protocol.md) against a daemon serving the mock provider, on a free
// port with a fresh database.
import { spawn } from "node:child_process";
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
let check = "the daemon answers";
const fail = (error) => {
  console.log(`FAIL ${check}: ${String(error?.message ?? error).split("\n")[0]}`);
  process.exit(1);
};
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "liton-protocol-"));
const daemon = spawn(path.join(repo, "zig-out/bin/liton-daemon"), {
  cwd: repo,
  stdio: ["ignore", "ignore", "inherit"],
  env: { ...process.env, PASEO_PASSWORD: "", LITON_HOST: "127.0.0.1", LITON_PORT: String(port), LITON_DB: path.join(scratch, "liton.db") },
});
process.on("exit", () => {
  if (daemon.exitCode === null && daemon.signalCode === null) daemon.kill("SIGKILL");
  fs.rmSync(scratch, { recursive: true, force: true });
});
daemon.on("error", fail);
daemon.on("exit", (code) => fail(`the daemon exited with ${code}`));

const base = `http://127.0.0.1:${port}/liton/v1`;
const post = async (what, body) => (await fetch(`${base}/${what}`, { method: "POST", body: JSON.stringify(body) })).json();
const call = (capability, request, provider) => post("call", { capability, request, ...(provider && { provider }) });
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
    assert.deepEqual(manifest.topics.find((t) => t.capability.name === "chat").patterns, ["sessions", "timeline/<session_id>"]);
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
      { capability: "chat.v1", topic: "nothing", after: "" },
    ];
    const first = (await post("poll", { topics })).topics;
    assert.deepEqual(first.map((t) => t.events.length), [1, 6, 1, 1, 1, 0]);
    assert.equal(first[1].cursor, "6");
    assert.equal(first[4].events[0].Changes.changes.files[0].path, "src/Auth.roc");
    assert.equal(first[5].error.code, "NotFound");
    const again = (await post("poll", { topics: first.map(({ capability, topic, cursor }) => ({ capability, topic, after: cursor })) })).topics;
    assert.deepEqual(again.map((t) => t.events.length), [0, 0, 0, 0, 0, 0]);
    assert.deepEqual(again.map((t) => t.cursor), first.map((t) => t.cursor));
  });
  console.log("PASS /liton/v1");
  process.exit(0);
} catch (error) {
  fail(error);
}

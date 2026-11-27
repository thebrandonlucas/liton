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
const post = async (what, body) => (await fetch(`${base}/${what}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) })).json();
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
    assert.deepEqual(manifest.providers.map((p) => p.id), ["mock", "review", "rooms", "tickets", "hosts", "people"]);
    assert.deepEqual(manifest.transformers.map((t) => [t.id, t.offers.name, t.uses[0].name]), [["attention", "attention", "chat"]]);
    assert.deepEqual(manifest.topics.find((t) => t.capability.name === "chat").patterns, ["sessions", "timeline/<session_id>", "importable", "agents"]);
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
  await step("the mock's sessions carry a Goal / Done / Now summary once a turn ended", async () => {
    const sessions = async () => (await call("chat.v1", "ListSessions")).Ok.Sessions;
    const fixAuth = (await sessions()).find((s) => s.id === "fix-auth");
    assert.deepEqual([fixAuth.summary.goal, fixAuth.summary.done, fixAuth.summary.now, typeof fixAuth.summary.at], ["Logging in sends me back to /login.", "The redirect target is hard-coded to /login.", "Waiting for your next message.", "string"]);
    // notes, once its turn after the "hi" sent above is stopped: its first message is its goal.
    const notes = async () => (await sessions()).find((s) => s.id === "notes");
    for (const start = Date.now(); (await notes()).status !== "AwaitingPermission"; await new Promise((r) => setTimeout(r, 200))) {
      if (Date.now() - start > 10000) throw new Error("notes isn't waiting for an answer after 10 s");
    }
    assert.equal((await notes()).summary, undefined);
    assert.deepEqual(await call("chat.v1", { Cancel: { session_id: "notes" } }), { Ok: "Accepted" });
    const summary = (await notes()).summary;
    assert.deepEqual([summary.goal, summary.done, summary.now], ["hi", "Stopped.", "Waiting for your next message."]);
  });
  await step("failed calls answer their error codes", async () => {
    const code = async (...args) => (await call(...args)).Err?.code;
    assert.equal(await code("chat.v1", { SendMessage: { session_id: "nope", text: "hi" } }), "NotFound");
    assert.equal(await code("chat.v1", "ListSessions", "elsewhere"), "NotFound");
    assert.equal(await code("chat.v1", "Bogus"), "BadRequest");
    assert.equal(await code("workspace.git.v1", "Anything"), "Unsupported");
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
  await step("a cached poll answers the same from what the daemon keeps, with nothing to refresh, and a refresh answers", async () => {
    const topics = [{ capability: "chat.v1", topic: "sessions", after: "" }, { capability: "chat.v1", topic: "timeline/flaky-ci", after: "" }];
    const plain = await post("poll", { topics });
    const cached = await post("poll", { topics, cached: true });
    assert.equal(plain.refresh, undefined);
    assert.equal(cached.refresh, false);
    assert.deepEqual(cached.topics, plain.topics);
    assert.deepEqual(await post("refresh", {}), {});
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
  await step("attention.v1 lists what needs you, then the latest first, and Seen reads an item until it changes", async () => {
    const items = async () => (await call("attention.v1", "ListItems")).Ok.Items;
    const listed = await items();
    const rest = listed.filter((i) => i.state !== "NeedsYou").map((i) => i.updated);
    assert.deepEqual(rest, [...rest].sort().reverse());
    const shown = listed.find((i) => i.state !== "Working" && i.unread);
    const unread = async () => (await items()).find((i) => i.session_id === shown.session_id).unread;
    assert.deepEqual(await call("attention.v1", { Seen: [{ session_id: shown.session_id, through: shown.updated }] }), { Ok: "Accepted" });
    assert.equal(await unread(), false);
    assert.deepEqual(await call("attention.v1", { Seen: [{ session_id: shown.session_id, through: "" }] }), { Ok: "Accepted" });
    assert.equal(await unread(), true);
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
    assert.deepEqual(stopped.filter((e) => !e.TurnEnded).slice(-2), [{ AgentMessage: { text: "Stopped." } }, { StatusChanged: "Idle" }]);
    assert.ok(stopped.at(-2).TurnEnded?.started, "the stopped turn ends with when it started");
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
    assert.deepEqual([setup.remotes, setup.transformers, setup.presets.map((p) => p.name), setup.default_preset], [[], ["attention"], ["Developer", "Inbox", "Tiling", "Chat", "Rooms", "Review", "Board"], "Developer"]);
    assert.deepEqual(manifest.setup, { default_preset: setup.default_preset, presets: setup.presets, themes: setup.themes, default_theme: setup.default_theme, deck: setup.deck });
    assert.deepEqual(setup.deck, ["Developer", "Rooms", "Review", "Board"]);
    assert.deepEqual([setup.themes.map((t) => t.name), setup.default_theme], [["Pastoral", "Hypr", "Plain", "Neutral", "Sky", "Graphite"], "Pastoral"]);
  });
  await step("a Litonfile that imports liton's changes parts of it", async () => {
    const team = JSON.parse(await evaluated(path.join(repo, "examples/litonfile-team"), path.join(scratch, "team")));
    assert.deepEqual([team.remotes.map((r) => r.name), team.transformers, team.presets.map((p) => p.name), team.default_preset], [["team"], [], ["Developer", "Tiling", "Chat", "Rooms", "Review", "Board"], "Review"]);
  });
  await step("review.v1 keeps a context's threads, moves one to its lines, and sends the drafts to the agent as one message", async () => {
    const threads = async () => (await post("poll", { topics: [{ capability: "review.v1", topic: "threads/notes", after: "" }] })).topics[0].events[0].Threads;
    const lines = { path: "src/Auth.roc", scope: "File", side: "New", start_line: 9, end_line: 9, quote: "\tSession.start(redirect_to)" };
    assert.deepEqual(await call("review.v1", { AddComment: { context: "notes", place: { Lines: lines }, author: "Me", text: "Why here?" } }), { Ok: "Accepted" });
    assert.deepEqual(await call("review.v1", { AddComment: { context: "notes", place: "Overall", author: "Me", text: "Otherwise fine." } }), { Ok: "Accepted" });
    const [thread] = (await threads()).threads;
    assert.deepEqual([thread.id, thread.anchor.start_line, thread.outdated, thread.comments[0].state], ["t2", 3, false, "Draft"]);
    assert.equal((await call("review.v1", { EditComment: { context: "notes", comment_id: "c9", text: "" } })).Err.code, "NotFound");
    assert.deepEqual(await call("review.v1", { Send: { context: "notes", session_id: "notes" } }), { Ok: { Sent: { round: 1 } } });
    assert.equal((await call("review.v1", { Send: { context: "notes", session_id: "notes" } })).Err.code, "BadRequest");
    assert.equal((await call("review.v1", { DeleteComment: { context: "notes", comment_id: "c1" } })).Err.code, "BadRequest");
    assert.deepEqual((await threads()).threads[0].comments[0].state, { Sent: 1 });
    const sent = (await call("chat.v1", { WatchSession: { session_id: "notes", after: 0 } })).Ok.Entries.map((e) => e.event.UserMessage?.text ?? "").find((text) => text.startsWith("# Review"));
    assert.ok(sent.startsWith("# Review, round 1") && sent.includes("## src/Auth.roc:3\n\n```roc\n\tSession.start(redirect_to)\n```\n\nWhy here?") && sent.endsWith("## Overall\n\nOtherwise fine."), sent);
  });
  await step("tickets.v1 lists the mock's tickets, keeps what calls change, and links sessions by branch or by hand", async () => {
    const ticket = (id) => ({ capability: "tickets.v1", topic: `ticket/${id}`, after: "" });
    const links = async () => (await post("poll", { topics: [{ capability: "tickets.v1", topic: "links", after: "" }] })).topics[0].events[0].Links;
    const mine = { sources: [], kinds: ["Open", "Started"], assignee: "Me", label: "", text: "" };
    assert.deepEqual((await call("tickets.v1", { ListTickets: mine })).Ok.Listed.tickets.map((t) => t.key), ["LIT-12", "#7"]);
    assert.deepEqual(await links(), [{ session_id: "fix-auth", ticket_id: "LIT-12", inferred: true }]);
    assert.deepEqual(await call("tickets.v1", { Comment: { ticket_id: "mock/liton#9", body: "Rounds too." } }), { Ok: "Accepted" });
    assert.deepEqual(await call("tickets.v1", { SetStatus: { ticket_id: "mock/liton#7", status_id: "closed" } }), { Ok: "Accepted" });
    assert.deepEqual((await call("tickets.v1", { ListTickets: mine })).Ok.Listed.tickets.map((t) => t.key), ["LIT-12"]);
    const [nine, nope] = (await post("poll", { topics: [ticket("mock/liton#9"), ticket("nope")] })).topics;
    assert.deepEqual(nine.events[0].Ticket.comments.map((c) => [c.author.name, c.body]).at(-1), ["Ada", "Rounds too."]);
    assert.equal(nope.error.code, "NotFound");
    assert.equal((await call("tickets.v1", { SetStatus: { ticket_id: "mock/liton#7", status_id: "done" } })).Err.code, "BadRequest");
    assert.deepEqual(await call("tickets.v1", { Unlink: { session_id: "fix-auth" } }), { Ok: "Accepted" });
    assert.deepEqual(await call("tickets.v1", { Link: { session_id: "notes", ticket_id: "mock/liton#9" } }), { Ok: "Accepted" });
    assert.deepEqual(await links(), [{ session_id: "notes", ticket_id: "mock/liton#9", inferred: false }]);
    assert.equal((await call("tickets.v1", { Link: { session_id: "notes", ticket_id: "nope" } })).Err.code, "NotFound");
  });
  await step("tickets.v1 keeps the daemon's own projects and tickets, keyed by each project's prefix", async () => {
    const project = (await call("tickets.v1", { CreateProject: { name: "liton app", prefix: "" } })).Ok.Created;
    assert.equal(project.key, "LA");
    assert.equal((await call("tickets.v1", { CreateProject: { name: "Other", prefix: "la" } })).Err.message, "the prefix LA is liton app's");
    assert.equal((await call("tickets.v1", { CreateTicket: { source: project.id, title: " ", body: "", labels: [] } })).Err.message, "a ticket needs a title");
    const first = (await call("tickets.v1", { CreateTicket: { source: project.id, title: "Drop images in the composer", body: "Paste too.", labels: ["ui", " "] } })).Ok.Created;
    const second = (await call("tickets.v1", { CreateTicket: { source: project.id, title: "Group workspaces", body: "", labels: [] } })).Ok.Created;
    assert.deepEqual([first.key, second.key], ["LA-1", "LA-2"]);
    assert.deepEqual(await call("tickets.v1", { EditTicket: { ticket_id: first.id, title: "Drop and paste images", body: "In the composer.", labels: ["ui", "chat"] } }), { Ok: "Accepted" });
    assert.deepEqual(await call("tickets.v1", { SetStatus: { ticket_id: first.id, status_id: "in_review" } }), { Ok: "Accepted" });
    assert.deepEqual(await call("tickets.v1", { Comment: { ticket_id: first.id, body: "Done but for paste." } }), { Ok: "Accepted" });
    assert.equal((await call("tickets.v1", { SetStatus: { ticket_id: first.id, status_id: "closed" } })).Err.code, "BadRequest");
    const ours = { sources: [project.id], kinds: [], assignee: "Anyone", label: "", text: "" };
    const listed = (await call("tickets.v1", { ListTickets: ours })).Ok.Listed;
    const source = listed.sources.find((s) => s.id === project.id);
    assert.deepEqual([source.name, source.statuses.map((status) => status.name)], ["liton app", ["Backlog", "Todo", "In progress", "In review", "Done", "Canceled"]]);
    assert.deepEqual(listed.tickets.map((t) => [t.key, t.title, t.status.name, t.labels]), [["LA-1", "Drop and paste images", "In review", ["ui", "chat"]], ["LA-2", "Group workspaces", "Todo", []]]);
    const opened = (await post("poll", { topics: [{ capability: "tickets.v1", topic: `ticket/${first.id}`, after: "" }] })).topics[0].events[0].Ticket;
    assert.deepEqual([opened.body, opened.comments.map((c) => c.body)], ["In the composer.", ["Done but for paste."]]);
  });
  await step("chat.v1's ListHistory pages through the mock's sessions, archived ones too, and Unarchive lists one again", async () => {
    const history = async (request) => (await call("chat.v1", { ListHistory: request })).Ok.History;
    const listed = async () => (await call("chat.v1", "ListSessions")).Ok.Sessions.map((s) => s.id);
    const found = await history({ search: "README", limit: 50 });
    assert.deepEqual(found.sessions.map((s) => [s.id, typeof s.archived]), [["old-readme", "string"]]);
    assert.equal(found.next, undefined);
    const first = await history({ search: "", limit: 1 });
    const second = await history({ search: "", cursor: first.next, limit: 1 });
    assert.equal(first.sessions.length + second.sessions.length, 2);
    assert.notEqual(first.sessions[0].id, second.sessions[0].id);
    assert.ok(!(await listed()).includes("old-readme"));
    assert.deepEqual(await call("chat.v1", { Unarchive: { session_id: "old-readme" } }), { Ok: "Accepted" });
    assert.ok((await listed()).includes("old-readme"));
    assert.equal((await history({ search: "README", limit: 50 })).sessions[0].archived, undefined);
    assert.deepEqual(await call("chat.v1", { Archive: { session_id: "old-readme" } }), { Ok: "Accepted" });
    assert.ok(!(await listed()).includes("old-readme"));
  });
  await step("schedules.v1 runs the mock's schedules by the daemon's clock, pauses, resumes, runs at once and deletes them", async () => {
    const schedules = async () => (await post("poll", { topics: [{ capability: "schedules.v1", topic: "schedules", after: "" }] })).topics[0].events[0].Schedules;
    const runs = async (id) => (await post("poll", { topics: [{ capability: "schedules.v1", topic: `runs/${id}`, after: "" }] })).topics[0].events[0].Runs;
    assert.deepEqual((await schedules()).map((s) => [s.id, s.status]), [["nightly", "Active"]]);
    const draft = { name: "Once", prompt: "Say hi", cadence: { Every: 1000 }, target: { NewSession: { place: { Workspace: "main" }, agent: "claude", isolation: "Local", archive_on_finish: false } }, max_runs: 1 };
    const made = (await call("schedules.v1", { Create: draft })).Ok.Created.schedule_id;
    await new Promise((resolve) => setTimeout(resolve, 1500));
    assert.equal((await schedules()).find((s) => s.id === made).status, "Completed");
    const [ran] = await runs(made);
    assert.equal(ran.status, "Succeeded");
    assert.ok((await call("chat.v1", "ListSessions")).Ok.Sessions.some((s) => s.id === ran.session_id));
    assert.deepEqual(await call("schedules.v1", { Pause: { schedule_id: "nightly" } }), { Ok: "Accepted" });
    assert.equal((await schedules()).find((s) => s.id === "nightly").next_run, undefined);
    assert.deepEqual(await call("schedules.v1", { Resume: { schedule_id: "nightly" } }), { Ok: "Accepted" });
    assert.deepEqual(await call("schedules.v1", { RunOnce: { schedule_id: "nightly" } }), { Ok: "Accepted" });
    assert.equal((await call("schedules.v1", { Inspect: { schedule_id: "nightly" } })).Ok.Inspected.runs.length, 1);
    assert.equal((await call("schedules.v1", { Create: { ...draft, cadence: { Cron: { expression: "0 9 * * 1-5" } } } })).Ok.Rejected.length > 0, true);
    assert.deepEqual(await call("schedules.v1", { Delete: { schedule_id: made } }), { Ok: "Accepted" });
    assert.deepEqual((await schedules()).map((s) => s.id), ["nightly"]);
    assert.equal((await call("schedules.v1", { Pause: { schedule_id: "nope" } })).Err.code, "NotFound");
  });
  await step("Create makes a workspace of the mock's project and starts an agent in it, which its listing has", async () => {
    const made = (await call("workspaces.v1", { Create: { project_id: "liton", kind: "Worktree", branch: "docs" } })).Ok.Created.workspace_id;
    const started = (await call("chat.v1", { Create: { place: { Workspace: made }, agent: "codex", prompt: "Write the docs" } })).Ok.Started.session_id;
    const listed = (await call("workspaces.v1", "ListWorkspaces")).Ok.Listed.workspaces.find((w) => w.id === made);
    assert.deepEqual([listed.branch, listed.session_ids], [{ Branch: "docs" }, [started]]);
    const session = (await call("chat.v1", "ListSessions")).Ok.Sessions.find((s) => s.id === started);
    assert.deepEqual([session.title, session.status, session.workspace.id], ["Write the docs", "Running", made]);
    assert.equal((await call("chat.v1", { Create: { place: { Workspace: made }, agent: "gemini", prompt: "" } })).Ok.Rejected, "the mock provider starts no gemini agent");
    assert.equal((await call("workspaces.v1", { Create: { project_id: "nope", kind: "Checkout" } })).Err.code, "NotFound");
    const [agents] = (await post("poll", { topics: [{ capability: "chat.v1", topic: "agents", after: "" }] })).topics;
    assert.deepEqual(agents.events[0].Agents.map((a) => a.agent), ["claude", "codex"]);
  });
  await step("Configure switches a mock session's model, mode and thinking level of those its agent offers, Create starts one in them, and its usage grows with each message", async () => {
    const session = async (id) => (await call("chat.v1", "ListSessions")).Ok.Sessions.find((s) => s.id === id);
    const [agents] = (await post("poll", { topics: [{ capability: "chat.v1", topic: "agents", after: "" }] })).topics;
    const claude = agents.events[0].Agents.find((a) => a.agent === "claude");
    assert.deepEqual([claude.models.map((m) => m.id), claude.modes.map((m) => m.id), claude.default_mode], [["claude-sonnet-4-5", "claude-opus-4-1"], ["default", "acceptEdits", "plan", "bypassPermissions"], "default"]);
    const fresh = await session("fix-auth");
    assert.deepEqual([fresh.model, fresh.mode, fresh.thinking, fresh.modes.length], ["claude-sonnet-4-5", "default", "medium", 4]);
    assert.deepEqual(await call("chat.v1", { Configure: { session_id: "fix-auth", model: "claude-opus-4-1", mode: "plan" } }), { Ok: "Accepted" });
    const switched = await session("fix-auth");
    assert.deepEqual([switched.model, switched.mode, switched.thinking], ["claude-opus-4-1", "plan", "high"]);
    assert.deepEqual(await call("chat.v1", { Configure: { session_id: "fix-auth", thinking: "low" } }), { Ok: "Accepted" });
    assert.equal((await session("fix-auth")).thinking, "low");
    assert.equal((await call("chat.v1", { Configure: { session_id: "fix-auth", model: "gpt-5" } })).Ok.Rejected, "the mock's claude runs no model gpt-5");
    assert.equal((await call("chat.v1", { Configure: { session_id: "nope", mode: "plan" } })).Err.code, "NotFound");
    const used = (await session("fix-auth")).usage;
    assert.deepEqual([used.context_max, used.context_used > 0, used.cost_usd > 0], [200000, true, true]);
    assert.deepEqual(await call("chat.v1", { SendMessage: { session_id: "fix-auth", text: "And the tests", while_running: "Steer" } }), { Ok: "Accepted" });
    await new Promise((resolve) => setTimeout(resolve, 200));
    assert.ok((await session("fix-auth")).usage.context_used > used.context_used);
    const started = (await call("chat.v1", { Create: { place: { Workspace: "main" }, agent: "codex", mode: "read-only", thinking: "high", prompt: "" } })).Ok.Started.session_id;
    const made = await session(started);
    assert.deepEqual([made.model, made.mode, made.thinking], ["gpt-5-codex", "read-only", "high"]);
  });
  await step("a message's attachments go with it: the mock names them after its text, a 2 MB one is taken, and a call over 16 MB is refused", async () => {
    const started = (await call("chat.v1", { Create: { place: { Workspace: "main" }, agent: "claude", prompt: "" } })).Ok.Started.session_id;
    const attachments = [{ Image: { name: "shot.png", mime_type: "image/png", data: "iVBORw0KGgo=" } }, { Text: { name: "notes.md", text: "# Notes" } }];
    assert.deepEqual(await call("chat.v1", { SendMessage: { session_id: started, text: "Look", attachments } }), { Ok: "Accepted" });
    const said = async () => (await call("chat.v1", { WatchSession: { session_id: started, after: 0 } })).Ok.Entries.map((e) => e.event.UserMessage?.text).filter(Boolean);
    for (const start = Date.now(); !(await said()).includes("Look (attached: shot.png, notes.md)"); await new Promise((r) => setTimeout(r, 200))) {
      if (Date.now() - start > 5000) throw new Error(`no message naming its attachments: ${JSON.stringify(await said())}`);
    }
    assert.deepEqual(await call("chat.v1", { SendMessage: { session_id: started, text: "Two megabytes", attachments: [{ Text: { name: "two.txt", text: "x".repeat(2 * 1024 * 1024) } }] } }), { Ok: "Accepted" });
    const big = await fetch(`${base}/call`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ capability: "chat.v1", request: { SendMessage: { session_id: started, text: "big", attachments: [{ Text: { name: "big.txt", text: "x".repeat(17 * 1024 * 1024) } }] } } }) });
    assert.equal(big.status, 413);
  });
  await step("sessions, workspaces and projects are renamed, pinned and archived, and the listings show it", async () => {
    const workspaces = async () => (await call("workspaces.v1", "ListWorkspaces")).Ok.Listed;
    const sessions = async () => (await call("chat.v1", "ListSessions")).Ok.Sessions;
    assert.deepEqual(await call("chat.v1", { Rename: { session_id: "notes", title: "Notes" } }), { Ok: "Accepted" });
    assert.deepEqual(await call("workspaces.v1", { Rename: { workspace_id: "main", name: "Main" } }), { Ok: "Accepted" });
    assert.deepEqual(await call("workspaces.v1", { Pin: { workspace_id: "main", pinned: true } }), { Ok: "Accepted" });
    assert.deepEqual(await call("workspaces.v1", { RenameProject: { project_id: "liton", name: "Liton" } }), { Ok: "Accepted" });
    const main = (await workspaces()).workspaces.find((w) => w.id === "main");
    assert.deepEqual([(await sessions()).find((s) => s.id === "notes").title, main.name, main.pinned, (await workspaces()).projects[0].name], ["Notes", "Main", true, "Liton"]);
    assert.deepEqual(await call("chat.v1", { Archive: { session_id: "notes" } }), { Ok: "Accepted" });
    assert.ok(!(await sessions()).some((s) => s.id === "notes"));
    assert.ok(!(await workspaces()).workspaces.find((w) => w.id === "main").session_ids.includes("notes"));
    assert.deepEqual(await call("workspaces.v1", { Archive: { workspace_id: "fix-auth" } }), { Ok: "Accepted" });
    assert.ok(!(await workspaces()).workspaces.some((w) => w.id === "fix-auth"));
    assert.equal((await call("workspaces.v1", { Pin: { workspace_id: "nope", pinned: true } })).Err.code, "NotFound");
  });
  await step("rooms.v1 keeps the mock's rooms, where an agent a message mentions types and then answers in its thread", async () => {
    const room = (topic, after = "") => ({ capability: "rooms.v1", topic, after });
    const poll = async (...topics) => (await post("poll", { topics })).topics;
    const send = (room_id, text) => call("rooms.v1", { Send: { room_id, text, place: "TopLevel", mentions: [] } });
    const rooms = async () => (await call("rooms.v1", "ListRooms")).Ok.Rooms;
    assert.deepEqual((await rooms()).map((r) => [r.id, r.kind, r.joined]), [["general", "Channel", true], ["ideas", "Forum", true], ["releases", "Announce", false], ["scout", "Direct", true]]);
    const [listed, members, general, thread, missing] = await poll(room("rooms"), room("members/general"), room("messages/general"), room("thread/general/general-1"), room("messages/nope"));
    assert.deepEqual([listed.events[0].Rooms.length, members.events[0].Members.map((m) => m.id)], [4, ["you", "ada", "scout", "patch"]]);
    assert.deepEqual([general.events.map((e) => e.RoomEntry.sequence), thread.events.map((e) => e.RoomEntry.sequence)], [[1, 3, 5], [2, 4]]);
    assert.equal(missing.error.code, "NotFound");
    assert.deepEqual(await send("general", "@Scout run the tests"), { Ok: { Sent: { message_id: "general-6" } } });
    assert.deepEqual((await poll(room("messages/general", general.cursor)))[0].events.map((e) => e.RoomEntry.event.Posted.id), ["general-6"]);
    await new Promise((r) => setTimeout(r, 1800));
    const [answered, summary] = await poll(room("thread/general/general-6"), room("messages/general", "6"));
    assert.deepEqual(answered.events.map((e) => Object.keys(e.RoomEntry.event)[0]), ["Typing", "Posted"]);
    assert.equal(answered.events[1].RoomEntry.event.Posted.author, "scout");
    assert.equal(summary.events[0].RoomEntry.event.Threaded.replies, 1);
    assert.deepEqual(await call("rooms.v1", { React: { room_id: "general", message_id: "general-1", emoji: "+" } }), { Ok: "Accepted" });
    assert.deepEqual(await send("releases", "Hi"), { Ok: { Rejected: "join #releases first" } });
    assert.deepEqual(await call("rooms.v1", { Join: { room_id: "releases" } }), { Ok: "Accepted" });
    assert.deepEqual([(await rooms()).find((r) => r.id === "releases").joined, (await send("releases", "Hi")).Ok.Rejected], [true, "only Ada announces in #releases"]);
    assert.equal((await send("nope", "Hi")).Err.code, "NotFound");
  });
  console.log("PASS /liton/v1");
  process.exit(0);
} catch (error) {
  fail(error);
}

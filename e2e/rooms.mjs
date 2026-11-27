// node e2e/rooms.mjs, after `zig build daemon cli`: a box's rooms, kept in
// its tables, against a daemon on a free port with a fresh database that
// requires pairing: the setup's rooms at start, `liton room create` and
// `liton room list` from the owner's command line, and a staff member
// invited into a room, by token, talking there.
import { execFile, spawn, spawnSync } from "node:child_process";
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
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "liton-rooms-"));
fs.mkdirSync(path.join(scratch, "www"));
fs.writeFileSync(path.join(scratch, "www/index.html"), "<!doctype html><title>liton</title>");
const setup = {
  remotes: [], transformers: [], presets: [], default_preset: "", themes: [], default_theme: "", deck: [], owner: "",
  roles: [{ name: "staff", capabilities: ["rooms.v1"], presets: [], locked: true }],
  rooms: [{ name: "General", about: "Everyone", kind: "Channel", private: false, open: true }],
};
fs.writeFileSync(path.join(scratch, "liton.setup.json"), JSON.stringify(setup));
const database = path.join(scratch, "liton.db");
let daemon_process;
const start = () => {
  daemon_process = spawn(path.join(repo, "zig-out/bin/liton-daemon"), {
    cwd: repo,
    stdio: ["ignore", "ignore", "pipe"],
    env: { ...process.env, PASEO_PASSWORD: "", LITON_HOST: "127.0.0.1", LITON_PORT: String(port), LITON_DB: database, LITON_UI: path.join(scratch, "www"), LITON_SETUP: path.join(scratch, "liton.setup.json"), LITON_MOCK: "off", LITON_AUTH: "required" },
  });
  daemon_process.on("error", fail);
  daemon_process.on("exit", (code) => fail(`the daemon exited with ${code}`));
};
const stop = () =>
  new Promise((resolve) => {
    daemon_process.removeAllListeners("exit");
    daemon_process.on("exit", (code) => resolve(code));
    daemon_process.kill();
  });
process.on("exit", () => {
  if (daemon_process.exitCode === null && daemon_process.signalCode === null) daemon_process.kill("SIGKILL");
  fs.rmSync(scratch, { recursive: true, force: true });
});
const answering = async () => {
  for (const begin = Date.now(); ; await new Promise((r) => setTimeout(r, 100))) {
    if (await fetch(`http://127.0.0.1:${port}/ui/index.html`).then((r) => r.ok).catch(() => false)) return;
    if (Date.now() - begin > 10000) throw new Error("no answer after 10 s");
  }
};
const daemon = `http://127.0.0.1:${port}`;
// A program run with args and env: its exit code, stdout and stderr.
const run = (program, args, env = {}) =>
  new Promise((resolve) => {
    execFile(program, args, { env: { ...process.env, LITON_URL: daemon, LITON_DB: database, XDG_CONFIG_HOME: path.join(scratch, "config"), LITON_TOKEN: "", ...env } }, (error, stdout, stderr) =>
      resolve({ code: error?.code ?? 0, stdout, stderr }),
    );
  });
const liton = (args) => run(path.join(repo, "zig-out/bin/liton"), args);
const agent = (args, env = {}) => run("node", [path.join(repo, "examples/room-agent/agent.mjs"), ...args], env);
const step = async (name, test) => {
  check = name;
  await test();
};
// The JSON a route answers `body` with, sent with `token`.
const ask = (route, body, token) =>
  fetch(`${daemon}/liton/v1/${route}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
  }).then(async (r) => (r.ok ? r.json() : { status: r.status, text: await r.text() }));
const call = (token, capability, request) => ask("call", { capability, request }, token);
const rooms = (token, request) => call(token, "rooms.v1", request);
// The latest event of each topic polled.
const polled = async (token, ...topics) => (await ask("poll", { topics: topics.map(([capability, topic]) => ({ capability, topic, after: "" })) }, token)).topics.map((t) => t.events);
const posted = (events) => events.flatMap(({ RoomEntry }) => (RoomEntry?.event.Posted ? [RoomEntry.event.Posted.text] : []));

try {
  await step("a database from liton 0.1 is refused, saying to move it aside", async () => {
    const old = path.join(scratch, "old.db");
    const { DatabaseSync } = await import("node:sqlite");
    new DatabaseSync(old).exec("CREATE TABLE key_roles (role TEXT)");
    const refused = spawnSync(path.join(repo, "zig-out/bin/liton-daemon"), { env: { ...process.env, PASEO_PASSWORD: "", LITON_PORT: String(port), LITON_DB: old, LITON_UI: path.join(scratch, "www"), LITON_MOCK: "off" }, encoding: "utf8", timeout: 10000 });
    assert.equal(refused.status, 3);
    assert.match(refused.stderr, /is from liton 0\.1; 0\.2 starts fresh: move liton\.db aside/);
  });
  await step("a database from before passkeys starts: its devices are the owner's and still signed in, and liton pair's code pairs", async () => {
    const before = path.join(scratch, "before.db");
    const { DatabaseSync } = await import("node:sqlite");
    const { createHash } = await import("node:crypto");
    const secret = "5".repeat(64);
    const kept = new DatabaseSync(before);
    kept.exec("CREATE TABLE devices (id TEXT PRIMARY KEY, name TEXT NOT NULL, token_hash TEXT NOT NULL, created_at INTEGER NOT NULL, seen_at INTEGER NOT NULL); CREATE TABLE pairing_codes (code TEXT PRIMARY KEY, expires_at INTEGER NOT NULL); CREATE TABLE invites (id TEXT PRIMARY KEY, secret_hash TEXT NOT NULL UNIQUE, name TEXT NOT NULL, role TEXT NOT NULL, rooms TEXT NOT NULL, expires_at INTEGER NOT NULL)");
    kept.prepare("INSERT INTO devices VALUES (?, ?, ?, 0, 0)").run("d0", "Browser", createHash("sha256").update(secret).digest("hex"));
    kept.close();
    const migrated = spawn(path.join(repo, "zig-out/bin/liton-daemon"), { cwd: repo, stdio: ["ignore", "ignore", "inherit"], env: { ...process.env, PASEO_PASSWORD: "", LITON_HOST: "127.0.0.1", LITON_PORT: String(port), LITON_DB: before, LITON_UI: path.join(scratch, "www"), LITON_MOCK: "off", LITON_AUTH: "required" } });
    try {
      await answering();
      const listed = await fetch(`${daemon}/liton/v1/devices`, { headers: { Authorization: `Bearer d0.${secret}` } });
      assert.equal(listed.status, 200, await listed.clone().text());
      assert.deepEqual((await listed.json()).devices.map((device) => [device.name, device.current, device.expires_at]), [["Browser", true, 0]]);
      const code = (await run(path.join(repo, "zig-out/bin/liton"), ["pair"], { LITON_DB: before })).stdout.split("\n")[0];
      const paired = await ask("pair", { code, name: "Phone", token: true });
      assert.ok(paired.token, JSON.stringify(paired));
      const [people] = await polled(paired.token, ["people.v1", "people"]);
      assert.deepEqual(people.at(-1).People.people.map((person) => [person.name, person.devices]), [["Owner", 2]]);
    } finally {
      await new Promise((resolve) => {
        migrated.on("exit", resolve);
        migrated.kill();
      });
    }
  });
  start();
  await answering();
  let owner_token;
  await step("the command line pairs with the daemon, as the owner", async () => {
    const pairing = await liton(["pair"]);
    assert.equal(pairing.code, 0, pairing.stderr);
    const login = await liton(["login", pairing.stdout.split("\n")[0]]);
    assert.equal(login.code, 0, login.stderr);
    const kept = fs.readFileSync(path.join(scratch, "config/liton/tokens"), "utf8");
    owner_token = kept.split("\n").find((line) => line.startsWith(`${daemon} `)).split(" ")[1];
  });
  await step("the setup's rooms are there at start, and once after a restart, the daemon stopping by SIGTERM with 0", async () => {
    assert.equal((await liton(["room", "list"])).stdout, "general\tGeneral\tChannel\n");
    assert.equal(await stop(), 0);
    start();
    await answering();
    assert.equal((await liton(["room", "list"])).stdout, "general\tGeneral\tChannel\n");
  });
  await step("liton room create makes a room, refuses its id twice, and liton room list shows it", async () => {
    const created = await liton(["room", "create", "--type", "forum", "--private", "--about", "Orders and returns", "Front desk"]);
    assert.equal(created.code, 0, created.stderr);
    assert.equal(created.stdout.split("\n")[0], "front-desk");
    const again = await liton(["room", "create", "front desk"]);
    assert.equal(again.code, 1);
    assert.match(again.stderr, /there is a room front-desk already/);
    assert.equal((await liton(["room", "list"])).stdout, "general\tGeneral\tChannel\nfront-desk\tFront desk\tForum\tprivate\n");
  });
  let dana;
  let dana_id;
  await step("a staff member invited into a room redeems the invite for a token, posts there, and joins the open room to post in it", async () => {
    const invited = await liton(["invite", "--agent", "--role", "staff", "--rooms", "front-desk", "Dana"]);
    assert.equal(invited.code, 0, invited.stderr);
    const secret = new URL(invited.stdout.split("\n")[0]).hash.slice("#invite=".length);
    const redeemed = await ask("invite", { secret, token: true });
    assert.deepEqual([redeemed.person.name, redeemed.person.role], ["Dana", "staff"]);
    assert.equal((await ask("invite", { secret, token: true })).status, 401);
    dana = redeemed.token;
    dana_id = redeemed.person.id;
    const sent = await rooms(dana, { Send: { room_id: "front-desk", text: "The 3 o'clock delivery is in.", place: "TopLevel", mentions: [] } });
    assert.ok(sent.Ok.Sent.message_id);
    assert.deepEqual(await rooms(dana, { Send: { room_id: "general", text: "Hello?", place: "TopLevel", mentions: [] } }), { Ok: { Rejected: "you aren't a member of this room: ask one of its admins to add you" } });
    assert.deepEqual(await rooms(dana, { Join: { room_id: "general" } }), { Ok: "Accepted" });
    assert.ok((await rooms(dana, { Send: { room_id: "general", text: "Hello!", place: "TopLevel", mentions: [] } })).Ok.Sent);
  });
  await step("the room's members are its owner, an admin, and the staff member, whose message it holds, and a closed room refuses a join", async () => {
    const [members, messages] = await polled(dana, ["rooms.v1", "members/front-desk"], ["rooms.v1", "messages/front-desk"]);
    assert.deepEqual(members.at(-1).Members.map((member) => [member.name, member.role]), [["Owner", "Owner"], ["Dana", "Member"]]);
    assert.deepEqual(posted(messages), ["The 3 o'clock delivery is in."]);
    await liton(["room", "create", "Back office"]);
    assert.deepEqual(await rooms(dana, { Join: { room_id: "back-office" } }), { Ok: { Rejected: "the room is closed and you weren't invited: ask one of its admins to add you" } });
  });
  await step("a reply goes to its thread, the room shows the thread's summary, and a mention reaches the inbox of whom it names", async () => {
    const [root] = await polled(owner_token, ["rooms.v1", "messages/front-desk"]);
    const root_id = root.find((e) => e.RoomEntry?.event.Posted).RoomEntry.event.Posted.id;
    const reply = await rooms(owner_token, { Send: { room_id: "front-desk", text: "Thanks @Dana", place: { Reply: { root: root_id, parent: root_id } }, mentions: [dana_id] } });
    assert.ok(reply.Ok.Sent, JSON.stringify(reply));
    const [thread, top, inbox] = await polled(dana, ["rooms.v1", `thread/front-desk/${root_id}`], ["rooms.v1", "messages/front-desk"], ["rooms.v1", "inbox"]);
    assert.deepEqual(posted(thread), ["Thanks @Dana"]);
    assert.deepEqual(top.at(-1).RoomEntry.event.Threaded.replies, 1);
    assert.deepEqual(posted(inbox), ["Thanks @Dana"]);
    assert.deepEqual(posted((await polled(owner_token, ["rooms.v1", "inbox"]))[0]), []);
  });
  await step("a reaction is added and taken back once", async () => {
    const [top] = await polled(dana, ["rooms.v1", "messages/front-desk"]);
    const id = top.find((e) => e.RoomEntry?.event.Posted).RoomEntry.event.Posted.id;
    for (const request of [{ React: { room_id: "front-desk", message_id: id, emoji: "+" } }, { React: { room_id: "front-desk", message_id: id, emoji: "+" } }, { Unreact: { room_id: "front-desk", message_id: id, emoji: "+" } }]) {
      assert.deepEqual(await rooms(dana, request), { Ok: "Accepted" });
    }
    const [after] = await polled(dana, ["rooms.v1", "messages/front-desk"]);
    assert.deepEqual(after.flatMap((e) => (e.RoomEntry?.event.Reacted ? [e.RoomEntry.event.Reacted.added] : [])), [true, false]);
  });
  await step("an agent joins by its invite's link and posts with its token (examples/room-agent)", async () => {
    const invited = await liton(["invite", "--agent", "--role", "staff", "--rooms", "front-desk", "Dispatch bot"]);
    const file = path.join(scratch, "agent-token");
    const joined = await agent(["join", invited.stdout.split("\n")[0], file]);
    assert.equal(joined.code, 0, joined.stderr);
    assert.equal((fs.statSync(file).mode & 0o777).toString(8), "600");
    const sent = await agent(["send", "front-desk", "On my way."], { LITON_TOKEN_FILE: file });
    assert.equal(sent.code, 0, sent.stdout + sent.stderr);
    const refused = await agent(["send", "general", "Hello?"], { LITON_TOKEN_FILE: file });
    assert.equal(refused.code, 1);
    assert.match(refused.stdout, /you aren't a member of this room/);
  });
  await step("an operator renames a person and takes them out of a room, a staff member renames only themselves, and the audit shows who did what", async () => {
    assert.deepEqual(await call(owner_token, "people.v1", { Rename: { person: dana_id, name: "Dana S." } }), { Ok: "Accepted" });
    const [people] = await polled(owner_token, ["people.v1", "people"]);
    const owner_id = people.at(-1).People.people.find((person) => person.owner).id;
    assert.deepEqual(await call(dana, "people.v1", { Rename: { person: owner_id, name: "Eve" } }), { Err: { code: "Refused", message: "this device's role, staff, can't use people.v1" } });
    assert.deepEqual(await call(owner_token, "people.v1", { RemoveMember: { room: "general", person: dana_id } }), { Ok: "Accepted" });
    const [members] = await polled(owner_token, ["rooms.v1", "members/general"]);
    assert.equal(members.at(-1).Members.some((member) => member.id === dana_id), false);
    const [audit] = await polled(owner_token, ["people.v1", "audit"]);
    const actions = audit.at(-1).Audit.map((entry) => entry.action);
    for (const action of ["invite.made", "invite.redeemed", "room.made", "member.joined", "person.renamed", "member.removed"]) assert.ok(actions.includes(action), action);
    assert.equal(audit.at(-1).Audit.at(-1).person, "Owner");
  });
  await step("a staff member can't create rooms", async () => {
    const answer = await call(dana, "people.v1", { CreateRoom: { name: "Back room", about: "", kind: "Channel", private: false } });
    assert.ok(answer.Err, "the call is refused");
    assert.equal((await liton(["room", "list"])).stdout.includes("back-room"), false);
  });
  await step("removing a person signs them out and takes them out of their rooms, and the owner stays", async () => {
    const [people] = await polled(owner_token, ["people.v1", "people"]);
    const owner_id = people.at(-1).People.people.find((person) => person.owner).id;
    assert.deepEqual(await call(owner_token, "people.v1", { Remove: { person: owner_id } }), { Ok: { Rejected: "the owner can't be removed" } });
    assert.deepEqual(await call(owner_token, "people.v1", { Remove: { person: dana_id } }), { Ok: "Accepted" });
    assert.equal((await ask("poll", { topics: [] }, dana)).status, 401);
    const [members] = await polled(owner_token, ["rooms.v1", "members/front-desk"]);
    assert.deepEqual(members.at(-1).Members.map((member) => member.name), ["Owner", "Dispatch bot"]);
  });
} catch (error) {
  fail(error);
}
console.log("ok: a box's rooms");
process.exit(0);

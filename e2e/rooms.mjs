// node e2e/rooms.mjs, after `zig build daemon cli`: a box's rooms made by
// its operator, against a daemon on a free port with a fresh database that
// requires pairing: the setup's rooms at start, `liton room create` and
// `liton room list` from a command line with no key of its own, and a
// staff key invited into a room posting there (examples/room-agent).
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
let check = "the daemon answers";
const fail = (error) => {
  console.log(`FAIL ${check}: ${String(error?.message ?? error).split("\n")[0]}`);
  process.exit(1);
};
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "liton-rooms-"));
fs.mkdirSync(path.join(scratch, "www"));
fs.writeFileSync(path.join(scratch, "www/index.html"), "<!doctype html><title>liton</title>");
const owner = "a".repeat(64);
const setup = {
  remotes: [], transformers: [], presets: [], default_preset: "", themes: [], default_theme: "", deck: [], owner,
  roles: [{ name: "staff", capabilities: ["rooms.v1"], presets: [], locked: true }],
  rooms: [{ name: "General", about: "Everyone", kind: "Channel", private: false }],
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

try {
  start();
  await answering();
  await step("the command line pairs with the daemon", async () => {
    const pairing = await liton(["pair"]);
    assert.equal(pairing.code, 0, pairing.stderr);
    const login = await liton(["login", pairing.stdout.split("\n")[0]]);
    assert.equal(login.code, 0, login.stderr);
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
    assert.match(again.stderr, /duplicate: the room front-desk exists/);
    assert.equal((await liton(["room", "list"])).stdout, "general\tGeneral\tChannel\nfront-desk\tFront desk\tForum\tprivate\n");
  });
  let keys;
  let dana;
  await step("a staff key invited into the room posts there, and not in a room it isn't in", async () => {
    const invited = await liton(["invite", "--role", "staff", "--rooms", "front-desk", "Dana"]);
    assert.equal(invited.code, 0, invited.stderr);
    keys = path.join(scratch, "dana");
    const joined = await agent(["join", invited.stdout.split("\n")[0], keys]);
    assert.equal(joined.code, 0, joined.stderr);
    dana = joined.stdout.match(/key ([0-9a-f]{64})/)[1];
    const env = { LITON_KEY_FILE: path.join(keys, "key"), LITON_TOKEN_FILE: path.join(keys, "token") };
    const sent = await agent(["send", "front-desk", "The 3 o'clock delivery is in."], env);
    assert.equal(sent.code, 0, sent.stdout + sent.stderr);
    assert.ok(JSON.parse(sent.stdout).Ok.Sent.message_id);
    const refused = await agent(["send", "general", "Hello?"], env);
    assert.equal(refused.code, 1);
    assert.match(refused.stdout, /only the room's members speak in it/);
  });
  await step("the room's members are the owner, its admin, and the staff key, whose message it holds", async () => {
    const token = fs.readFileSync(path.join(keys, "token"), "utf8").trim();
    const polled = await fetch(`${daemon}/liton/v1/poll`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({ topics: [{ capability: "rooms.v1", topic: "members/front-desk", after: "" }, { capability: "rooms.v1", topic: "messages/front-desk", after: "" }] }),
    }).then((r) => r.json());
    const [members, messages] = polled.topics.map((topic) => topic.events);
    assert.deepEqual(members.at(-1).Members.map((member) => [member.name, member.role]), [["aaaaaaaa", "Admin"], ["Dana", "Member"]]);
    assert.deepEqual(messages.flatMap(({ RoomEntry }) => (RoomEntry?.event.Posted ? [RoomEntry.event.Posted.text] : [])), ["The 3 o'clock delivery is in."]);
  });
  await step("the devices answer gives each device's key, as a setup's owner names one", async () => {
    const kept = fs.readFileSync(path.join(scratch, "config/liton/tokens"), "utf8");
    const token = kept.split("\n").find((line) => line.startsWith(`${daemon} `)).split(" ")[1];
    const { devices } = await fetch(`${daemon}/liton/v1/devices`, { headers: { Authorization: `Bearer ${token}` } }).then((r) => r.json());
    assert.deepEqual(devices.map((device) => [device.name, device.pubkey]), [["liton command line", ""], ["Dana", dana]]);
  });
  await step("a staff key can't create rooms", async () => {
    const token = fs.readFileSync(path.join(keys, "token"), "utf8").trim();
    const answer = await fetch(`${daemon}/liton/v1/call`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({ capability: "people.v1", request: { CreateRoom: { name: "Back office", about: "", kind: "Channel", private: false } } }),
    });
    assert.ok((await answer.json()).Err, "the call is refused");
    assert.equal((await liton(["room", "list"])).stdout.includes("back-office"), false);
  });
} catch (error) {
  fail(error);
}
console.log("ok: a box's rooms");
process.exit(0);

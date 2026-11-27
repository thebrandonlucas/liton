// node e2e/invites.mjs CDP, after `zig build daemon cli`: a box's invites,
// against a daemon on a free port with a fresh database that requires
// pairing, its site LITON_RP_ID=localhost: a person invited makes a passkey
// in headless Chrome (e2e/passkey-page.mjs) and talks in the invite's room;
// an agent's invite gives a token alone, which the room agent example posts
// with; and `liton people relink` gives a person a passkey again.
// CDP is roc-signals's DevTools client, which `zig build e2e` passes; CHROME
// names the browser (default `chromium` on PATH).
import { execFile, spawn } from "node:child_process";
import assert from "node:assert/strict";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { opened } from "./passkey-page.mjs";

const { launch } = await import(pathToFileURL(process.argv[2]).href);

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const port = await new Promise((resolve) => {
  const probe = net.createServer().listen(0, "127.0.0.1", () => {
    const { port } = probe.address();
    probe.close(() => resolve(port));
  });
});
let check = "the daemon answers";
const fail = (error) => {
  console.log(`FAIL ${check}: ${String(error?.message ?? error).split("\n").slice(0, 6).join(" ")}`);
  process.exit(1);
};
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "liton-invites-"));
fs.mkdirSync(path.join(scratch, "www"));
fs.writeFileSync(path.join(scratch, "www/index.html"), "<!doctype html><title>liton</title>");
const setup = {
  remotes: [], transformers: [], presets: [], default_preset: "", themes: [], default_theme: "", deck: [],
  roles: [{ name: "staff", capabilities: ["rooms.v1"], presets: [], locked: true }, { name: "agent", capabilities: ["rooms.v1"], presets: [], locked: true }],
  rooms: [{ name: "Front desk", about: "", kind: "Channel", private: false, open: false }],
};
fs.writeFileSync(path.join(scratch, "liton.setup.json"), JSON.stringify(setup));
const database = path.join(scratch, "liton.db");
const daemon_process = spawn(path.join(repo, "zig-out/bin/liton-daemon"), {
  cwd: repo,
  stdio: ["ignore", "ignore", "inherit"],
  env: { ...process.env, PASEO_PASSWORD: "", LITON_HOST: "127.0.0.1", LITON_PORT: String(port), LITON_DB: database, LITON_UI: path.join(scratch, "www"), LITON_SETUP: path.join(scratch, "liton.setup.json"), LITON_MOCK: "off", LITON_AUTH: "required", LITON_RP_ID: "localhost", LITON_VERIFY: path.join(repo, "zig-out/bin/liton-verify") },
});
daemon_process.on("error", fail);
daemon_process.on("exit", (code) => fail(`the daemon exited with ${code}`));
process.on("exit", () => {
  if (daemon_process.exitCode === null && daemon_process.signalCode === null) daemon_process.kill("SIGKILL");
  fs.rmSync(scratch, { recursive: true, force: true });
});
const daemon = `http://localhost:${port}`;
const run = (program, args, env = {}) =>
  new Promise((resolve) => {
    execFile(program, args, { env: { ...process.env, LITON_URL: daemon, LITON_DB: database, XDG_CONFIG_HOME: path.join(scratch, "config"), LITON_TOKEN: "", ...env } }, (error, stdout, stderr) => resolve({ code: error?.code ?? 0, stdout, stderr }));
  });
const liton = (args) => run(path.join(repo, "zig-out/bin/liton"), args);
const agent = (args, env = {}) => run("node", [path.join(repo, "examples/room-agent/agent.mjs"), ...args], env);
const step = async (name, test) => {
  check = name;
  await test();
};
const secret_of = (printed) => new URL(printed.split("\n")[0].split("\t").at(-1)).hash.slice("#invite=".length);
const redeem = (body) => fetch(`${daemon}/liton/v1/invite`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });

try {
  for (const begin = Date.now(); !(await fetch(`${daemon}/ui/index.html`).then((r) => r.ok).catch(() => false)); await new Promise((r) => setTimeout(r, 100))) {
    if (Date.now() - begin > 10000) throw new Error("no answer after 10 s");
  }
  await step("the owner's command line pairs", async () => {
    const pairing = await liton(["pair"]);
    assert.equal((await liton(["login", pairing.stdout.split("\n")[0]])).code, 0);
  });
  const browser = await launch({ executablePath: process.env.CHROME || "chromium" });
  const laptop = await opened(browser, daemon);
  const phone = await opened(await browser.createBrowserContext(), daemon);
  const poll = (page, topics) => page.evaluate(`liton.post("poll", { topics: ${JSON.stringify(topics.map(([capability, topic]) => ({ capability, topic, after: "" })))} })`);
  let invited;
  await step("a person's invite is redeemed by making a passkey, which signs them in, a member of its room, where they post", async () => {
    invited = (await liton(["invite", "--role", "staff", "--rooms", "front-desk", "Dana"])).stdout;
    const secret = secret_of(invited);
    const redeemed = await laptop.evaluate(`liton.redeem(${JSON.stringify(secret)}, "Laptop")`);
    assert.equal(redeemed.status, 200, redeemed.body);
    assert.deepEqual([redeemed.body.person.name, redeemed.body.person.role], ["Dana", "staff"]);
    const polled = await poll(laptop, [["rooms.v1", "members/front-desk"]]);
    assert.deepEqual(polled.body.topics[0].events.at(-1).Members.map((member) => [member.name, member.role]), [["Owner", "Owner"], ["Dana", "Member"]]);
    const sent = await laptop.evaluate(`liton.post("call", { capability: "rooms.v1", request: { Send: { room_id: "front-desk", text: "Hello from Dana", place: "TopLevel", mentions: [] } } })`);
    assert.ok(sent.body.Ok.Sent, JSON.stringify(sent.body));
  });
  await step("an invite is used once, and a person's isn't redeemed for a token", async () => {
    assert.equal((await redeem({ secret: secret_of(invited) })).status, 401);
    const another = (await liton(["invite", "--role", "staff", "Eli"])).stdout;
    const refused = await redeem({ secret: secret_of(another), token: true });
    assert.equal(refused.status, 400);
    assert.match(await refused.text(), /open its link in a browser/);
  });
  let token_file;
  await step("an agent's invite gives a token alone, as the room agent example keeps it, and the agent posts with it", async () => {
    const invite = (await liton(["invite", "--agent", "--role", "agent", "--rooms", "front-desk", "Dispatch bot"])).stdout;
    assert.equal((await redeem({ secret: secret_of(invite) })).status, 400);
    token_file = path.join(scratch, "bot-token");
    const joined = await agent(["join", invite.split("\n")[0], token_file]);
    assert.equal(joined.code, 0, joined.stderr);
    const sent = await agent(["send", "front-desk", "On it."], { LITON_TOKEN_FILE: token_file });
    assert.equal(sent.code, 0, sent.stdout + sent.stderr);
    const polled = await poll(laptop, [["rooms.v1", "members/front-desk"]]);
    const members = polled.body.topics[0].events.at(-1).Members;
    assert.deepEqual(members.map((member) => [member.name, member.kind === "Person"]), [["Owner", true], ["Dana", true], ["Dispatch bot", false]]);
    assert.ok(members[2].kind.Agent, "the bot is an agent");
  });
  await step("liton people relink gives a person an invite to make a passkey again, signing in as them, and --all lists everyone but the owner", async () => {
    const relinked = await liton(["people", "relink", "Dana"]);
    assert.equal(relinked.code, 0, relinked.stderr);
    assert.match(relinked.stdout, /^Dana\thttp/);
    const redeemed = await phone.evaluate(`liton.redeem(${JSON.stringify(secret_of(relinked.stdout))}, "Phone")`);
    assert.equal(redeemed.status, 200, redeemed.body);
    assert.equal(redeemed.body.person.name, "Dana");
    const listed = await phone.evaluate(`fetch("/liton/v1/passkeys").then((r) => r.json())`);
    assert.deepEqual(listed.passkeys.map((passkey) => passkey.name), ["Laptop", "Phone"]);
    const all = await liton(["people", "relink", "--all"]);
    assert.deepEqual(all.stdout.trim().split("\n").map((line) => line.split("\t")[0]), ["Dana", "Dispatch bot"]);
  });
  await browser.close();
} catch (error) {
  fail(error);
}
console.log("ok: invites");
process.exit(0);

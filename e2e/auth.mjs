// node e2e/auth.mjs, after `zig build daemon cli`: checks client
// authentication (docs/protocol.md, Authentication) against daemons on free
// ports with fresh databases: one that requires pairing (LITON_AUTH=required),
// one on loopback that doesn't unless a proxy forwarded the request, and one
// federating the first with the token it was paired with.
import { execFile, spawn } from "node:child_process";
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
const [requiredPort, loopbackPort, federatingPort] = [await freePort(), await freePort(), await freePort()];
let check = "the daemons answer";
const fail = (error) => {
  console.log(`FAIL ${check}: ${String(error?.message ?? error).split("\n")[0]}`);
  process.exit(1);
};
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "liton-auth-"));
// The UI the daemons serve: a page, public as it holds no secrets.
fs.mkdirSync(path.join(scratch, "www"));
fs.writeFileSync(path.join(scratch, "www/index.html"), "<!doctype html><title>liton</title>");
fs.writeFileSync(path.join(scratch, "empty.setup.json"), JSON.stringify({ remotes: [], transformers: [], presets: [], default_preset: "" }));
const started = [];
const start = (env) => {
  const child = spawn(path.join(repo, "zig-out/bin/liton-daemon"), {
    cwd: repo,
    stdio: ["ignore", "ignore", "pipe"],
    env: { ...process.env, PASEO_PASSWORD: "", LITON_HOST: "127.0.0.1", LITON_UI: path.join(scratch, "www"), LITON_SETUP: path.join(scratch, "empty.setup.json"), ...env },
  });
  child.stderrText = "";
  child.stderr.on("data", (chunk) => (child.stderrText += chunk));
  child.on("error", fail);
  child.on("exit", (code) => fail(`the daemon exited with ${code}`));
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
const database = path.join(scratch, "required.db");
const required = start({ LITON_PORT: String(requiredPort), LITON_DB: database, LITON_AUTH: "required" });
start({ LITON_PORT: String(loopbackPort), LITON_DB: path.join(scratch, "loopback.db") });
const answering = (port) => until(`answer on ${port}`, () => fetch(`http://127.0.0.1:${port}/ui/index.html`).then((r) => r.ok));
await answering(requiredPort).catch(fail);
await answering(loopbackPort).catch(fail);

const daemon = `http://127.0.0.1:${requiredPort}`;
const config = path.join(scratch, "config");
// liton run with args: its exit code, stdout and stderr.
const liton = (args, env = {}) =>
  new Promise((resolve) => {
    execFile(path.join(repo, "zig-out/bin/liton"), args, { env: { ...process.env, LITON_URL: daemon, LITON_DB: database, XDG_CONFIG_HOME: config, LITON_TOKEN: "", ...env } }, (error, stdout, stderr) =>
      resolve({ code: error?.code ?? 0, stdout, stderr }),
    );
  });
const code = async () => {
  const made = await liton(["pair"]);
  assert.equal(made.code, 0, made.stderr);
  const [first] = made.stdout.split("\n");
  assert.match(first, /^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/);
  assert.ok(made.stdout.includes(`${daemon}/ui/index.html#pair=${first}`));
  return first;
};
const ask = (route, { method = "GET", body, headers = {} } = {}) =>
  fetch(`${daemon}/liton/v1/${route}`, { method, headers: { ...(body !== undefined && { "Content-Type": "application/json" }), ...headers }, body: body === undefined ? undefined : JSON.stringify(body) });
const step = async (name, run) => {
  check = name;
  await run();
};

try {
  await step("every /liton/v1 route but pair answers 401 to a device not paired, and /ui is public", async () => {
    for (const [route, options] of [["manifest"], ["call", { method: "POST", body: { capability: "chat.v1", request: "ListSessions" } }], ["poll", { method: "POST", body: { topics: [] } }], ["devices"], ["devices/code", { method: "POST", body: {} }], ["devices/revoke", { method: "POST", body: { id: "x" } }]]) {
      const answer = await ask(route, options);
      assert.equal(answer.status, 401, route);
      assert.equal(answer.headers.get("www-authenticate"), 'Bearer realm="liton"');
    }
    assert.equal((await ask("manifest", { headers: { Authorization: "Bearer 0011223344556677.00" } })).status, 401);
    assert.equal((await fetch(`${daemon}/ui/index.html`)).status, 200);
  });
  let cookie;
  let browserCode;
  await step("a browser pairs with a code liton pair makes, once, and gets its token as an HttpOnly cookie only", async () => {
    browserCode = await code();
    assert.equal((await ask("pair", { method: "POST", body: { code: "AAAA-AAAA", name: "Browser" } })).status, 401);
    const paired = await ask("pair", { method: "POST", body: { code: browserCode.toLowerCase().replace("-", " "), name: "Browser" }, headers: { "X-Forwarded-Proto": "https" } });
    assert.equal(paired.status, 200);
    const answer = await paired.json();
    assert.deepEqual(Object.keys(answer), ["device"]);
    assert.equal(answer.device.name, "Browser");
    const set = paired.headers.get("set-cookie");
    assert.match(set, /^liton_token=[0-9a-f]{16}\.[0-9a-f]{64}; Path=\/; Max-Age=\d+; HttpOnly; SameSite=Strict; Secure$/);
    cookie = set.split(";")[0];
    assert.equal((await ask("manifest", { headers: { Cookie: cookie } })).status, 200);
    assert.equal((await ask("pair", { method: "POST", body: { code: browserCode } })).status, 401);
  });
  await step("the CLI pairs with liton login, keeps its token readable by its owner alone, and sends it", async () => {
    assert.equal((await liton(["manifest"])).code, 2);
    const login = await liton(["login", await code()]);
    assert.equal(login.code, 0, login.stderr);
    const tokens = path.join(config, "liton/tokens");
    assert.equal(fs.statSync(tokens).mode & 0o777, 0o600);
    assert.match(fs.readFileSync(tokens, "utf8"), new RegExp(`^${daemon} [0-9a-f]{16}\\.[0-9a-f]{64}\\n$`));
    const manifest = await liton(["manifest"]);
    assert.equal(manifest.code, 0, manifest.stderr);
    assert.equal(JSON.parse(manifest.stdout).protocol, 1);
  });
  await step("Devices lists both, the one asking current, and no token; revoking the CLI refuses it", async () => {
    const { devices } = await (await ask("devices", { headers: { Cookie: cookie } })).json();
    assert.deepEqual(devices.map((device) => [device.name, device.current]), [["Browser", true], ["liton command line", false]]);
    assert.ok(!JSON.stringify(devices).includes(cookie.split(".")[1]));
    const made = await (await ask("devices/code", { method: "POST", body: {}, headers: { Cookie: cookie } })).json();
    assert.match(made.code, /^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$/);
    assert.ok(made.expires_at > Date.now());
    assert.equal(made.link, `${daemon}/ui/index.html#pair=${made.code}`);
    const revoked = await ask("devices/revoke", { method: "POST", body: { id: devices[1].id }, headers: { Cookie: cookie } });
    assert.equal(revoked.status, 200);
    assert.equal(revoked.headers.get("set-cookie"), null);
    assert.equal((await liton(["manifest"])).code, 2);
  });
  await step("revoking the browser itself clears its cookie and signs it out", async () => {
    const { devices } = await (await ask("devices", { headers: { Cookie: cookie } })).json();
    const revoked = await ask("devices/revoke", { method: "POST", body: { id: devices[0].id }, headers: { Cookie: cookie } });
    assert.match(revoked.headers.get("set-cookie"), /^liton_token=; Path=\/; Max-Age=0/);
    assert.equal((await ask("manifest", { headers: { Cookie: cookie } })).status, 401);
  });
  await step("a federating daemon reaches a daemon that requires pairing with the token it was paired with", async () => {
    const paired = await (await ask("pair", { method: "POST", body: { code: await code(), name: "home", token: true } })).json();
    assert.match(paired.token, /^[0-9a-f]{16}\.[0-9a-f]{64}$/);
    start({ LITON_PORT: String(federatingPort), LITON_DB: path.join(scratch, "federating.db"), LITON_MOCK: "off", LITON_PROVIDERS: `team=${daemon}`, LITON_PROVIDER_TOKENS: `team=${paired.token}` });
    const manifest = await until("the remote's providers", async () => {
      const answer = await (await fetch(`http://127.0.0.1:${federatingPort}/liton/v1/manifest`)).json();
      return answer.providers.some((provider) => provider.id === "team/mock") && answer;
    });
    assert.ok(manifest.providers.some((provider) => provider.id === "team/mock"));
  });
  await step("pairing is tried at most 10 times a minute", async () => {
    const statuses = [];
    for (let attempt = 0; attempt < 12; attempt++) statuses.push((await ask("pair", { method: "POST", body: { code: "AAAA-AAAA" } })).status);
    assert.ok(statuses.includes(429));
    assert.ok(statuses.slice(statuses.indexOf(429)).every((status) => status === 429));
  });
  await step("a loopback-only daemon answers this machine unpaired, but not a request a proxy forwarded", async () => {
    const loopback = `http://127.0.0.1:${loopbackPort}/liton/v1/manifest`;
    assert.equal((await fetch(loopback)).status, 200);
    assert.equal((await fetch(loopback, { headers: { "X-Forwarded-For": "203.0.113.9" } })).status, 401);
  });
  await step("no token is ever logged", async () => {
    assert.ok(!/[0-9a-f]{16}\.[0-9a-f]{64}/.test(required.stderrText + started.map((child) => child.stderrText).join("")));
  });
} catch (error) {
  fail(error);
}
console.log("ok: client authentication");
process.exit(0);

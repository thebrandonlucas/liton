// node e2e/passkeys.mjs CDP, after `zig build daemon cli`: a person registers
// a passkey and signs in with it, in headless Chrome with a virtual
// authenticator (WebAuthn.addVirtualAuthenticator), against a daemon on a
// free port with a fresh database that requires pairing, its site
// LITON_RP_ID=localhost. Without LITON_RP_ID, passkeys are refused.
// CDP is roc-signals's DevTools client, which `zig build e2e` passes; CHROME
// names the browser (default `chromium` on PATH).
import { execFile, spawn } from "node:child_process";
import assert from "node:assert/strict";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

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
  console.log(`FAIL ${check}: ${String(error?.message ?? error).split("\n")[0]}`);
  process.exit(1);
};
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "liton-passkeys-"));
fs.mkdirSync(path.join(scratch, "www"));
fs.writeFileSync(path.join(scratch, "www/index.html"), "<!doctype html><title>liton</title>");
const database = path.join(scratch, "liton.db");
let daemon_process;
const start = (env = {}) => {
  daemon_process = spawn(path.join(repo, "zig-out/bin/liton-daemon"), {
    cwd: repo,
    stdio: ["ignore", "ignore", "inherit"],
    env: { ...process.env, PASEO_PASSWORD: "", LITON_HOST: "127.0.0.1", LITON_PORT: String(port), LITON_DB: database, LITON_UI: path.join(scratch, "www"), LITON_MOCK: "off", LITON_AUTH: "required", LITON_VERIFY: path.join(repo, "zig-out/bin/liton-verify"), ...env },
  });
  daemon_process.on("error", fail);
  daemon_process.on("exit", (code) => fail(`the daemon exited with ${code}`));
};
const stop = () =>
  new Promise((resolve) => {
    daemon_process.removeAllListeners("exit");
    daemon_process.on("exit", resolve);
    daemon_process.kill();
  });
let browser;
process.on("exit", () => {
  if (daemon_process && daemon_process.exitCode === null && daemon_process.signalCode === null) daemon_process.kill("SIGKILL");
  fs.rmSync(scratch, { recursive: true, force: true });
});
const daemon = `http://localhost:${port}`;
const answering = async () => {
  for (const begin = Date.now(); ; await new Promise((r) => setTimeout(r, 100))) {
    if (await fetch(`${daemon}/ui/index.html`).then((r) => r.ok).catch(() => false)) return;
    if (Date.now() - begin > 10000) throw new Error("no answer after 10 s");
  }
};
const liton = (args) =>
  new Promise((resolve) => {
    execFile(path.join(repo, "zig-out/bin/liton"), args, { env: { ...process.env, LITON_URL: daemon, LITON_DB: database, XDG_CONFIG_HOME: path.join(scratch, "config"), LITON_TOKEN: "" } }, (error, stdout, stderr) => resolve({ code: error?.code ?? 0, stdout, stderr }));
  });
const step = async (name, test) => {
  check = name;
  await test();
};

// What the page does with a passkey, as the UI's will: each route's answer
// as { status, body }, the browser's passkey asked for between begin and
// finish, its bytes base64url.
const helpers = `
  const b64 = (buffer) => btoa(String.fromCharCode(...new Uint8Array(buffer))).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
  const bytes = (text) => Uint8Array.from(atob(text.replaceAll("-", "+").replaceAll("_", "/")), (c) => c.charCodeAt(0));
  const post = async (route, body) => {
    const r = await fetch("/liton/v1/" + route, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
    const text = await r.text();
    return { status: r.status, body: r.ok ? JSON.parse(text) : text };
  };
  window.liton = {
    post,
    register: async (name) => {
      const begun = await post("passkeys/register/begin", {});
      if (begun.status !== 200) return begun;
      const o = begun.body;
      const made = await navigator.credentials.create({ publicKey: {
        challenge: bytes(o.challenge), rp: { id: o.rp_id, name: o.rp_id },
        user: { id: bytes(o.user_id), name: o.user_name, displayName: o.display_name },
        pubKeyCredParams: [{ type: "public-key", alg: -7 }, { type: "public-key", alg: -8 }],
        authenticatorSelection: { residentKey: "required", userVerification: "required" }, attestation: "none",
        excludeCredentials: o.exclude.map((id) => ({ type: "public-key", id: bytes(id) })) } });
      return post("passkeys/register/finish", { challenge: o.challenge, id: b64(made.rawId), public_key: b64(made.response.getPublicKey()), alg: made.response.getPublicKeyAlgorithm(), authenticator_data: b64(made.response.getAuthenticatorData()), client_data: b64(made.response.clientDataJSON), name });
    },
    answer: async () => {
      const begun = await post("login/begin", {});
      const got = await navigator.credentials.get({ publicKey: { challenge: bytes(begun.body.challenge), rpId: begun.body.rp_id, userVerification: "required", allowCredentials: [] } });
      return { challenge: begun.body.challenge, id: b64(got.rawId), authenticator_data: b64(got.response.authenticatorData), client_data: b64(got.response.clientDataJSON), signature: b64(got.response.signature), name: "Browser" };
    },
    // An answer with its signature counter one higher, which it didn't sign.
    tampered: (answer) => {
      const data = bytes(answer.authenticator_data);
      data[36] = data[36] + 1;
      return { ...answer, authenticator_data: b64(data) };
    },
    sign_in: async () => {
      const answer = await window.liton.answer();
      return { answer, finished: await post("login/finish", answer) };
    },
  };`;

try {
  await step("without LITON_RP_ID, passkeys are refused, saying to set it", async () => {
    start({ LITON_RP_ID: "" });
    await answering();
    const refused = await fetch(`${daemon}/liton/v1/login/begin`, { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" });
    assert.equal(refused.status, 503);
    assert.match(await refused.text(), /set LITON_RP_ID/);
    await stop();
    start({ LITON_RP_ID: "localhost" });
    await answering();
  });
  await step("a passkey is used only at the box's name", async () => {
    const elsewhere = await fetch(`http://127.0.0.1:${port}/liton/v1/login/begin`, { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" });
    assert.equal(elsewhere.status, 403);
    assert.match(await elsewhere.text(), /passkeys are for localhost/);
  });
  browser = await launch({ executablePath: process.env.CHROME || "chromium" });
  const page = await browser.newPage();
  await page.send("WebAuthn.enable", {});
  await page.send("WebAuthn.addVirtualAuthenticator", { options: { protocol: "ctap2", transport: "internal", hasResidentKey: true, hasUserVerification: true, isUserVerified: true } });
  await page.goto(`${daemon}/ui/index.html`);
  await page.evaluate(helpers);
  const poll = () => page.evaluate(`liton.post("poll", { topics: [] }).then((r) => r.status)`);
  await step("a browser paired as the owner registers a passkey, which the owner's listing counts", async () => {
    const code = (await liton(["pair"])).stdout.split("\n")[0];
    assert.equal((await page.evaluate(`liton.post("pair", { code: ${JSON.stringify(code)}, name: "Browser" }).then((r) => r.status)`)), 200);
    const registered = await page.evaluate(`liton.register("Laptop")`);
    assert.equal(registered.status, 200, registered.body);
    assert.equal(registered.body.passkey.name, "Laptop");
    const people = await page.evaluate(`liton.post("poll", { topics: [{ capability: "people.v1", topic: "people", after: "" }] }).then((r) => r.body.topics[0].events.at(-1).People.people)`);
    assert.deepEqual(people.map((person) => [person.name, person.passkeys, person.devices]), [["Owner", 1, 1]]);
  });
  await step("signing out ends the browser's session", async () => {
    assert.equal(await page.evaluate(`liton.post("logout", {}).then((r) => r.status)`), 200);
    assert.equal(await poll(), 401);
  });
  let answer;
  await step("the passkey signs the browser in, a session of 30 days, and the passkey shows as this browser's", async () => {
    const signed = await page.evaluate(`liton.sign_in()`);
    assert.equal(signed.finished.status, 200, signed.finished.body);
    assert.deepEqual([signed.finished.body.person.name, signed.finished.body.person.role], ["Owner", "operator"]);
    answer = signed.answer;
    assert.equal(await poll(), 200);
    const listed = await page.evaluate(`fetch("/liton/v1/passkeys").then((r) => r.json())`);
    assert.deepEqual(listed.passkeys.map((passkey) => [passkey.name, passkey.rp_id, passkey.current]), [["Laptop", "localhost", true]]);
    assert.equal(listed.rp_id, "localhost");
  });
  await step("an answer is used once: replayed, it is refused", async () => {
    const replayed = await page.evaluate(`liton.post("login/finish", ${JSON.stringify(answer)})`);
    assert.equal(replayed.status, 401);
    assert.match(replayed.body, /expired or was used/);
  });
  await step("authenticator data the passkey didn't sign is refused", async () => {
    const refused = await page.evaluate(`liton.answer().then((answer) => liton.post("login/finish", liton.tampered(answer)))`);
    assert.equal(refused.status, 401);
    assert.match(refused.body, /signature is wrong/);
  });
  await step("deleting the passkey signs out the sessions it opened", async () => {
    const listed = await page.evaluate(`fetch("/liton/v1/passkeys").then((r) => r.json())`);
    assert.equal(await page.evaluate(`liton.post("passkeys/delete", { id: ${JSON.stringify(listed.passkeys[0].id)} }).then((r) => r.status)`), 200);
    assert.equal(await poll(), 401);
    const signed = await page.evaluate(`liton.sign_in()`);
    assert.equal(signed.finished.status, 401);
  });
  await browser.close();
} catch (error) {
  fail(error);
}
console.log("ok: passkeys");
process.exit(0);

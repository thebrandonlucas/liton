// node e2e/voice.mjs, after `zig build daemon`: checks voice.v1 and the audio
// route (see docs/protocol.md) against a daemon of its own. With LITON_STT
// naming a running engine (rig/speech/), it posts fixtures/utterance.wav (2.9
// s of "Open the authentication module and run the tests.", synthesized with
// Kokoro, Apache-2.0) in 1 s chunks and checks the transcript. Without it, the
// daemon's engine is a closed port, and the transcript is skipped.
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
const port = await freePort();
const engine = process.env.LITON_STT || `sherpa=ws://127.0.0.1:${await freePort()}`;
let check = "the daemon answers";
const fail = (error) => {
  console.log(`FAIL ${check}: ${String(error?.message ?? error).split("\n")[0]}`);
  process.exit(1);
};
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "liton-voice-"));
process.on("exit", () => fs.rmSync(scratch, { recursive: true, force: true }));
const daemon = spawn(path.join(repo, "zig-out/bin/liton-daemon"), {
  cwd: repo,
  stdio: ["ignore", "ignore", "inherit"],
  env: { ...process.env, PASEO_PASSWORD: "", LITON_STT: engine, LITON_HOST: "127.0.0.1", LITON_PORT: String(port), LITON_DB: path.join(scratch, "liton.db"), LITON_UI: scratch },
});
process.on("exit", () => {
  if (daemon.exitCode === null && daemon.signalCode === null) daemon.kill("SIGKILL");
});
daemon.on("error", fail);
daemon.on("exit", (code) => fail(`the daemon exited with ${code}`));

const base = `http://127.0.0.1:${port}/liton/v1`;
const call = async (request) => (await fetch(`${base}/call`, { method: "POST", body: JSON.stringify({ capability: "voice.v1", request }) })).json();
const chunk = async (utterance, seq, body) => {
  const response = await fetch(`${base}/audio/voice.v1/${utterance}/${seq}`, { method: "POST", headers: { "Content-Type": "audio/L16;rate=16000;channels=1" }, body });
  return { status: response.status, answer: await response.json() };
};
const status = async () => (await (await fetch(`${base}/poll`, { method: "POST", body: JSON.stringify({ topics: [{ capability: "voice.v1", topic: "status", after: "" }] }) })).json()).topics[0];
const step = async (name, run) => {
  check = name;
  await run();
};
const pcm = fs.readFileSync(path.join(repo, "e2e/fixtures/utterance.wav")).subarray(44);
const chunks = Array.from({ length: Math.ceil(pcm.length / 32000) }, (_, seq) => pcm.subarray(seq * 32000, (seq + 1) * 32000));
const last_seq = chunks.length - 1;

try {
  let manifest;
  for (const start = Date.now(); !manifest; await new Promise((r) => setTimeout(r, 50))) {
    manifest = await fetch(`${base}/manifest`).then((r) => r.json()).catch(() => null);
    if (Date.now() - start > 10000) throw new Error("no manifest after 10 s");
  }
  await step("the manifest lists local-speech with voice.v1 and its status topic", () => {
    assert.deepEqual(manifest.providers.find((p) => p.id === "local-speech").capabilities, [{ name: "voice", version: 1 }]);
    assert.deepEqual(manifest.topics.find((t) => t.capability.name === "voice").patterns, ["status"]);
  });
  const up = (await status()).events[0].Status.stt === "Ready";
  await step("the status topic and Begin agree on the engine", async () => {
    const begun = await call({ Begin: { utterance_id: "u1", purpose: "Dictation" } });
    if (up) assert.deepEqual(begun, { Ok: "Accepted" });
    else assert.deepEqual([begun.Err.code, Object.keys((await status()).events[0].Status.stt)], ["Unavailable", ["Down"]]);
  });
  await step("the audio route refuses a bad address, an odd chunk and one too big", async () => {
    assert.equal((await chunk("u1", 300, chunks[0])).answer.Err.code, "BadRequest");
    assert.equal((await chunk("u.1", 0, chunks[0])).answer.Err.code, "BadRequest");
    assert.equal((await chunk("u1", 0, pcm.subarray(0, 3))).answer.Err.code, "BadRequest");
    const big = await chunk("u1", 0, Buffer.alloc(70000));
    assert.deepEqual([big.status, big.answer.Err.code], [413, "BadRequest"]);
  });
  await step("chunks are acked up to the highest seq held with every one before it", async () => {
    assert.deepEqual((await chunk("u1", 1, chunks[1])).answer, { Ok: {} });
    assert.deepEqual((await chunk("u1", 0, chunks[0])).answer, { Ok: { acked: 1 } });
    assert.deepEqual((await chunk("u1", 0, chunks[0])).answer, { Ok: { acked: 1 } });
  });
  await step("Finish names the first chunk missing", async () => {
    assert.deepEqual(await call({ Finish: { utterance_id: "u1", last_seq } }), { Ok: { Missing: { from_seq: 2 } } });
    for (let seq = 2; seq <= last_seq; seq++) await chunk("u1", seq, chunks[seq]);
  });
  if (up) {
    await step("Finish transcribes the utterance, and again answers the same", async () => {
      const start = performance.now();
      const finished = await call({ Finish: { utterance_id: "u1", last_seq } });
      const took = Math.round(performance.now() - start);
      assert.match(finished.Ok?.Transcript?.text ?? JSON.stringify(finished), /^open the authentication module and run the tests\.?$/i);
      assert.deepEqual(await call({ Finish: { utterance_id: "u1", last_seq } }), finished);
      console.log(`  ${engine.split("=")[0]}: "${finished.Ok.Transcript.text}" in ${took} ms for ${(pcm.length / 32000).toFixed(1)} s of audio`);
    });
  } else {
    await step("Finish with the engine down is Unavailable, and Cancel drops the audio", async () => {
      assert.equal((await call({ Finish: { utterance_id: "u1", last_seq } })).Err.code, "Unavailable");
      assert.deepEqual(await call({ Cancel: { utterance_id: "u1" } }), { Ok: "Accepted" });
      assert.deepEqual(await call({ Finish: { utterance_id: "u1", last_seq } }), { Ok: { Missing: { from_seq: 0 } } });
    });
    console.log("SKIP voice.v1 transcript: no speech engine; set LITON_STT to one running (rig/speech/README.md)");
  }
  console.log("PASS voice.v1");
  process.exit(0);
} catch (error) {
  fail(error);
}

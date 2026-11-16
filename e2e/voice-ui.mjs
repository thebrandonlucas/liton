// node e2e/voice-ui.mjs CDP, after `zig build ui daemon`: headless Chrome,
// its microphone fed fixtures/utterance.wav ("Open the authentication module
// and run the tests."), dictates into a chat's composer against a daemon of
// its own. The mic loads its JavaScript only when first pressed. With
// LITON_STT naming a running engine (rig/speech/), a tap starts it, a tap
// stops it, and the transcript lands in the composer beside what was typed;
// then Send while dictating stops it and sends what was typed with the
// transcript after it, in one go. Without one, the mic says the engine is
// down, and the dictation is skipped.
// CDP is roc-signals's DevTools client, which `zig build e2e` passes; CHROME
// names the browser (default `chromium` on PATH).
import { spawn } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const { launch } = await import(pathToFileURL(process.argv[2]).href);

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
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "liton-voice-ui-"));
process.on("exit", () => fs.rmSync(scratch, { recursive: true, force: true }));
const daemon = spawn(path.join(repo, "zig-out/bin/liton-daemon"), {
  cwd: repo,
  stdio: ["ignore", "ignore", "inherit"],
  env: { ...process.env, PASEO_PASSWORD: "", LITON_STT: engine, LITON_HOST: "127.0.0.1", LITON_PORT: String(port), LITON_DB: path.join(scratch, "liton.db"), LITON_UI: path.join(repo, "zig-out/www") },
});
process.on("exit", () => {
  if (daemon.exitCode === null && daemon.signalCode === null) daemon.kill("SIGKILL");
});
for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) process.on(signal, () => process.exit(1));
daemon.on("error", fail);
daemon.on("exit", (code) => fail(`the daemon exited with ${code}`));
const until = async (what, test, timeout = 10000) => {
  for (const start = Date.now(); ; await new Promise((r) => setTimeout(r, 50))) {
    const value = await test().catch(() => false);
    if (value) return value;
    if (Date.now() - start > timeout) throw new Error(`timed out after ${timeout} ms waiting for ${what}`);
  }
};
const step = async (name, run) => {
  check = name;
  await run();
};

// The browser's fake microphone plays the fixture once; launch() takes no
// flags, so a wrapper adds them.
const chrome = path.join(scratch, "chrome");
const fixture = path.join(repo, "e2e/fixtures/utterance.wav");
fs.writeFileSync(chrome, `#!/bin/sh\nexec ${JSON.stringify(process.env.CHROME || "chromium")} --use-fake-ui-for-media-stream --use-fake-device-for-media-stream ${JSON.stringify(`--use-file-for-fake-audio-capture=${fixture}%noloop`)} --autoplay-policy=no-user-gesture-required "$@"\n`, { mode: 0o755 });

try {
  const base = `http://127.0.0.1:${port}`;
  await until("the manifest", async () => (await fetch(`${base}/liton/v1/manifest`)).ok);
  const status = async () => (await (await fetch(`${base}/liton/v1/poll`, { method: "POST", body: JSON.stringify({ topics: [{ capability: "voice.v1", topic: "status", after: "" }] }) })).json()).topics[0].events[0].Status.stt;
  const up = (await status()) === "Ready";

  const browser = await launch({ executablePath: chrome });
  const page = await browser.newPage();
  await page.goto(`${base}/`);
  const mic = () => page.evaluate(() => {
    const button = document.querySelector(".composer .mic");
    return button && { label: button.getAttribute("aria-label"), disabled: button.getAttribute("aria-disabled") === "true", title: button.title, level: Number(button.style.getPropertyValue("--level")), status: button.closest(".voice").querySelector(".voice-status").textContent, hidden: button.closest(".voice").hidden };
  });
  const loaded = () => page.evaluate(() => performance.getEntriesByType("resource").some((entry) => entry.name.endsWith("/voice.mjs")));

  await step("the composer shows the mic once the daemon offers voice.v1, without loading the voice code", async () => {
    await until("the mic", async () => (await mic())?.hidden === false && (await mic()).title !== "Voice is unavailable: checking the speech engine");
    if (await loaded()) throw new Error("voice.mjs loaded before the mic was pressed");
  });

  if (!up) {
    await step("the mic says the engine is down", async () => {
      const shown = await mic();
      if (!shown.disabled || !shown.title.startsWith("Voice is unavailable: ")) throw new Error(JSON.stringify(shown));
    });
    console.log("SKIP voice in the UI, dictation: no speech engine; set LITON_STT to one running (rig/speech/README.md)");
    console.log("PASS voice in the UI");
    process.exit(0);
  }

  await step("a tap on the mic listens at once and loads the voice code", async () => {
    await until("the mic usable", async () => !(await mic()).disabled);
    await page.evaluate(() => {
      const box = document.querySelector(".composer textarea");
      box.focus();
      document.execCommand("insertText", false, "Please:");
    });
    await (await page.evaluateHandle(() => document.querySelector(".composer .mic"))).click();
    const shown = await mic();
    if (shown.status !== "Listening" || shown.label !== "Stop dictating") throw new Error(JSON.stringify(shown));
    await until("voice.mjs", loaded);
  });

  await step("the level meter follows the fixture's speech", async () => {
    await until("a level over 30", async () => (await mic()).level > 30, 5000);
  });

  await step("a second tap stops it, shown as transcribing", async () => {
    await new Promise((r) => setTimeout(r, 3500));
    await (await page.evaluateHandle(() => document.querySelector(".composer .mic"))).click();
    const shown = await mic();
    if (shown.status !== "Transcribing…") throw new Error(JSON.stringify(shown));
  });

  await step("the transcript lands in the composer after what was typed", async () => {
    const start = performance.now();
    const text = await until("the transcript", async () => {
      const value = await page.evaluate(() => document.querySelector(".composer textarea").value);
      return /^Please: open the authentication module,? and run the tests\.?$/i.test(value) && value;
    }, 20000);
    const shown = await mic();
    if (shown.status !== "" || shown.label !== "Dictate") throw new Error(JSON.stringify(shown));
    console.log(`  ${engine.split("=")[0]}: "${text}", ${Math.round(performance.now() - start)} ms after the stop`);
  });

  await step("Send while dictating stops it, shown as transcribing at once, then sends what was typed with the transcript", async () => {
    await page.evaluate(() => [...document.querySelectorAll(".tree-session button")].find((button) => button.textContent.includes("Scratch")).click());
    await until("Scratch in the chat", () => page.evaluate(() => [...document.querySelectorAll(".pane-header")].some((header) => header.textContent.includes("Scratch"))));
    await page.evaluate(() => {
      const box = document.querySelector(".composer textarea");
      box.focus();
      box.select();
      document.execCommand("insertText", false, "Then:");
    });
    await (await page.evaluateHandle(() => document.querySelector(".composer .mic"))).click();
    await until("a level over 30", async () => (await mic()).level > 30, 5000);
    await new Promise((r) => setTimeout(r, 3500));
    await (await page.evaluateHandle(() => document.querySelector(".composer button[type=submit]"))).click();
    const shown = await mic();
    if (shown.status !== "Transcribing…") throw new Error(JSON.stringify(shown));
    const start = performance.now();
    const sent = await until("the message sent", () =>
      page.evaluate(() => [...document.querySelectorAll(".entry.user")].map((entry) => entry.textContent).find((text) => /Then: open the authentication module,? and run the tests/i.test(text))), 20000);
    const left = await page.evaluate(() => document.querySelector(".composer textarea").value);
    if (left !== "" || (await mic()).label !== "Dictate") throw new Error(JSON.stringify({ left, mic: await mic() }));
    console.log(`  sent "${sent}", ${Math.round(performance.now() - start)} ms after Send`);
  });

  console.log("PASS voice in the UI");
  process.exit(0);
} catch (error) {
  fail(error);
}

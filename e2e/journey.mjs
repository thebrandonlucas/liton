// node e2e/journey.mjs CDP, after `zig build ui daemon`: headless Chrome drives
// the UI against a daemon serving the mock provider, on a free port with a
// fresh database. CDP is roc-signals's DevTools client (its
// tests/browser/cdp.mjs), which `zig build e2e` passes. CHROME names the browser
// (default `chromium` on PATH).
import { spawn } from "node:child_process";
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
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "liton-e2e-"));
const daemon = spawn(path.join(repo, "zig-out/bin/liton-daemon"), {
  cwd: repo,
  stdio: ["ignore", "ignore", "inherit"],
  env: { ...process.env, PASEO_PASSWORD: "", LITON_HOST: "127.0.0.1", LITON_PORT: String(port), LITON_DB: path.join(scratch, "liton.db"), LITON_UI: path.join(repo, "zig-out/www") },
});
process.on("exit", () => {
  if (daemon.exitCode === null && daemon.signalCode === null) daemon.kill("SIGKILL");
  fs.rmSync(scratch, { recursive: true, force: true });
});
for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) process.on(signal, () => process.exit(1));
daemon.on("error", fail);
daemon.on("exit", (code) => fail(`the daemon exited with ${code}`));
const until = async (what, test, timeout = 10000) => {
  for (const start = Date.now(); ; await new Promise((r) => setTimeout(r, 50))) {
    if (await test().catch(() => false)) return;
    if (Date.now() - start > timeout) throw new Error(`timed out after ${timeout} ms waiting for ${what}`);
  }
};

try {
  const base = `http://127.0.0.1:${port}`;
  await until("the manifest", async () => (await fetch(`${base}/liton/v1/manifest`)).ok);

  const browser = await launch({ executablePath: process.env.CHROME || "chromium" });
  const page = await browser.newPage();
  await page.goto(`${base}/`);
  // Whether an element matching `selector` in the pane named `pane` contains `text`.
  const has = (pane, selector, text = "") =>
    page.evaluate(
      (pane, selector, text) => [...document.querySelectorAll(`section[aria-label="${pane}"] ${selector}`)].some((e) => e.textContent.includes(text)),
      pane, selector, text,
    );
  const see = (pane, selector, text, timeout) => until(`${pane}: ${selector} "${text ?? ""}"`, () => has(pane, selector, text), timeout);
  const click = async (pane, selector, text) => {
    await see(pane, selector, text);
    const target = await page.evaluateHandle(
      (pane, selector, text) => [...document.querySelectorAll(`section[aria-label="${pane}"] ${selector}`)].find((e) => e.textContent.includes(text)),
      pane, selector, text,
    );
    await target.click();
  };
  const step = async (name, run) => {
    check = name;
    await run();
  };

  await step("the three preset panes render", async () => {
    for (const pane of ["Sessions", "Chat", "Capabilities"]) await see(pane, ".pane-title", pane);
    await see("Capabilities", ".manifest", "Mock agents (mock)");
  });
  await step("the seeded sessions appear in Sessions", async () => {
    for (const title of ["Fix the login redirect", "Find the flaky CI test", "Scratch"]) await see("Sessions", ".session button", title);
  });
  await step("the flaky CI session is waiting for you", () =>
    until("its status", () => page.evaluate(() =>
      [...document.querySelectorAll(".session")].some((s) => s.textContent.includes("Find the flaky CI test") && s.querySelector('[data-testid="session-status"]')?.textContent === "waiting for you"))));
  await step("the Inbox preset lists it under Needs you, and the title counts it", async () => {
    await page.click(".settings-toggle");
    await click("Settings", "button", "Inbox preset");
    await see("Inbox", ".inbox-section", "Needs you");
    await see("Inbox", ".inbox-section .inbox-item", "Find the flaky CI test");
    await until("the title count", () => page.evaluate(() => document.title === "(1) liton"));
    await click("Settings", "button", "Developer preset");
    await page.click(".settings-toggle");
  });
  await step("focusing the login fix shows its changed file in Changes, and picking it shows a hunk", async () => {
    await click("Sessions", ".session button", "Fix the login redirect");
    await see("Changes", ".git-status", "fix-auth");
    await click("Changes", ".git-file button", "src/Auth.roc");
    await see("Changes", ".hunk-header", "@@ -40,3 +40,3 @@");
    await see("Changes", ".diff-line .added", "redirect_to = request.came_from");
  });
  await step("selecting it shows its failed tool card and the permission prompt", async () => {
    await click("Sessions", ".session button", "Find the flaky CI test");
    await see("Chat", ".pane-context", "following Find the flaky CI test");
    await see("Chat", '.tool-card.failed [data-testid="tool-state"]', "failed");
    await see("Chat", ".tool-card.failed .tool-output", "FAIL (expected 3, got 2)");
    await see("Chat", "div.permission", "Allow edit: Sort entries by sequence in tests/timeline.roc?");
    await see("Chat", '.pane-header [data-testid="session-status"]', "waiting for you");
  });
  await step("Allow clears the prompt", async () => {
    await click("Chat", "div.permission button", "Allow");
    await until("the prompt to clear", async () => !(await has("Chat", "div.permission")));
  });
  await step("a message sent to Scratch with Enter appears, and leaves the composer empty and focused", async () => {
    await click("Sessions", ".session button", "Scratch");
    await see("Chat", ".pane-context", "following Scratch");
    const composer = 'section[aria-label="Chat"] input[aria-label="Message"]';
    await (await page.$(composer)).type("Find the TODOs");
    await page.keyboard.press("Enter");
    await see("Chat", ".entry.user", "Find the TODOs");
    const typed = () => page.evaluate((composer) => document.activeElement === document.querySelector(composer) && document.querySelector(composer).value, composer);
    await until("an empty, focused composer", async () => (await typed()) === "");
    await page.keyboard.type("Next");
    await until("only the new text in the composer", async () => (await typed()) === "Next");
  });
  await step("its tool card runs, then is done", async () => {
    await see("Chat", '.tool-card.running [data-testid="tool-state"]', "running", 8000);
    await see("Chat", '.tool-card.done [data-testid="tool-state"]', "done", 8000);
    await see("Chat", ".tool-card.done .tool-output", "TODO handle the empty case");
  });
  await step("a new permission prompt asks to edit", () => see("Chat", "div.permission", "Allow edit: Edit src/Main.roc to handle the empty case?", 8000));
  await step("on a phone, the Workbench opens on the chat, and the strip scrolls to the sessions", async () => {
    await page.send("Emulation.setDeviceMetricsOverride", { width: 390, height: 800, deviceScaleFactor: 1, mobile: true });
    await page.goto(`${base}/`);
    const in_view = (pane) => page.evaluate((pane) => {
      const left = document.querySelector(`section[aria-label="${pane}"]`)?.getBoundingClientRect().left ?? -1;
      return left >= 0 && left < 20;
    }, pane);
    await until("the chat panel in view", () => in_view("Chat"));
    await page.click('[data-testid="show-left"]');
    await until("the sessions panel in view", () => in_view("Sessions"));
  });
  await step("the page threw no errors", async () => {
    if (page.errors.length) throw new Error(page.errors.join("; "));
  });
  await browser.close();
  console.log("ok   e2e journey: panes, sessions, the inbox, changes, permission prompts and tool cards against the mock daemon");
  process.exit(0);
} catch (error) {
  fail(error);
}

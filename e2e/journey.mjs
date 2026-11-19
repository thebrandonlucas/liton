// node e2e/journey.mjs CDP, after `zig build ui daemon cli`: headless Chrome
// drives the UI against a daemon serving the mock provider, on a free port
// with a fresh database and the setup liton's Litonfile evaluates to, with a
// preset added. CDP is roc-signals's DevTools client (its
// tests/browser/cdp.mjs), which `zig build e2e` passes. CHROME names the
// browser (default `chromium` on PATH).
import assert from "node:assert/strict";
import { execFile, spawn } from "node:child_process";
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
process.on("exit", () => fs.rmSync(scratch, { recursive: true, force: true }));
// liton's setup as `liton setup` evaluates its Litonfile, with a preset of its own.
check = "liton setup evaluates liton's Litonfile";
await new Promise((resolve) => execFile(path.join(repo, "zig-out/bin/liton"), ["setup", path.join(repo, "Litonfile.roc")], { cwd: scratch }, (error, _, stderr) => (error ? fail(stderr) : resolve())));
const setup = JSON.parse(fs.readFileSync(path.join(scratch, "liton.setup.json"), "utf8"));
const changes_only = { name: "Changes only", snapshot: { version: 4, shell: "Tiling", collapsed: [], hidden: [], theme: "", grid: { columns: [1], rows: [1], tiles: [{ id: "tile-1", left: 0, top: 0, right: 1, bottom: 1, active: "pane-1", panes: [{ id: "pane-1", widget: "changes", pinned: "", options: [] }] }] } } };
fs.writeFileSync(path.join(scratch, "liton.setup.json"), JSON.stringify({ ...setup, presets: [...setup.presets, changes_only] }));
check = "the daemon answers";
const daemon = spawn(path.join(repo, "zig-out/bin/liton-daemon"), {
  cwd: repo,
  stdio: ["ignore", "ignore", "inherit"],
  env: { ...process.env, PASEO_PASSWORD: "", LITON_HOST: "127.0.0.1", LITON_PORT: String(port), LITON_DB: path.join(scratch, "liton.db"), LITON_UI: path.join(repo, "zig-out/www"), LITON_SETUP: path.join(scratch, "liton.setup.json") },
});
process.on("exit", () => {
  if (daemon.exitCode === null && daemon.signalCode === null) daemon.kill("SIGKILL");
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

  // A laptop's window, not headless Chrome's small default, in which a drawer is too short to show a file.
  const browser = await launch({ executablePath: process.env.CHROME || "chromium", args: ["--window-size=1280,800"] });
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

  await step("the three preset panes render, with Capabilities left to Settings", async () => {
    for (const pane of ["Workspaces", "Chat", "Changes"]) await see(pane, ".pane-header .menu-toggle");
    await until("no Capabilities pane", async () => !(await page.evaluate(() => !!document.querySelector('section[aria-label="Capabilities"]'))));
  });
  await step("the mock's project, its workspaces and their seeded sessions appear in Workspaces", async () => {
    await see("Workspaces", ".tree-group button", "Liton");
    // fix-auth holds one session, which stands in its place with its branch.
    await see("Workspaces", ".tree-workspace button", "main");
    await see("Workspaces", ".tree-session .branch", "fix-auth");
    for (const title of ["Fix the login redirect", "Find the flaky CI test", "Scratch"]) await see("Workspaces", ".tree-session button", title);
  });
  await step("the flaky CI session is waiting for you", () =>
    until("its status", () => page.evaluate(() =>
      [...document.querySelectorAll(".tree-session")].some((s) => s.textContent.includes("Find the flaky CI test") && s.querySelector('[data-testid="row-status"]')?.textContent === "waiting for you"))));
  await step("the Inbox preset lists it under Needs you, the title counts it, and opening an unread item reads it", async () => {
    await page.click(".settings-toggle");
    await click("Settings", "button", "Inbox preset");
    await see("Inbox", ".inbox-section", "Needs you");
    await see("Inbox", ".inbox-section .inbox-item", "Find the flaky CI test");
    await until("the title count", () => page.evaluate(() => document.title === "(1) liton"));
    // Unread until opened, then read at once.
    await page.click(".settings-toggle");
    await see("Inbox", ".inbox-item.unread > button");
    const title = await page.evaluate(() => document.querySelector(".inbox-item.unread > button").textContent);
    await click("Inbox", ".inbox-item.unread > button", title);
    const read = () => page.evaluate((title) => [...document.querySelectorAll(".inbox-item > button")].some((b) => b.textContent === title && !b.parentElement.classList.contains("unread")), title);
    await until(`${title} read`, read);
    // And still, once the daemon took it and a poll or two followed.
    await new Promise((r) => setTimeout(r, 2500));
    assert.ok(await read(), `${title} read after polls`);
    await page.click(".settings-toggle");
    await click("Settings", "button", "Developer preset");
    await page.click(".settings-toggle");
  });
  await step("the preset picker offers the setup's own preset, which loads its layout", async () => {
    await page.click(".settings-toggle");
    await click("Settings", "button", "Changes only preset");
    await until("only Changes", () => page.evaluate(() => [...document.querySelectorAll("section.pane")].map((s) => s.getAttribute("aria-label")).join() === "Changes"));
    await click("Settings", "button", "Developer preset");
    await page.click(".settings-toggle");
  });
  await step("clicking a workspace shows its session that needs you in Chat, and its git in Changes", async () => {
    await click("Workspaces", ".tree-workspace button", "main");
    await see("Chat", ".pane-header .pane-title", "Find the flaky CI test");
    await see("Changes", ".git-status", "main");
    await see("Changes", ".missing", "Working tree clean");
  });
  await step("focusing the login fix shows its reply as Markdown, its changed file in Changes, and picking it shows a hunk", async () => {
    await click("Workspaces", ".tree-session button", "Fix the login redirect");
    await see("Changes", ".git-status", "fix-auth");
    await click("Changes", '.git-file button[aria-label="src/Auth.roc"]', "Auth.roc");
    await see("Changes", ".hunk-header", "@@ -40,3 +40,3 @@");
    await see("Changes", ".code-row .added", "redirect_to = request.came_from");
    await see("Chat", ".markdown .code", "/login");
    await see("Chat", ".md-code .tok-comment", "# src/Auth.roc");
    await see("Chat", ".md-item", "Logging in now returns you where you were.");
  });
  await step("a comment on lines of the file opened from Changes is a draft until Send review sends it to the agent, which replies", async () => {
    await click("Changes", ".diff-path button", "Open in Files");
    await see("Files", ".file-path", "src/Auth.roc");
    await see("Files", ".code-row", "Session.start(redirect_to)");
    await click("Files", ".code-row .number", "2");
    await click("Files", ".code-row .number", "3");
    await see("Files", ".composer-title", "Comment on src/Auth.roc:2-3");
    await page.keyboard.type("Fall back to `/` without a page to return to?");
    await click("Files", ".comment-actions button", "Comment");
    await see("Files", '.comment [data-testid="comment-state"]', "draft");
    await see("Files", '[data-testid="review-summary"]', "1 draft");
    await click("Files", ".review-panel button", "Send review");
    await see("Files", '.comment [data-testid="comment-state"]', "sent in round 1");
    await see("Chat", ".entry.user", "src/Auth.roc:2-3");
    await see("Chat", ".entry.user", "Fall back to");
    await see("Chat", ".markdown", "Looking into it", 8000);
    await see("Files", '[data-testid="review-summary"]', "1 round sent");
  });
  await step("selecting it shows its failed tool card and the permission prompt", async () => {
    await click("Workspaces", ".tree-session button", "Find the flaky CI test");
    await see("Chat", ".pane-header .pane-title", "Find the flaky CI test");
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
    await click("Workspaces", ".tree-session button", "Scratch");
    await see("Chat", ".pane-header .pane-title", "Scratch");
    const composer = 'section[aria-label="Chat"] textarea[aria-label="Message"]';
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
  await step("Stop ends the turn: the prompt goes, and the agent says it stopped", async () => {
    // The round button stops only once nothing is typed; with "Next" in the composer it sends.
    for (const _ of "Next") await page.keyboard.press("Backspace");
    await click("Chat", '.composer button[aria-label="Stop"]', "");
    await see("Chat", ".markdown", "Stopped.", 8000);
    await until("the prompt to clear", async () => !(await has("Chat", "div.permission")));
    await see("Chat", '.pane-header [data-testid="session-status"]', "idle");
  });
  await step("New agent in a workspace shows it starting at once, then running", async () => {
    // The row may start and run within one poll, so watch for it starting.
    await page.evaluate(() => {
      window.sawStarting = false;
      const starting = () => [...document.querySelectorAll(".tree-session")].some((row) => row.textContent.includes("Write the docs") && row.textContent.includes("starting…"));
      new MutationObserver(() => { window.sawStarting ||= starting(); }).observe(document.body, { subtree: true, childList: true, characterData: true });
    });
    await page.click('section[aria-label="Workspaces"] button[aria-label="New agent beside Fix the login redirect"]');
    await see("Workspaces", ".create-form", "New agent in fix-auth");
    await (await page.$('section[aria-label="Workspaces"] input[aria-label="First prompt"]')).type("Write the docs");
    await click("Workspaces", ".create-form button", "Start");
    await until("the new agent starting", () => page.evaluate(() => window.sawStarting));
    await see("Chat", ".pane-header .pane-title", "Write the docs");
    await until("the new agent running", () => page.evaluate(() =>
      [...document.querySelectorAll(".tree-session")].some((row) => row.textContent.includes("Write the docs") && row.querySelector('[data-testid="row-status"]')?.textContent === "running")), 8000);
    await see("Chat", '.pane-header [data-testid="session-status"]', "running");
  });
  await step("dragging the Files tab onto the chat moves it to the main area, and dragging it back returns it", async () => {
    const centre = (selector) => page.evaluate((selector) => {
      const box = document.querySelector(selector).getBoundingClientRect();
      return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
    }, selector);
    const mouse = (type, { x, y }) => page.send("Input.dispatchMouseEvent", { type, x, y, button: "left", buttons: type === "mouseReleased" ? 0 : 1, clickCount: 1 });
    const drag = async (from, to) => {
      const start = await centre(from), end = await centre(to);
      await mouse("mouseMoved", start);
      await mouse("mousePressed", start);
      for (let step = 1; step <= 8; step++) await mouse("mouseMoved", { x: start.x + (end.x - start.x) * step / 8, y: start.y + (end.y - start.y) * step / 8 });
      await until(`a drop target over ${to}`, () => page.evaluate(() => !!document.querySelector(".tile.drop-into")));
      await mouse("mouseReleased", end);
    };
    const tabs = (slot) => page.evaluate((slot) => [...document.querySelectorAll(`[data-testid="slot-${slot}"] .tab-select`)].map((b) => b.textContent).join(), slot);
    await drag('[data-testid="slot-right"] .tab-select.widget-files', 'section[aria-label="Chat"]');
    await until("Files in the main area", async () => (await tabs("main")).endsWith("Files") && !(await tabs("right")).includes("Files"));
    await until("no drop target left", () => page.evaluate(() => !document.querySelector(".drop-into, .dragged")));
    await drag('[data-testid="slot-main"] .tab-select.widget-files', '[data-testid="slot-right"]');
    await until("Files back in the right drawer", async () => (await tabs("right")).includes("Files") && !(await tabs("main")).includes("Files"));
  });
  await step("on a phone, the Workbench opens on the chat, and the strip scrolls to the workspaces", async () => {
    await page.send("Emulation.setDeviceMetricsOverride", { width: 390, height: 800, deviceScaleFactor: 1, mobile: true });
    await page.goto(`${base}/`);
    const in_view = (pane) => page.evaluate((pane) => {
      const left = document.querySelector(`section[aria-label="${pane}"]`)?.getBoundingClientRect().left ?? -1;
      return left >= 0 && left < 20;
    }, pane);
    await until("the chat panel in view", () => in_view("Chat"));
    await page.click('[data-testid="show-left"]');
    await until("the workspaces panel in view", () => in_view("Workspaces"));
  });
  await step("the page threw no errors", async () => {
    if (page.errors.length) throw new Error(page.errors.join("; "));
  });
  await browser.close();
  console.log("ok   e2e journey: panes, workspaces and new agents, sessions, the inbox, a setup's preset, changes, files and a review sent to the agent, permission prompts and tool cards against the mock daemon");
  process.exit(0);
} catch (error) {
  fail(error);
}

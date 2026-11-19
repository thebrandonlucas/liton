// node e2e/previews.mjs CDP, after `zig build ui daemon`, as `zig build
// devtool -- previews` runs it: headless Chrome renders each surface the
// daemon's setup offers and each part liton has, against a daemon serving
// the mock provider on a free port with a fresh database, into
// ui/previews/surface-<name>.webp and widget-<id>.webp, the thumbnails
// Settings' Deck shows. CDP is roc-signals's DevTools client (its
// tests/browser/cdp.mjs). CHROME names the browser (default `chromium` on
// PATH), which runs with a throwaway profile and is killed on exit.
//
// FIXME: a JavaScript stopgap, as the e2e scripts are. It becomes Roc in
// devtool/ once basic-cli can hold a WebSocket to speak the DevTools
// protocol (or roc-signals's browser harness is a Roc package).
//
// Animated previews, a short loop of each surface in use, would be
// recorded here too (Page.startScreencast) into ui/previews/*.webm beside
// these; they aren't made yet.
import { spawn } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const { launch } = await import(pathToFileURL(process.argv[2]).href);

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const out = path.join(repo, "ui/previews");
const port = await new Promise((resolve) => {
  const probe = net.createServer().listen(0, "127.0.0.1", () => {
    const { port } = probe.address();
    probe.close(() => resolve(port));
  });
});
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "liton-previews-"));
process.on("exit", () => fs.rmSync(scratch, { recursive: true, force: true }));
const daemon = spawn(path.join(repo, "zig-out/bin/liton-daemon"), {
  cwd: repo,
  stdio: ["ignore", "ignore", "inherit"],
  env: { ...process.env, PASEO_PASSWORD: "", LITON_HOST: "127.0.0.1", LITON_PORT: String(port), LITON_DB: path.join(scratch, "liton.db"), LITON_UI: path.join(repo, "zig-out/www") },
});
process.on("exit", () => {
  if (daemon.exitCode === null && daemon.signalCode === null) daemon.kill("SIGKILL");
});
for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) process.on(signal, () => process.exit(1));
const until = async (what, test, timeout = 10000) => {
  for (const start = Date.now(); ; await new Promise((r) => setTimeout(r, 50))) {
    if (await test().catch(() => false)) return;
    if (Date.now() - start > timeout) throw new Error(`timed out after ${timeout} ms waiting for ${what}`);
  }
};
// As ui/Model.roc's `preview` names them.
const slug = (name) => name.toLowerCase().replaceAll(" ", "-");

try {
  const base = `http://127.0.0.1:${port}`;
  await until("the manifest", async () => (await fetch(`${base}/liton/v1/manifest`)).ok);
  const manifest = await (await fetch(`${base}/liton/v1/manifest`)).json();
  const browser = await launch({ executablePath: process.env.CHROME || "chromium" });
  const page = await browser.newPage();
  // The page as a browser that kept a deck of `snapshot` alone shows it,
  // its tiles drawn and the mock's sessions polled, shot at a quarter size.
  const shoot = async (file, name, snapshot, { width, height }) => {
    await page.send("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 1, mobile: false });
    // Kept from a page that isn't the app, which would write its own.
    await page.goto(`${base}/style.css`);
    await page.evaluate((deck, name) => {
      localStorage.clear();
      localStorage.setItem("liton.snapshot", deck);
      localStorage.setItem("liton.surface", name);
    }, JSON.stringify({ surfaces: [{ name, snapshot }], version: snapshot.version }), name);
    await page.goto(`${base}/`);
    await until(`${name}'s tiles`, () => page.evaluate(() => document.querySelectorAll(".tile .pane").length > 0));
    await new Promise((r) => setTimeout(r, 2500));
    const { data } = await page.send("Page.captureScreenshot", { format: "webp", quality: 60, clip: { x: 0, y: 0, width, height, scale: 0.25 } });
    fs.writeFileSync(path.join(out, file), Buffer.from(data, "base64"));
    console.log(`wrote ui/previews/${file}`);
  };
  fs.mkdirSync(out, { recursive: true });
  const presets = manifest.setup?.presets ?? [];
  for (const preset of presets) await shoot(`surface-${slug(preset.name)}.webp`, preset.name, preset.snapshot, { width: 1440, height: 900 });
  // The parts, as Settings' Deck lists them by id, each alone in Tiling.
  await page.goto(`${base}/style.css`);
  await page.evaluate(() => localStorage.clear());
  await page.goto(`${base}/`);
  await until("Settings", () => page.evaluate(() => !!document.querySelector(".settings-toggle")));
  await page.click(".settings-toggle");
  await until("the Deck section", () => page.evaluate(() => [...document.querySelectorAll(".settings-rail button")].some((b) => b.textContent === "Deck")));
  await page.evaluate(() => [...document.querySelectorAll(".settings-rail button")].find((b) => b.textContent === "Deck").click());
  await until("the parts", () => page.evaluate(() => !!document.querySelector("[data-widget]")));
  const widgets = await page.evaluate(() => [...new Set([...document.querySelectorAll("[data-widget]")].map((e) => e.getAttribute("data-widget")))]);
  const version = presets[0]?.snapshot.version ?? 9;
  for (const widget of widgets) {
    const grid = { columns: [1], rows: [1], tiles: [{ id: "tile-1", left: 0, top: 0, right: 1, bottom: 1, active: "pane-1", panes: [{ id: "pane-1", widget, pinned: "", options: [] }] }] };
    await shoot(`widget-${slug(widget)}.webp`, "", { version, shell: "Tiling", grid, collapsed: [], hidden: [], theme: "" }, { width: 960, height: 600 });
  }
  await browser.close();
  process.exit(0);
} catch (error) {
  console.log(`FAIL previews: ${String(error?.message ?? error).split("\n")[0]}`);
  process.exit(1);
}

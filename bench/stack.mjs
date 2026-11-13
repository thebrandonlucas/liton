// The processes a benchmark run needs, all on 127.0.0.1 inside the private
// network namespace bench.mjs opens: a throwaway Paseo 0.15.3 daemon from
// the rig's npm packages (its web UI on, unlike rig/paseo/daemon.sh), liton's
// daemon pointed at it, and counting proxies in front of both, so each
// client's traffic to a daemon is counted on its own.
import { spawn, execFile } from "node:child_process";
import fs from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";

const run_file = promisify(execFile);

export const ports = {
  paseo: 16767,
  // The Paseo web client's origin: browser -> proxy -> Paseo.
  paseo_for_browser: 16768,
  // What liton's daemon dials: liton daemon -> proxy -> Paseo.
  paseo_for_liton: 16769,
  liton: 18095,
  // liton's origin: browser -> proxy -> liton daemon.
  liton_for_browser: 18096,
  // The precompression experiment's file server, in front of liton's daemon.
  liton_static: 18097,
};
export const password = "liton-bench-password";

const started = [];
export function stop_all() {
  for (const child of started.reverse()) {
    if (child.exitCode === null && child.signalCode === null) {
      try {
        process.kill(-child.pid, "SIGKILL");
      } catch (_) {
        child.kill("SIGKILL");
      }
    }
  }
}
process.on("exit", stop_all);

function start(command, args, options) {
  const child = spawn(command, args, { detached: true, stdio: ["ignore", "pipe", "pipe"], ...options });
  started.push(child);
  return child;
}

export const until = async (what, test, timeout = 30000, every = 50) => {
  for (const begin = Date.now(); ; await new Promise((r) => setTimeout(r, every))) {
    if (await test().catch(() => false)) return;
    if (Date.now() - begin > timeout) throw new Error(`timed out after ${timeout} ms waiting for ${what}`);
  }
};

// Paseo's environment, with nothing inherited from a real Paseo.
function paseo_env(home) {
  const env = Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith("PASEO_")));
  return { ...env, HOME: home, PASEO_HOME: home };
}

export async function start_paseo({ repo, scratch, log }) {
  const home = path.join(scratch, "paseo-home");
  fs.mkdirSync(home, { recursive: true });
  fs.writeFileSync(
    path.join(home, "config.json"),
    JSON.stringify({
      daemon: { listen: `127.0.0.1:${ports.paseo}`, relay: { enabled: false } },
      features: { webUi: { enabled: true }, dictation: { enabled: false }, voiceMode: { enabled: false } },
    }),
  );
  const bin = path.join(repo, "rig/paseo/node_modules/.bin/paseo");
  if (!fs.existsSync(bin)) throw new Error("rig/paseo has no npm packages yet: run rig/paseo/paseo.sh --version once");
  const child = start(bin, ["daemon", "run", "--home", home], {
    cwd: scratch,
    env: {
      ...paseo_env(home),
      PASEO_LISTEN: `127.0.0.1:${ports.paseo}`,
      PASEO_PASSWORD: password,
      PASEO_RELAY_ENABLED: "false",
      PASEO_WEB_UI_ENABLED: "true",
      PASEO_DICTATION_ENABLED: "false",
      PASEO_VOICE_MODE_ENABLED: "false",
      // Adds the scripted "mock" provider, which needs no model or account.
      PASEO_NODE_ENV: "development",
    },
  });
  child.stdout.pipe(log);
  child.stderr.pipe(log);
  await until("Paseo's web UI", async () => (await fetch(`http://127.0.0.1:${ports.paseo}/`)).ok, 60000, 200);
  const cli = (...args) =>
    run_file(bin, ["--home", home, ...args], { cwd: path.join(scratch, "workspace"), env: { ...paseo_env(home), PASEO_PASSWORD: password }, maxBuffer: 64 << 20 }).then((r) => r.stdout);
  return { child, home, cli };
}

export async function start_liton({ repo, scratch, log, www }) {
  const child = start(path.join(repo, "zig-out/bin/liton-daemon"), [], {
    cwd: repo,
    env: {
      ...Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith("PASEO_") && !k.startsWith("LITON_"))),
      LITON_HOST: "127.0.0.1",
      LITON_PORT: String(ports.liton),
      LITON_DB: path.join(scratch, "liton.db"),
      LITON_UI: www,
      LITON_MOCK: "off",
      PASEO_HOST: "127.0.0.1",
      PASEO_PORT: String(ports.paseo_for_liton),
      PASEO_PASSWORD: password,
    },
  });
  child.stdout.pipe(log);
  child.stderr.pipe(log);
  await until("liton's manifest", async () => (await fetch(`http://127.0.0.1:${ports.liton}/liton/v1/manifest`)).ok, 30000, 100);
  return { child };
}

// Counts what passes through it: HTTP requests by path, WebSocket upgrades,
// and WebSocket messages and bytes each way, parsed from the frames.
export function counting_proxy(listen_port, target_port) {
  const counts = { connections: 0, http_requests: 0, http_paths: {}, ws_connections: 0, ws_open: 0, ws_messages_up: 0, ws_messages_down: 0, ws_bytes_up: 0, ws_bytes_down: 0, bytes_up: 0, bytes_down: 0 };
  const sockets = new Set();
  // One direction of one connection: HTTP heads until an upgrade, then frames.
  const reader = (direction, on_upgrade) => {
    let buffer = Buffer.alloc(0);
    let mode = "http";
    return {
      set_ws: () => (mode = "ws"),
      feed(chunk) {
        if (direction === "up") counts.bytes_up += chunk.length;
        else counts.bytes_down += chunk.length;
        if (mode === "http") {
          if (direction === "up") {
            // Count request lines; bodies are rare here (GETs and upgrades).
            for (const m of chunk.toString("latin1").matchAll(/(?:^|\r\n)(GET|POST|PUT|HEAD|DELETE|PATCH|OPTIONS) (\S+) HTTP\/1\.[01]\r\n/g)) {
              counts.http_requests++;
              const p = m[2].split("?")[0];
              counts.http_paths[p] = (counts.http_paths[p] ?? 0) + 1;
            }
          } else if (/^HTTP\/1\.1 101/.test(chunk.toString("latin1", 0, 12))) {
            const head_end = chunk.indexOf("\r\n\r\n");
            on_upgrade();
            mode = "ws";
            if (head_end >= 0 && head_end + 4 < chunk.length) this.feed_ws(chunk.subarray(head_end + 4));
          }
          return;
        }
        this.feed_ws(chunk);
      },
      feed_ws(chunk) {
        buffer = buffer.length ? Buffer.concat([buffer, chunk]) : chunk;
        for (;;) {
          if (buffer.length < 2) return;
          const fin = buffer[0] & 0x80;
          const opcode = buffer[0] & 0x0f;
          const masked = buffer[1] & 0x80;
          let length = buffer[1] & 0x7f;
          let offset = 2;
          if (length === 126) {
            if (buffer.length < 4) return;
            length = buffer.readUInt16BE(2);
            offset = 4;
          } else if (length === 127) {
            if (buffer.length < 10) return;
            length = Number(buffer.readBigUInt64BE(2));
            offset = 10;
          }
          if (masked) offset += 4;
          if (buffer.length < offset + length) return;
          // A message is a final data frame or continuation; pings and pongs count too.
          if (fin && opcode !== 0x8) {
            if (direction === "up") counts.ws_messages_up++;
            else counts.ws_messages_down++;
          }
          if (direction === "up") counts.ws_bytes_up += length;
          else counts.ws_bytes_down += length;
          buffer = buffer.subarray(offset + length);
        }
      },
    };
  };
  const server = net.createServer((client) => {
    counts.connections++;
    sockets.add(client);
    const upstream = net.connect(target_port, "127.0.0.1");
    sockets.add(upstream);
    const up = reader("up", () => {});
    const down = reader("down", () => {
      counts.ws_connections++;
      counts.ws_open++;
      up.set_ws();
      client.once("close", () => counts.ws_open--);
    });
    client.on("data", (d) => {
      up.feed(d);
      upstream.write(d);
    });
    upstream.on("data", (d) => {
      down.feed(d);
      client.write(d);
    });
    const end = () => {
      client.destroy();
      upstream.destroy();
      sockets.delete(client);
      sockets.delete(upstream);
    };
    client.on("close", end);
    upstream.on("close", end);
    client.on("error", end);
    upstream.on("error", end);
  });
  return new Promise((resolve) =>
    server.listen(listen_port, "127.0.0.1", () =>
      resolve({
        counts,
        snapshot: () => JSON.parse(JSON.stringify(counts)),
        close: () => {
          for (const s of sockets) s.destroy();
          server.close();
        },
      }),
    ),
  );
}

// Each counter's growth between two snapshots.
export function delta(after, before) {
  const out = {};
  for (const [k, v] of Object.entries(after)) {
    if (typeof v === "number") out[k] = v - (before[k] ?? 0);
  }
  return out;
}

export const make_scratch = () => fs.mkdtempSync(path.join(os.tmpdir(), "liton-bench-"));

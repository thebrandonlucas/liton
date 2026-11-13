# Benchmarks: liton against other agent clients

`bench/bench.mjs` runs the same scripted tasks against liton and Paseo
0.15.3's web client, in headless Chromium driven over the DevTools protocol,
and writes `bench/results/<date>-<label>.json` (every sample) and `.md` (the
tables).

```sh
zig build daemon ui                        # liton as it is now, into zig-out/
rig/paseo/paseo.sh --version               # once: installs Paseo 0.15.3's npm packages
CHROME=/path/to/chromium node bench/bench.mjs
```

`CHROME` defaults to `chromium` on `PATH`; without one, use
`CHROME=$(nix build --no-link --print-out-paths nixpkgs#chromium)/bin/chromium`.
The DevTools client is roc-signals's `tests/browser/cdp.mjs`, the one `zig build
e2e` uses; the script finds it in `zig-pkg/` after `zig build --fetch`, or takes
its path as its first argument. A full run (5 desktop runs, 3 phone runs, a
minute of each client idle) takes about 15 minutes.

| option | default | |
|---|---|---|
| `--runs` | 5 | desktop runs per client |
| `--phone-runs` | 3 | phone runs per client |
| `--profiles` | `desktop,phone` | |
| `--clients` | `liton,paseo` | |
| `--agents` | 5 | mock agents seeded, 2 to 9 |
| `--rounds` | 1 | clicks through every agent per run |
| `--sends` | 3 | messages typed and sent per run |
| `--idle-seconds` | 60 | how long each client sits idle for the daemon load |
| `--liton-www` | `zig-out/www` | the UI liton's daemon serves, to compare builds |
| `--precompressed` | off | serve the UI's files from their `.br` siblings (see below) |
| `--label`, `--out` | `baseline`, `bench/results` | where the results go |

## What it sets up

Everything runs in a private network namespace (`unshare -rn`, loopback only):
no daemon outside it, such as a Paseo or liton you use, can be reached, and
nothing listens outside it.

- A throwaway Paseo 0.15.3 daemon from `rig/paseo`'s npm packages, with a
  temporary home, a password, the mock provider (no model or account) and,
  unlike `rig/paseo/daemon.sh`, its web UI on, as Paseo serves its own web
  client.
- `--agents` mock agents, each in its own directory (Paseo shows each as a
  workspace): agents 1 to N-1 run one ten-second scripted turn, then agent 0
  one two-second turn, so it was updated last and liton opens on it. Agent k's
  prompt starts `Bench task k:`.
- liton's daemon from `zig-out/bin`, on a temporary database with
  `LITON_MOCK=off`, pointed at the same Paseo daemon.
- Counting proxies in front of the daemons: browser to Paseo, liton's daemon to
  Paseo, browser to liton's daemon. They count HTTP requests, WebSocket
  connections, and WebSocket messages and bytes each way.
- Paseo's web client asks for the daemon's password once, then keeps the host
  in localStorage. The script connects once through its form, untimed, and gives
  every measured browser context that saved host, as for a returning user. liton
  needs nothing: its daemon holds the password.

## What each number means

Each run opens a fresh browser context (empty cache and storage) at 1280x800.
Times come from the page's own clock (`performance.now()`, zero at navigation
start): an in-page probe watches the DOM and records the animation frame after
a condition first holds, which is about when it is painted.

- **cold**: the first load in the context. **First contentful paint** is the
  browser's own. **Agent list shown**: all N agents are listed (liton's
  Sessions pane, Paseo's sidebar workspace rows). **Agent timeline shown**:
  agent 0's prompt and its answer's last line ("end of synthetic stream") are
  visible. liton opens on it at `/`; Paseo opens on its home screen, so it loads
  agent 0's own URL, `/h/<server>/agent/<id>`.
- **warm**: the same URL again in the same context: HTTP cache, compiled code
  cache and storage warm. liton's daemon revalidates every file (`no-cache`);
  Paseo's hashed bundles are cached for a year.
- **click session to timeline**: a real mouse click on agent k's row, from the
  `pointerdown` event's timestamp to the frame showing agent k's timeline and no
  other's. It visits every agent once, so most clicks open a timeline for the
  first time in that page.
- **keystroke to frame**: each key of a typed message, from `keydown` to the
  frame after the composer holds the text so far.
- **send to message shown**: Enter, from `keydown` to the frame showing the
  message in the timeline. The script then waits for the mock's turn to end.
- **memory**: after a forced garbage collection. **JS heap** is the page's and
  its workers'; it leaves out WebAssembly memory. **Renderer memory** is the
  proportional set size (PSS) of the page's renderer process, wasm memory,
  DOM and workers included; it is the fairer comparison. Measured after the
  loads and again after the clicks and sends.
- **download**: bytes per kind of response in the cold load, as transferred
  (compressed, with headers) and decoded. The table also lists each request's
  start and end in the first cold load.
- **daemon load, per minute**: from the proxies. *Idle* is each client open on
  agent 0 and left alone; *liton's daemon, no page open* is its own traffic to
  Paseo with no client; *active* is the clicks and sends of each run, divided
  by how long they took. For liton both hops count: the browser's requests to
  liton's daemon, and that daemon's to Paseo.

Each metric reports median / p95 over the runs (p95 is the nearest rank: with
5 samples, the largest).

## Profiles

- **desktop**: no throttling.
- **phone**: `Emulation.setCPUThrottlingRate` 4x and
  `Network.emulateNetworkConditions` at 150 ms latency, 1.6 Mbit/s down and
  750 kbit/s up, Lighthouse's mobile settings, to approximate a mid-range phone
  on a slow 4G network. The viewport stays desktop-sized, so both clients show
  the same layout.

## Caveats

- Headless Chromium on a development machine is not a phone. CPU throttling
  slows the renderer's main thread but not the GPU, the network stack or the
  machine's cores, and it scales the machine's speed, not a phone's. Treat
  phone numbers as relative, between clients and between liton builds.
- Network emulation applies to HTTP requests; how far it slows WebSocket
  frames depends on the Chromium version.
- The daemons and the browser share the machine. Other load moves the numbers:
  compare runs from the same machine, and look at p95 as well as the median.
- Both clients talk to a daemon on loopback, with no TLS or relay.
- Paseo's workspace rows show the directory name; liton's rows show the
  agent's title. The tasks find each by its own text.
- Messages are sent to agent 0, so its timeline grows over the runs, for both
  clients alike (they alternate which goes first each run).

## Comparing liton builds

`--liton-www` points liton's daemon at another UI directory, such as one with
an `app.wasm` built with `roc-ui build --opt=size`. `--precompressed` puts a
small file server (`bench/static.mjs`) in front of liton's daemon that serves
each file's `.br` sibling (made with `brotli -q 11 -k`) with
`Content-Encoding: br`, and passes the API to the daemon, to estimate what
serving precompressed files would gain over the daemon's on-the-fly zstd.
Use `--clients liton` to skip Paseo.

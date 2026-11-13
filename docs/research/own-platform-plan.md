# Plan: a Roc platform of liton's own

This is a plan, not a commitment. liton's daemon runs on
[basic-webserver](https://github.com/roc-lang/basic-webserver). That platform is
well maintained for the new compiler, but it is general on purpose, and some of
what liton needs is outside its model. This note covers what a platform built
for liton would offer, what it would cost, and how to find out cheaply whether
it is worth building. The detailed design is in
[own-platform-design.md](own-platform-design.md).

## What liton keeps running into

- **No work outside a request.** The daemon can't hold a connection to Paseo
  across requests, or read what Paseo pushes. So it polls Paseo on a 3-second
  cycle, and the UI polls the daemon every second (roc-issues
  `basic-webserver/IMPROVEMENT-011`). An agent's output reaches the screen up
  to about 4 s late, and each cycle opens a new WebSocket session on Paseo.
- **Upstream load is kept down by discipline, not structure.** Polling Paseo on
  every UI poll once kept Paseo near full CPU, until the daemon learned to ask
  at most every 3 seconds.
- **Footprint.** The UI's wasm is 10.8 MB, the daemon binary about 10.7 MB, and
  the goal is to be the fastest agent GUI with the smallest footprint.
- **Compiler churn.** Two nightlies in a row broke basic-webserver 0.21.0: one
  made every app segfault at startup (BUG-031), and one made every SQLite query
  into a record fail to check (BUG-032). Each needs a platform release before
  liton can move.

This is by design, not neglect. basic-webserver's design rules out mutable
in-process state, actors, background callbacks, supervision and
application-defined WebSockets
([design.md, "Deliberate non-goals"](https://github.com/roc-lang/basic-webserver/blob/main/design.md#deliberate-non-goals)),
so that its apps scale out across processes. liton is a personal daemon that
runs as a single process and fronts stateful agent backends. It needs exactly
what basic-webserver leaves out.

## Requirements

**Day one: parity with today's daemon** (`daemon/main.roc`), on Linux x64:

- an HTTP/1.1 server with keep-alive, header and body limits, and timeouts,
  covering today's routes: the manifest, `chat.v1`, `attention.v1`,
  `workspace.git.v1` and `workspaces.v1`;
- the UI's static files under `/ui`;
- SQLite with typed rows, parameters and `IMMEDIATE` transactions (the
  compare-and-swap in `store!`);
- an outbound HTTP client with timeouts (Paseo's MCP endpoint);
- TCP, enough to run today's WebSocket code unchanged until processes replace it;
- environment variables, stderr and the clock.

**Added by the new features:** long-lived pure processes with timers and
connections, a WebSocket client in the host, SSE push with resume, upstream
budgets, precompressed embedded assets, tracing, record and replay of
processes, and later live SQLite queries.

**Non-goals:**

- TLS: Caddy terminates it, as for any deployment.
- Windows at first. macOS and arm64 Linux come in M4.
- HTTP/2: the daemon speaks HTTP/1.1, and Caddy can serve HTTP/2 to browsers.
  The one cost is the browser's six-connections-per-origin limit when a tab
  connects without Caddy (see the design).
- Scaling out over several daemon processes, or clustering.
- A general actor framework, or a WebSocket server for apps' own protocols.
- Recovering from a Roc crash in-process: the daemon exits and is restarted.

## What it would offer

| | Idea | Where it lands |
|---|---|---|
| 1 | **Long-lived pure processes**: host-run state machines with mailboxes, timers and connections | M2 |
| 2 | **Signals over the wire**: processes publish to topics, and the UI subscribes over SSE through a roc-signals port | M2 |
| 3 | **Upstream budgets**: declared limits per upstream, enforced by the host | M3 |
| 4 | **One file, assets inside**: precompressed, content-hashed, cached for good | M1 |
| 5 | **Live SQLite queries**: the host reruns a subscribed query when its tables change | after M3 |
| 6 | **Record and replay** of process events | M3 |
| 7 | **Effects scoped per package**: a provider reaches only its own upstream | later |
| 8 | **Hot reload keeping state** (Roc's compiler has a hot-load mechanism, `src/ipc/hot_reload.zig`; its use by platforms is unverified) | later |
| 9 | **Tracing by default**: every effect, shown in a liton widget | M3 |
| 10 | **Typed RPC** from the shared `capabilities` package | later |

## Key choices

- **I/O:** one epoll thread owns every socket. One thread runs every process
  step, in one total order. A small pool runs request handlers, which may block
  on local effects. There is no async runtime.
- **ABI:** the new compiler's direct symbols, with a narrow surface and
  generated Zig glue. Values move between threads and are never shared. A Roc
  crash ends the daemon.
- **Processes:** `step : proc, Event(msg) -> Step(proc, msg)` is pure by its
  type. The host performs the effects it returns and restarts a failed process.
- **Built from source in liton's repo**, so a nightly fix lands in the same
  commit as the pin bump.

## Milestones

Estimates are full-time weeks for one developer, guessed rather than measured.
The spike exists to correct them.

**Spike: 2 days.** Built on a branch, never merged as is:

1. a Zig host on the pinned nightly: epoll, a minimal HTTP/1.1 server and one
   Roc route through `roc_respond`;
2. `roc_step` and one process, holding a WebSocket to Paseo (the host does the
   framing) and reconnecting with backoff;
3. a `/api/events` SSE stream of one session's timeline, applied in the UI
   through a `Port.subscription`;
4. measurements against today's daemon with 1 and 6 tabs open: latency from
   Paseo's message to the DOM (p50, p95), Paseo connections per minute, RSS idle
   and under load, binary size, and hours lost to ABI or compiler problems.

**M1, parity on Linux x64: about 3 weeks.** The full HTTP server, SQLite (with
record rows), the HTTP client, TCP and embedded precompressed assets. The
daemon ports by changing imports. CI runs on the pinned and newest nightly.
*Exit:* `zig build test` and `zig build e2e` pass with the daemon on the new
platform, latency and memory are no worse than on basic-webserver, and the UI
downloads compressed and caches for good. *liton gains* control of its own
fixes and a smaller download. *Risks:* HTTP edge cases, layout bugs in the
glue, nightly breakage in the middle of the work.

**M2, processes and push: about 3 weeks.** The process runner, the Paseo link
(see the design), topics with SSE resume, the UI's subscription, and polling
kept only as a fallback. *Exit:* one Paseo WebSocket per daemon however many
tabs are open, p95 under 100 ms from Paseo to the screen, no 1-second polling,
e2e green. *liton gains* live agents and much less load on Paseo and the
daemon, the core of the speed goal. *Risks:* Paseo's subscription messages are
not read yet, retaining closures across the ABI for `Ask`, and roc-signals port
behavior under reconnects.

**M3, budgets, tracing and replay: about 2 weeks.** Declared upstreams enforced
by the host, the trace ring and its widget, recording and replaying processes.
*Exit:* an undeclared or over-budget call is refused in tests, the widget shows
calls per upstream, and a recorded session replays to the same effects. *liton
gains* overload that is impossible by construction, and bugs reproducible from
a log. *Risks:* the cost of tracing on hot paths (measure it).

**M4, targets and release: about 3 weeks, then about 2 hours a week.** arm64
Linux, macOS with kqueue, release builds, and benchmarks against Paseo's
clients. *Exit:* CI green on three targets, and a published benchmark. *Risks:*
macOS linking on the new compiler, and following nightlies for good.

All four milestones come to about 11 weeks, plus the ongoing upkeep the Roc team
does for basic-webserver today.

## Decision points

**Go after the spike** only if all of these hold:

- it ran within about 3 days, and every compiler problem had a workaround;
- p95 from Paseo to the DOM is under 100 ms, against up to about 4 s today;
- Paseo sees one connection, whatever the number of tabs;
- RSS and binary size are no worse than today's daemon;
- regenerating glue for one newer nightly took under an hour.

**Otherwise, the fallback:** liton stays on basic-webserver. It keeps polling
within Paseo's budget, raises IMPROVEMENT-011 on Roc's Zulip (a replaceable
host-owned cell is the smallest of its three proposals), and reports BUG-031
and BUG-032. It vendors basic-webserver only if a fix can't wait.

**Revisit at M2** if a Roc crash in a process proves common in practice, since
that would favor running processes in child processes, as roc-signals runs
worker jobs.

## Alternatives

- **Stay on basic-webserver**, polling within Paseo's budget, and raise
  IMPROVEMENT-011 upstream. This is the cheapest option, and live streaming
  waits.
- **Live streaming within basic-webserver's model:** an SSE source per open tab
  whose timer steps read from Paseo. This uses a feature basic-webserver chose
  to build, but needs one Paseo connection per tab.
- **Vendor basic-webserver** and add what liton needs (the `rcrt1.o` and
  `missing_field` fixes, a replaceable cell or a client pool), upstreaming each.
  This costs a Rust toolchain and keeping the copy current.

## Open questions

- Who owns following nightlies once the platform is liton's, and how much time
  a week is acceptable?
- Is a seventh tab without Caddy worth solving (one stream shared across tabs),
  or is "use Caddy" enough?
- Should M1 keep the 3-second cycle as is (parity first), or go straight to
  processes (fewer steps, a bigger first change)?
- Is macOS needed before M4?
- Should the platform be shaped for others too (a "basic-actor-server"), or stay
  narrow to liton?

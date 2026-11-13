# Plan: a Roc platform of liton's own

A plan, not a commitment. liton's daemon runs on
[basic-webserver](https://github.com/roc-lang/basic-webserver), which is well
maintained for the new compiler but is general on purpose, and some of what
liton needs sits outside its model. This note records what a platform built for
liton would offer, what it would cost, and how to find out cheaply whether it
is worth it.

## What liton keeps running into

- **No work outside a request.** The daemon can't hold a connection to Paseo
  across requests or read what Paseo pushes, so it polls Paseo on a 3-second
  cycle and the UI polls the daemon every second (roc-issues
  `basic-webserver/IMPROVEMENT-011`).
- **Upstream load is kept down by discipline, not structure.** Polling Paseo on
  every UI poll once kept it near full CPU, until the daemon learned to ask at
  most every 3 seconds.
- **Footprint.** The UI's wasm is 10.8 MB and the goal is to be the fastest,
  smallest agent GUI.
- **Compiler churn.** A nightly that made native executables position
  independent left basic-webserver 0.21.0's host unusable until its next
  release.

## Shape

Two halves, as for any Roc platform: Roc modules giving the app contract and its
typed effects, and a host in Zig that performs them and calls into the app. The
host is narrow: what liton's daemon needs, on Linux x64 first.

| Piece | Effort | Notes |
|---|---|---|
| Host ↔ Roc ABI | M | as kai's platform does; the ABI still changes between nightlies |
| HTTP/1.1 server | M | keep-alive, limits, timeouts, streamed bodies; TLS stays with Caddy |
| Concurrency into Roc | M–L | worker pool and reference counting across threads |
| SQLite | S | the amalgamation, compiled by Zig |
| WebSocket client and server, SSE | S–M | liton already frames WebSocket in Roc |
| Static assets | S | precompressed, content-hashed, immutable caching |
| Targets and releases | M, ongoing | Linux x64, then arm64 and macOS |

A first version covering the daemon is weeks of work; production quality across
targets is months. The lasting cost is following nightly ABI changes, which the
Roc team absorbs for basic-webserver today.

## What it would offer that basic-webserver doesn't

The first four are the reason to build it.

1. **Long-lived pure processes.** Named host-run processes, each a pure Roc state
   machine with a mailbox (event in, state and effects out, the shape liton's
   providers already have). Connections, timers and messages arrive as events,
   so a Paseo connection lives across requests and reconnects, with no mutable
   state in Roc.
2. **Signals over the wire.** The server keeps derived state per subscriber and
   pushes only differences over SSE or WebSocket into roc-signals (through a
   port), replacing polling with updates in milliseconds.
3. **Upstream budgets.** Declared limits per upstream ("Paseo: one connection per
   3 seconds"), enforced by the host, which also merges identical requests in
   flight and caches. Overloading an upstream becomes impossible by
   construction.
4. **One file, assets inside.** The UI's wasm and static files compiled into the
   binary, compressed ahead of time and named by content hash, so a browser
   caches them for good and a deploy is one file.
5. **Live SQLite queries.** Subscribe to a query; the host pushes changed rows
   when a write touches its tables.
6. **Record and replay.** Every effect passes through the host, so it can log
   all inputs and replay a run exactly, making any bug reproducible from its log.
7. **Effects scoped per package.** A provider package declares the effects it may
   use (the Paseo provider reaches only Paseo), giving shared provider packages
   least privilege.
8. **Hot reload keeping state.** State is plain data, so new code can take over
   connections and state, migrating changed types, without a restart.
9. **Tracing by default.** Every effect traced, shown in a liton widget: what
   calls Paseo, how often, how slowly.
10. **Typed RPC from shared types.** Endpoints, codecs and compatibility checks
    derived from the `capabilities` package both sides already share.

## Finding out cheaply

A spike of about two days before any commitment:

1. a Zig host on the pinned nightly answering one HTTP route from Roc;
2. one long-lived process holding a WebSocket to Paseo within its budget;
3. pushing what Paseo sends to the browser over SSE, into roc-signals through a
   port;
4. measuring it against the polling daemon (latency, Paseo connections, memory).

If the spike works and following the compiler looks manageable, the platform
becomes a project, starting with ideas 1–4. If not, liton stays on
basic-webserver, carrying its own changes in a vendored copy if it must, and
raises IMPROVEMENT-011 on Roc's Zulip.

## Alternatives

- **Stay on basic-webserver**, polling within Paseo's budget, and raise
  IMPROVEMENT-011 upstream. Cheapest; live streaming waits.
- **Live streaming within basic-webserver's model**: an SSE stream per open tab
  whose steps read from Paseo. Uses a feature basic-webserver chose to build; one
  Paseo connection per tab.
- **Vendor basic-webserver** and add what liton needs (a PIC host build, the
  SQLite row fix, a replaceable host-owned cell or a client pool), upstreaming
  each. Costs a Rust toolchain and keeping the copy current.

# liton

A modular, capability-driven UI for working with AI agents across daemon backends. See [docs/vision.md](docs/vision.md) and [docs/design.md](docs/design.md).

## Development

`kai shell` enters the development environment ([Kai](https://github.com/thebrandonlucas/kai)), with the Roc compilers `.roc-version` (the daemon's, as `roc`) and `ui/.roc-version` (the UI's, as `roc-ui`) pin, and Zig. Then `zig build test` runs the checks and tests, and `zig build fmt` formats the sources.

## License

Licensed under either of [Apache License, Version 2.0](LICENSE-APACHE) or [MIT license](LICENSE-MIT) at your option.

## Running

`zig build run` (in `kai shell`) builds the UI and the daemon and serves both at http://127.0.0.1:8095, with scripted mock agents. `LITON_HOST`, `LITON_PORT` and `LITON_DB` (default `liton.db`) configure the daemon.

`LITON_PROVIDERS` adds providers outside the daemon, each a server of the same protocol such as another liton daemon, as `name=url` pairs separated by commas: `LITON_PROVIDERS="echo=http://127.0.0.1:8096,team=https://liton.example"`. What each offers is named under its name (`echo/echo`, `team/fix-auth`), and the daemon asks each at most once every `LITON_PROVIDERS_INTERVAL_MS` (default 1000) however many clients poll. `zig build example-provider` builds `zig-out/bin/provider-echo`, the smallest such provider (`examples/provider-echo/`).

## Command line

`zig build cli` builds `zig-out/bin/liton`, a client of the daemon's capability protocol ([docs/protocol.md](docs/protocol.md), The CLI) that prints JSON lines, so it composes with other tools:

```sh
liton manifest
liton call chat.v1 '"ListSessions"'
liton watch chat.v1 timeline/fix-auth | jq -r '.Entry.event.AgentMessage.text // empty'
```

It finds the daemon at `LITON_URL` (default `http://127.0.0.1:8095`); `liton help` lists its commands.

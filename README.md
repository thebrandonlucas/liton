# liton

A modular, capability-driven UI for working with AI agents across daemon backends. See [docs/vision.md](docs/vision.md) and [docs/design.md](docs/design.md).

## Development

`kai shell` enters the development environment ([Kai](https://github.com/thebrandonlucas/kai)), with the Roc compiler `.roc-version` pins and Zig. Then `zig build test` runs the checks and tests, and `zig build fmt` formats the sources.

## License

Licensed under either of [Apache License, Version 2.0](LICENSE-APACHE) or [MIT license](LICENSE-MIT) at your option.

## Running

`zig build run` (in `kai shell`) builds the UI and the daemon and serves both at http://127.0.0.1:8095, with scripted mock agents. `LITON_HOST`, `LITON_PORT` and `LITON_DB` (default `liton.db`) configure the daemon.

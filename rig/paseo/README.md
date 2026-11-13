# A local Paseo rig

A throwaway Paseo 0.15.3 daemon, and optionally Paseo's relay, to develop
liton's Paseo provider against, writes included, without touching a Paseo
anyone uses. Everything listens on 127.0.0.1 only. Nothing reaches Paseo's
hosted relay. The scripts need Node; without it on PATH they run under
`nix shell nixpkgs#nodejs`. Each installs its pinned npm packages on first
run, into `node_modules/`, which git ignores. They clear any `PASEO_*`
variable the shell inherited.

```sh
rig/paseo/daemon.sh                  # Paseo 0.15.3 on 127.0.0.1:16767, in the foreground
rig/paseo/paseo.sh ls                # Paseo's CLI against it
rig/paseo/paseo.sh run --provider mock/ten-second-stream --no-wait --title "rig agent" "Say hello"
```

Then point liton's daemon at it, on a port and database of its own:

```sh
LITON_PORT=18095 LITON_DB=/tmp/liton-rig.db LITON_MOCK=off \
PASEO_HOST=127.0.0.1 PASEO_PORT=16767 PASEO_PASSWORD=liton-rig-password zig build run
```

- **Home.** `HOME` and `PASEO_HOME` are both `rig/paseo/home`, so agents read
  no real credentials or history. `rm -rf rig/paseo/home` resets it.
  `RIG_HOME`, `RIG_PORT`, `RIG_PASSWORD` and `RIG_RELAY_PORT` override the
  defaults in `env.sh`.
- **Agents.** The daemon runs with `PASEO_NODE_ENV=development`, which adds
  Paseo's `mock` provider: a scripted agent that needs no model or account.
  Its models set how long a turn streams (`ten-second-stream`,
  `one-minute-stream`...). A prompt containing "emit a synthetic plan
  approval" makes it ask for a permission, and "emit a synthetic turn
  failure" makes the turn fail. Delete an agent with `./paseo.sh delete <id>`.
- **Features.** Voice, dictation and the web UI are off, as in the sandbox
  architecture.
- **Relay.** `rig/paseo/relay.sh` runs Paseo's relay in workerd
  (`wrangler dev --local`) on 127.0.0.1:18787. `relay/wrangler.toml` has no
  account, routes or upstream. `RIG_RELAY=true rig/paseo/daemon.sh` then
  connects the daemon to it, and `./paseo.sh daemon pair --json` prints the
  pairing offer.
- **Bridge.** `rig/paseo/bridge.sh` pairs liton's relay bridge
  (`bridges/paseo-relay`) with the daemon, from `./paseo.sh daemon pair
  --json`, and listens on 127.0.0.1:18767 (`RIG_BRIDGE_PORT`). The bridge
  holds the password, so liton's is ignored but must be set:

  ```sh
  rig/paseo/relay.sh                     # each in a terminal of its own
  RIG_RELAY=true rig/paseo/daemon.sh
  rig/paseo/bridge.sh
  LITON_PORT=18095 LITON_DB=/tmp/liton-rig.db LITON_MOCK=off \
  PASEO_HOST=127.0.0.1 PASEO_PORT=18767 PASEO_PASSWORD=bridge zig build run
  curl http://127.0.0.1:18767/status     # the bridge's state, relay round trip, last error
  ```

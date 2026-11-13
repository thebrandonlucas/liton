#!/usr/bin/env bash
# Runs Paseo's relay locally in workerd, on 127.0.0.1 only. Its wrangler.toml
# has no account, routes or upstream, so nothing reaches a hosted relay.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$rig/relay"
[ -x node_modules/.bin/wrangler ] || npm install --no-audit --no-fund
exec env WRANGLER_SEND_METRICS=false node_modules/.bin/wrangler dev --local --ip 127.0.0.1 --port "$RIG_RELAY_PORT"

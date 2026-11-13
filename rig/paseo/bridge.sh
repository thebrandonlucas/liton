#!/usr/bin/env bash
# Runs liton's Paseo relay bridge (bridges/paseo-relay) in the foreground,
# paired with the rig's daemon through the local relay: start relay.sh, then
# RIG_RELAY=true daemon.sh, then this. It listens on 127.0.0.1:$RIG_BRIDGE_PORT.
set -euo pipefail
source "$(dirname "$0")/env.sh"
bridge="$rig/../../bridges/paseo-relay"
[ -d "$bridge/node_modules/@getpaseo/relay" ] || (cd "$bridge" && npm install --no-audit --no-fund)
offer=$("$rig/paseo.sh" daemon pair --json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).url))')
cat >&2 <<TEXT
Point liton's daemon at it with (the bridge holds the password; liton's is ignored):
  PASEO_HOST=127.0.0.1 PASEO_PORT=$RIG_BRIDGE_PORT PASEO_PASSWORD=bridge
TEXT
exec env PASEO_BRIDGE_OFFER="$offer" PASEO_BRIDGE_PASSWORD="$RIG_PASSWORD" PASEO_BRIDGE_PORT="$RIG_BRIDGE_PORT" \
	node "$bridge/bridge.mjs"

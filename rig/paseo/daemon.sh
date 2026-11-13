#!/usr/bin/env bash
# Runs a throwaway Paseo 0.15.3 daemon in the foreground, on 127.0.0.1 only.
# RIG_RELAY=true also connects it to the local relay (relay.sh); it never
# connects to Paseo's hosted one.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$rig"
[ -x node_modules/.bin/paseo ] || npm install --ignore-scripts --no-audit --no-fund
mkdir -p "$RIG_HOME"
# Voice, dictation and the web UI off, as the sandbox architecture has them.
cat > "$RIG_HOME/config.json" <<JSON
{"features":{"dictation":{"enabled":false},"voiceMode":{"enabled":false},"webUi":{"enabled":false}},
 "daemon":{"relay":{"enabled":${RIG_RELAY:-false},"endpoint":"127.0.0.1:$RIG_RELAY_PORT","useTls":false,"requireProtectedSecurity":true}}}
JSON
cat >&2 <<TEXT
Point liton's daemon at it with:
  PASEO_HOST=127.0.0.1 PASEO_PORT=$RIG_PORT PASEO_PASSWORD=$RIG_PASSWORD
Use Paseo's CLI against it with ./paseo.sh, as in ./paseo.sh ls
TEXT
# PASEO_NODE_ENV=development enables Paseo's "mock" provider, a scripted
# agent that needs no model or account (see README.md).
exec env HOME="$RIG_HOME" PASEO_HOME="$RIG_HOME" PASEO_LISTEN="127.0.0.1:$RIG_PORT" PASEO_PASSWORD="$RIG_PASSWORD" \
	PASEO_RELAY_ENABLED="${RIG_RELAY:-false}" PASEO_RELAY_ENDPOINT="127.0.0.1:$RIG_RELAY_PORT" PASEO_RELAY_USE_TLS=false \
	PASEO_WEB_UI_ENABLED=false PASEO_DICTATION_ENABLED=false PASEO_VOICE_MODE_ENABLED=false \
	PASEO_NODE_ENV=development \
	node_modules/.bin/paseo daemon run --home "$RIG_HOME"

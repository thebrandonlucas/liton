#!/usr/bin/env bash
# Runs Paseo's CLI against the rig's daemon, as in ./paseo.sh ls
set -euo pipefail
source "$(dirname "$0")/env.sh"
exec env HOME="$RIG_HOME" PASEO_HOME="$RIG_HOME" PASEO_PASSWORD="$RIG_PASSWORD" "$rig/node_modules/.bin/paseo" --home "$RIG_HOME" "$@"

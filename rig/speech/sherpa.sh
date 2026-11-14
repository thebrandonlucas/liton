#!/usr/bin/env bash
# Runs sherpa-onnx's offline WebSocket server with Parakeet TDT 0.6B v2 int8
# in the foreground, on port $RIG_SHERPA_PORT, downloading the model
# first. Without sherpa-onnx on PATH, it runs under nixpkgs' (337 MB).
set -euo pipefail
command -v sherpa-onnx-offline-websocket-server >/dev/null || exec nix shell nixpkgs#sherpa-onnx -c "$0" "$@"
source "$(dirname "$0")/env.sh"
"$rig/models.sh" parakeet
model=$RIG_MODELS/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8
echo "Point liton's daemon at it with LITON_STT=sherpa=ws://127.0.0.1:$RIG_SHERPA_PORT" >&2
# It writes its log to log.txt, here.
cd "$rig"
# The server listens on every interface; a firewall keeps it local, or run
# it in a network namespace of its own.
exec sherpa-onnx-offline-websocket-server --port="$RIG_SHERPA_PORT" \
	--num-work-threads=1 --num-io-threads=1 --num-threads="$RIG_THREADS" \
	--model-type=nemo_transducer --tokens="$model/tokens.txt" \
	--encoder="$model/encoder.int8.onnx" --decoder="$model/decoder.int8.onnx" --joiner="$model/joiner.int8.onnx"

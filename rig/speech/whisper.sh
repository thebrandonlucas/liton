#!/usr/bin/env bash
# Runs whisper.cpp's whisper-server with base.en in the foreground, on
# 127.0.0.1:$RIG_WHISPER_PORT, downloading the model first. Without
# whisper-server on PATH, it runs under nixpkgs' whisper-cpp.
set -euo pipefail
command -v whisper-server >/dev/null || exec nix shell nixpkgs#whisper-cpp -c "$0" "$@"
source "$(dirname "$0")/env.sh"
"$rig/models.sh" whisper
echo "Point liton's daemon at it with LITON_STT=whisper=http://127.0.0.1:$RIG_WHISPER_PORT" >&2
exec whisper-server -m "$RIG_MODELS/ggml-base.en.bin" --host 127.0.0.1 --port "$RIG_WHISPER_PORT" -t "$RIG_THREADS"

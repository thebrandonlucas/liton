#!/usr/bin/env bash
# Checks out roc-signals at the commit .roc-signals pins into vendor/ (it has no
# release yet) and builds its browser host.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
read -r url commit < .roc-signals
checkout=vendor/roc-signals
if [ ! -d "$checkout/.git" ]; then
  git clone --quiet "$url" "$checkout"
fi
if [ "$(git -C "$checkout" rev-parse HEAD)" != "$commit" ]; then
  git -C "$checkout" fetch --quiet origin "$commit"
  git -C "$checkout" checkout --quiet "$commit"
fi
host="$checkout/platform/targets/wasm32/host.wasm"
if [ ! -f "$host" ] || [ "$checkout/platform/host/host.zig" -nt "$host" ]; then
  mkdir -p "$(dirname "$host")"
  (cd "$checkout/platform" && zig build-obj host/host.zig -target wasm32-freestanding -O ReleaseSmall -fstrip -femit-bin=targets/wasm32/host.wasm)
fi

#!/usr/bin/env bash
# Checks out roc-signals at the commit .roc-signals pins into vendor/ (it has no
# release yet) and builds its browser host and native spec runner's.
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
# The native spec runner links musl and Zig's runtime libraries, which
# roc-signals takes from a roc-fuzz release.
native="$checkout/platform/targets/x64musl"
if [ ! -f "$native/libc.a" ]; then
  bundle=vendor/roc-fuzz-0.5.0.tar.zst
  if [ ! -f "$bundle" ]; then
    curl -fsSL --retry 3 -o "$bundle.part" https://github.com/lukewilliamboswell/roc-fuzz/releases/download/0.5.0/9WT86CuwM7ZJBSs8iTd1jLyrUFTTiGp5hcJE63TwswGE.tar.zst
    mv "$bundle.part" "$bundle"
  fi
  echo "aed4032105af1cc910604949f43636b7bff6aec4a82184631213153b8e2dd23f  $bundle" | sha256sum --check --quiet
  mkdir -p "$native"
  tar --zstd -xf "$bundle" -C "$native" --strip-components=2 targets/x64musl/crt1.o targets/x64musl/libc.a targets/x64musl/libzigc.a targets/x64musl/libcompiler_rt.a
fi
if [ ! -f "$native/spec.o" ] || [ "$checkout/platform/host/spec.zig" -nt "$native/spec.o" ]; then
  (cd "$checkout/platform" && zig build-obj host/spec.zig -target x86_64-linux-musl -O ReleaseFast -fstrip -fPIC -femit-bin=targets/x64musl/spec.o)
fi

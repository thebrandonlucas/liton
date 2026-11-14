#!/usr/bin/env bash
# Downloads a speech model into $RIG_MODELS, checks its SHA-256 and unpacks
# it: `parakeet`, sherpa.sh's (a 482 MB download, 631 MB unpacked), or
# `whisper`, whisper.sh's (148 MB). One already there is left alone.
set -euo pipefail
source "$(dirname "$0")/env.sh"
mkdir -p "$RIG_MODELS"
cd "$RIG_MODELS"
case "${1:-}" in
	parakeet)
		name=sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8
		[ -f "$name/tokens.txt" ] && exit 0
		curl -fL --retry 3 -o "$name.tar.bz2.part" "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$name.tar.bz2"
		echo "6fc4426b54aa549a0019b8a75b8dea59164e71790a37ac56a045ad57f915f714  $name.tar.bz2.part" | sha256sum -c -
		tar -xjf "$name.tar.bz2.part" "$name/README.md" "$name/tokens.txt" "$name/encoder.int8.onnx" "$name/decoder.int8.onnx" "$name/joiner.int8.onnx"
		rm "$name.tar.bz2.part"
		;;
	whisper)
		name=ggml-base.en.bin
		[ -f "$name" ] && exit 0
		curl -fL --retry 3 -o "$name.part" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$name"
		echo "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002  $name.part" | sha256sum -c -
		mv "$name.part" "$name"
		;;
	*)
		echo "usage: $0 parakeet|whisper" >&2
		exit 2
		;;
esac

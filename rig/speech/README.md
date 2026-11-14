# A local speech rig

A speech engine for liton's `local-speech` provider (voice.v1, dictation), so
audio never leaves the machine. Either script downloads its model on first
run into `models/`, which git ignores, checks its SHA-256, and runs the
engine in the foreground. Without the engine on PATH, it runs under nixpkgs'.

```sh
rig/speech/sherpa.sh       # sherpa-onnx with Parakeet TDT 0.6B v2 int8, on port 6006
rig/speech/whisper.sh      # or whisper.cpp's whisper-server with base.en, on 127.0.0.1:8178
```

Then point liton's daemon at it:

```sh
LITON_STT=sherpa=ws://127.0.0.1:6006 zig build run
LITON_STT=whisper=http://127.0.0.1:8178 zig build run
LITON_STT=sherpa=ws://127.0.0.1:6006 node e2e/voice.mjs    # transcribes e2e/fixtures/utterance.wav
```

| | sherpa.sh | whisper.sh |
|---|---|---|
| engine | `sherpa-onnx-offline-websocket-server` (`nix shell nixpkgs#sherpa-onnx`, 337 MB) | `whisper-server` (`nix shell nixpkgs#whisper-cpp`) |
| model | [sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8.tar.bz2](https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8.tar.bz2), 482 MB, 631 MB unpacked, CC-BY-4.0 | [ggml-base.en.bin](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin), 148 MB, MIT |
| SHA-256 | `6fc4426b54aa549a0019b8a75b8dea59164e71790a37ac56a045ad57f915f714` | `a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002` |
| memory | about 1.2 GB | about 275 MB |
| 2.9 s fixture, through liton, on a busy 6-core desktop | 0.4-1 s | 1.1-1.6 s |

Parakeet is the more accurate and the faster; whisper base.en is the
low-memory fallback. `models.sh parakeet` or `models.sh whisper` downloads a
model alone.

- **Listening.** sherpa-onnx's server has no option for its address and
  listens on every interface; keep the port closed to the network with a
  firewall, or run it in a network namespace of its own. whisper-server
  listens on 127.0.0.1.
- **Settings.** `RIG_MODELS` (default `models/`), `RIG_SHERPA_PORT` (6006),
  `RIG_WHISPER_PORT` (8178) and `RIG_THREADS` (4) override the defaults in
  `env.sh`.

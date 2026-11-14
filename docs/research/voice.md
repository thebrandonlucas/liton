# Research: voice

How liton gets the `voice` capability (design.md, Capabilities): dictation into
any composer first, then a spoken conversation with an agent. Constraints:
local models first; audio in numbered, acknowledged chunks; audio off the JSON
control channel; replies spoken from the agent's own text; voice turns on
without touching the session; talking over the agent interrupts it; nothing
added to the cold load (vision.md).

Measurements below are from one 8.7 s English utterance (synthesized by Kokoro,
resampled to 16 kHz) on a 6-core x86_64 desktop (i7-8700, 2018) that was busy
(load average about 5), so treat them as upper bounds.

## 1. Speech-to-text

| | Parakeet TDT 0.6B v2 int8, sherpa-onnx | whisper.cpp `whisper-server` | faster-whisper | Vosk |
|---|---|---|---|---|
| nixpkgs | `sherpa-onnx` 1.13.8 (C++ binaries, cached), `python3Packages.sherpa-onnx` | `whisper-cpp` 1.9.5 (7.9 MB) | `python3Packages.faster-whisper` 1.2.1, `wyoming-faster-whisper` | not packaged |
| server | `sherpa-onnx-offline-websocket-server` (WebSocket, binary frames); no HTTP | HTTP `POST /inference`, multipart | none built in (Wyoming is TCP) | WebSocket (separate project) |
| measured, 8.7 s | **0.58 s** CLI (4 threads); 0.9-1.2 s round trip through the WebSocket server | base.en: 1.2-2.6 s per request | not measured | not measured |
| memory | 1.15-1.2 GB RSS; model 631 MB | base.en: 275 MB RSS; model 148 MB | small.en int8 about 0.5 GB | 50-300 MB |
| accuracy | best of these: transcribed the test verbatim with punctuation and case | base.en verbatim here, but clearly weaker on real speech; small.en/turbo close the gap at 3x-10x the cost | same models as whisper, faster on CPU | noticeably worse |
| partials | offline model: re-decode the growing buffer (Paseo does every 350 ms) | same (re-run `/inference`) | same | true streaming |
| licence | code Apache-2.0, model CC-BY-4.0 | MIT, models MIT | MIT | Apache-2.0 |

Not measured (models over the 200 MB budget): small.en (466 MB) should take
3-6 s and large-v3-turbo (1.6 GB f16, about 550 MB q5_0) 8-15 s for this
utterance on this CPU, because whisper's encoder always processes a 30 s
window. Neither beats Parakeet for English on CPU. whisper-cpp 1.9.5 also
ships `parakeet-cli` (ggml Parakeet v3), but no Parakeet server.

Paseo (0.9.2 and 0.15.3 alike, `sherpa-onnx-node` 1.12.28) runs Parakeet TDT
v2 int8 for dictation, Kokoro en v0.19 for speech and Silero VAD, in a Node
child process (`speech/providers/local/worker-process.js`) driven over Node
IPC (`session.create/append/commit`, `stt.transcribe`, `tts.synthesize`). That
worker is internal and unversioned, needs Node's `fork` IPC plus pino, zod,
uuid and the native addon, so it is not worth reusing standalone. Reuse its
choices instead: same models, same engine, but the stock binaries.

**Recommendation: Parakeet TDT 0.6B v2 int8 behind
`sherpa-onnx-offline-websocket-server`.** It is the most accurate and the
fastest here: under a second for a 15 s utterance, so partials are cheap.
It comes from the binary cache, with no Python and no Node. The daemon already
has a pure WebSocket client with binary frames (`providers/paseo/WebSocket.roc`).
`whisper-server` base.en is the low-memory fallback (275 MB versus 1.2 GB) and
has plain HTTP. One provider can speak to either engine.

```sh
# models: k2-fsa/sherpa-onnx releases, asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8.tar.bz2
M=$XDG_DATA_HOME/liton/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8
nix shell nixpkgs#sherpa-onnx -c sherpa-onnx-offline-websocket-server \
  --port=8097 --num-work-threads=1 --num-io-threads=1 --num-threads=4 \
  --model-type=nemo_transducer --tokens=$M/tokens.txt \
  --encoder=$M/encoder.int8.onnx --decoder=$M/decoder.int8.onnx --joiner=$M/joiner.int8.onnx
```

Its protocol (verified with a 15-line client): connect to `ws://127.0.0.1:8097`,
send one binary message: int32 LE sample rate, int32 LE byte count, then
float32 LE samples. You may split it across messages. One text message comes
back, `{"text": "...", "tokens": [...], "timestamps": [...]}`. Send `Done` and
close.

Fallback:

```sh
nix shell nixpkgs#whisper-cpp -c whisper-server -m ggml-base.en.bin --host 127.0.0.1 --port 8097 -t 4
curl 127.0.0.1:8097/inference -F file=@utt.wav -F response_format=json -F temperature=0.0
# {"text":" Please open the authentication module, ..."}   (16 kHz WAV; --convert needs ffmpeg)
```

## 2. Text-to-speech

- **Browser `speechSynthesis`:** no download and no server, in every browser.
  Quality and privacy depend on the voice. Apple platforms and Android ship
  good offline voices. Chrome's "Google ..." voices are network voices, so the
  text leaves the machine. Chromium and Firefox on Linux often have only
  espeak through speech-dispatcher, or nothing. Only `voice.localService ===
  true` voices are private.
- **Kokoro 82M (sherpa-onnx):** natural speech, Apache-2.0 model. fp32 v0.19
  (354 MB on disk) measured at RTF 0.44 for a long text (4 threads, 634 MB RSS,
  1.3 s load). Per sentence: 0.9 s for "Done.", 2.6 s for a 3.7 s sentence
  under load. That is faster than playback, so sentence-by-sentence
  pipelining keeps it continuous after the first sentence. sherpa-onnx ships
  no TTS server, only the CLI, which reloads the model every time, so Kokoro
  needs a small resident process. `python3Packages.sherpa-onnx` (cached) does
  it in about 60 lines (`OfflineTts(...).generate(text, sid, speed)`). The
  int8 and multi-language Kokoro builds in sherpa-onnx's releases are smaller
  and faster. I didn't measure them.

**Phase 1:** `speechSynthesis`, local voices only by default. The voice picker
lists `localService` voices first, and a non-local voice needs an explicit
choice. **Phase 2:** Kokoro from the voice provider (`Speak`, below), with
`speechSynthesis` as the fallback when no provider offers it.

## 3. Capture in the browser, through a roc-signals port

roc-signals 0.5 ports (`Port.roc`) fit capture well. A **subscription**
receives one argument and emits any number of messages until its site is
disposed (stop). It carries `Wire.Bytes` as `Uint8Array`s beside the JSON.
But the audio should not go through the app at all. Wasm memory, PortJson,
one message waiting per subscription (`Latest`/`Every(n)`), and a base64
round trip into a JSON `Http` body all add cost. So the port's JavaScript
POSTs chunks straight to the daemon's audio route, and tells the app only
what changed: started, levels, acks, ended, errors. This is also what "audio
off the JSON control channel" asks for.

**Lazy loading.** The runtime refuses to mount unless every declared port has
a handler, so `index.html` registers a stub of about 10 lines. Its
`subscribe` does `await import("./voice.mjs")` on first use, and `voice.mjs`
adds `voice-worklet.js` with `audioWorklet.addModule` only then. The cold
load gains about 300 bytes of inline script and nothing else.

```js
// index.html, in mountRocEngineApp's options
ports: { "liton/voice/capture": { subscribe(arg, ctx) {
  let stop = () => {};
  import("./voice.mjs").then((v) => { stop = v.capture(arg, ctx); }, (e) => ctx.close(String(e)));
  return () => stop();
} } },
```

`voice.mjs` (about 120 lines):

```js
export function capture({ utterance_id, endpoint, mode }, { emit, close, signal }) {
  let ctx, stream, node, seq = 0, unacked = new Map(), stopped = false;
  (async () => {
    stream = await navigator.mediaDevices.getUserMedia({ audio: {
      channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true } });
    ctx = new AudioContext();                       // device rate; the worklet resamples to 16 kHz
    await ctx.audioWorklet.addModule(new URL("./voice-worklet.js", import.meta.url));
    node = new AudioWorkletNode(ctx, "liton-capture", { processorOptions: { mode } });
    ctx.createMediaStreamSource(stream).connect(node);
    emit({ Started: { sample_rate: 16000 } });
    node.port.onmessage = ({ data }) => {             // data: { chunk: Int16Array (1 s) } | { level } | { speech: bool } | { end: true }
      if (data.chunk) send(seq++, data.chunk);
      else if (data.level !== undefined) emit({ Level: data.level });  // the app subscribes with delivery: Latest
      else if (data.speech !== undefined) emit(data.speech ? "SpeechStarted" : "SpeechEnded");
      else if (data.end) finish();
    };
  })().catch((e) => close(e.name === "NotAllowedError" ? "Denied" : String(e)));
  async function send(n, pcm) {                     // retried until acked; the daemon acks idempotently by (utterance, seq)
    unacked.set(n, pcm);
    for (let wait = 250; unacked.has(n) && !signal.aborted; wait = Math.min(wait * 2, 4000)) {
      try {
        const r = await fetch(`${endpoint}/liton/v1/audio/voice.v1/${utterance_id}/${n}`, {
          method: "POST", headers: { "Content-Type": "audio/L16;rate=16000;channels=1" }, body: pcm });
        const { acked } = await r.json();            // highest contiguous seq the daemon holds
        for (const k of unacked.keys()) if (k <= acked) unacked.delete(k);
        emit({ Acked: acked });
      } catch { await new Promise((r) => setTimeout(r, wait)); }
    }
  }
  function finish() { node?.port.postMessage("flush"); emit({ Ended: { last_seq: seq - 1 } }); }
  return () => { stopped = true; node?.port.postMessage("flush"); stream?.getTracks().forEach((t) => t.stop()); ctx?.close(); };
}
```

`voice-worklet.js` (about 50 lines) does three things per 128-sample render
quantum. It resamples to 16 kHz (linear interpolation, after averaging
neighbours as a crude low-pass, which is enough for speech). It converts to
Int16 and posts 1 s chunks (32 KB). It runs an **energy VAD** on 20 ms
frames: RMS in dBFS against an adaptive noise floor (the minimum over the last
few seconds, rising slowly), speech when 12 dB above the floor for 3 frames,
and the end after 700 ms below it. It keeps 300 ms of pre-roll so the first
syllable isn't clipped. In `Continuous` mode the end of speech ends the
utterance. In `PushToTalk` the stop does. A WASM Silero VAD in the browser
(onnxruntime-web, several MB) costs too much download. Silero belongs on the
provider side if the energy VAD proves too twitchy.

Roc side (`ui/`), one port and one site:

```roc
Capture : [Started({ sample_rate : U32 }), Level(U8), SpeechStarted, SpeechEnded, Acked(U64), Ended({ last_seq : U64 })]
capture : Port.Subscription({ utterance_id : Str, endpoint : Str, mode : [PushToTalk, Continuous] }, Capture)
capture = Port.subscription({ name: "liton/voice/capture", delivery: Every(16) })
```

The composer's mic button sets `Dictating({ utterance_id, level: 0 })` in the
same update, so it shows recording before anything answers (rules.md). The
site exists while the model is `Dictating` (`Engine.watch_latest` on it), so
leaving that state disposes it and stops the microphone. `Ended` sets
`Transcribing` and issues `voice.v1 Finish` through the existing
`/liton/v1/call` `Http` effect. The answer inserts the text at the caret, or
rolls back to the composer's text with the reason. A `Threw("Denied")` shows
how to allow the microphone. Partials, if followed, come from polling
`transcript/<utterance_id>` with the other topics.

**Permission UX.** Ask on the first press of the mic button, never at load.
`getUserMedia` exists only in a secure context, which means `localhost` or
HTTPS. A daemon reached by plain `http://` on another host has no microphone,
and the button should say so rather than fail. Browsers remember the grant
per origin. Dictation is tap to start and tap to stop, plus a held key.
Conversation mode is continuous with VAD endpointing.

## 4. Transport and `voice.v1`

The arithmetic: 16 kHz, 16-bit mono is 32 KB/s, so 15 s is 480 KB raw, or
640 KB as base64. A single `Transcribe({ audio: base64 })` call would fit the
~8 MB request bodies basic-webserver allows (about 3 minutes). But it breaks
two design rules: audio would ride in JSON, and a dropped link would lose the
whole utterance. It also means nothing reaches the daemon until the speaker
stops. (The daemon reads JSON bodies with a 64 KiB limit today, `read_json!`.
The audio route needs its own limit, about 64 KB per 1 s chunk.)

**Audio route** (new, beside `call` and `poll`):

```
POST /liton/v1/audio/voice.v1/<utterance_id>/<seq>      body: audio/L16;rate=16000;channels=1 (raw bytes)
→ {"Ok": {"acked": 4}}     highest contiguous seq held; a repeat of a held seq is a no-op
```

The daemon stores chunks in SQLite (`voice_chunks(utterance_id, seq, pcm,
at)`, dropped after 10 minutes). No connection is held and no background work
runs, so it fits basic-webserver.

**`voice.v1`** in `capabilities/Voice.roc`:

```roc
Request : [
    Begin({ utterance_id : Str, purpose : [Dictation, Conversation({ session_id : Str })] }),
    Finish({ utterance_id : Str, last_seq : U64 }),
    Cancel({ utterance_id : Str }),
    Speak({ text : Str, voice : Try(Str, [Default]) }),  # phase 2
    ListVoices,                                            # phase 2
]
Response : [Accepted, Transcript({ text : Str }), Missing({ from_seq : U64 }), Speech({ audio_id : Str, sample_rate : U32 }), Voices(List(Str))]
```

| topic | kind | event |
|---|---|---|
| `transcript/<utterance_id>` | snapshot | `{"Transcript": {"text", "final"}}` |
| `status` | snapshot | `{"Status": {"stt": Ready \| Loading \| Down(reason), "tts": ...}}` |

- `Finish` waits until every seq up to `last_seq` is held, decodes the whole
  utterance once, and answers `Transcript`. If chunks are missing it answers
  `Missing` and the client resends them. One round trip after the speaker
  stops, about 1 s.
- Partials follow the existing pattern (protocol.md, Subscribe). Polling
  `transcript/<id>` notes it as wanted, and the poll re-decodes the held audio
  at most once per second, so a client that ignores partials costs nothing.
- `Speak` (phase 2) synthesizes and answers an id. Audio comes back raw and
  outside JSON from `GET /liton/v1/audio/voice.v1/speech/<audio_id>` (WAV),
  which the client plays through `AudioContext` or `<audio>`.

**Providers.**

- **`local-speech`, compiled in** (`providers/local-speech/`): a pure state
  machine whose effects the daemon performs. `Finish` reads the chunks,
  converts Int16 to float32, and sends one binary WebSocket message to the
  sherpa-onnx server, reusing `WebSocket.roc`. With
  `LITON_STT=whisper=http://127.0.0.1:8097` it instead sends a multipart POST
  to `whisper-server`'s `/inference`. `LITON_STT` unset means voice.v1 isn't
  offered, and the mic button is a placeholder naming it.
- **Paseo**, when its `server_info` advertises `voice.dictation.enabled`: the
  daemon can't hold Paseo's WebSocket across chunks, so `Finish` opens one
  connection and sends `dictation_stream_start` (`format:
  "audio/pcm;rate=16000;bits=16"`), every `dictation_stream_chunk` (seq,
  base64), and `dictation_stream_finish` (`finalSeq`). It then reads
  `dictation_stream_final` before the `finish_accepted` timeout runs out.
  That is one connection per utterance, within Paseo's load budget, with no
  partials until the daemon can hold connections. It's useful when the
  daemon and Paseo run on another machine that already has the models.
- **Outside the daemon**: a voice provider serving `/liton/v1` works once
  remotes route `voice.v1` and forward the audio route. Phase 2's Kokoro
  process could be that provider.

**Conversation mode, split by side.**

| | client | daemon / provider |
|---|---|---|
| turn on | a mode in the chat widget; the session is untouched (no reload, no voice mode upstream) | nothing |
| listen | continuous capture, VAD ends each utterance; `Finish` then `chat.v1 SendMessage` with the transcript | STT |
| speak replies | follows `timeline/<session_id>` as it already does; agent text after the voice turn is split into sentences and spoken (phase 1 `speechSynthesis`, phase 2 `Speak` per sentence, prefetching the next one); code blocks and tool output are skipped or summarized ("code block, 12 lines") | phase 2 TTS |
| barge-in | while speaking, VAD speech of at least 300 ms (echo cancellation on, so the agent's own voice doesn't count) stops playback at once and calls `chat.v1 Interrupt` | `Interrupt` maps to Paseo's `cancel_agent_request` |

`chat.v1` gains `Interrupt({ session_id })`, an additive change. It's useful
without voice too, as a stop button.

## 5. Privacy and footprint

- Audio never leaves the machine that runs the daemon. The browser POSTs only
  to its own daemon, and the providers are local processes. Chunks live in
  SQLite for at most 10 minutes. Browser `SpeechRecognition` is not used
  (Chrome sends the audio to Google). Network TTS voices need an explicit
  choice.
- Browser cost: about 300 B inline stub at cold load. On first use,
  `voice.mjs` (about 5 KB, 2 KB gzipped) and `voice-worklet.js` (about 2 KB).
  The Roc side adds a few KB to `app.wasm`. Capture uses about 1 MB of memory
  while active.
- Daemon side: Parakeet 1.2 GB RSS, or whisper base.en 275 MB, plus Kokoro
  about 650 MB in phase 2. These are separate opt-in processes, so liton's
  daemon itself grows only by the provider code. Model downloads (631 MB
  Parakeet, 148 MB base.en, 354 MB Kokoro) are the user's choice, made in
  their own setup.
- The benchmarks (vision.md) gain "time from end of speech to transcript in
  the composer" for liton against Paseo's dictation.

## Phase 1: dictation

1. `capabilities/Voice.roc`: the `voice.v1` types and codecs, `Begin`,
   `Finish`, `Cancel`, and the `transcript` and `status` topics.
2. Daemon: the `POST /liton/v1/audio/voice.v1/<id>/<seq>` route, the
   `voice_chunks` table, and cleanup.
3. `providers/local-speech/`: the sherpa-onnx WebSocket backend, the
   `whisper-server` HTTP backend, `LITON_STT`, and an entry for
   `sherpa-onnx-offline-websocket-server` in the Kaifile/dev env.
4. UI: the stub port in `index.html`, `voice.mjs` and `voice-worklet.js`
   copied to `zig-out/www`, the `liton/voice/capture` subscription, the mic
   button and states (Dictating, Transcribing, Denied, Unavailable) in the
   composer, with specs asserting the pending state before `run-effect`.
5. `protocol.md`: the audio route and `voice.v1`.

## Phase 2: conversation

1. `chat.v1 Interrupt`, in the Paseo provider as `cancel_agent_request`.
2. Partials: the `transcript/<id>` topic re-decoded at most once per second.
3. Conversation mode in the chat widget: continuous capture, auto-send,
   sentence-split speaking with `speechSynthesis`, and barge-in.
4. A Kokoro speech process (Python with `sherpa_onnx`, about 60 lines, from
   nixpkgs), `Speak` and `ListVoices`, and `GET .../speech/<audio_id>`.
5. Optionally, the Paseo dictation backend, and Silero VAD on the provider
   side.

// liton's voice, which ui/ports.mjs loads on first use: records an utterance
// (voice-worklet.js), posts each 1 s chunk to the daemon's audio route until
// acked, and asks voice.v1 for the transcript (docs/protocol.md, Audio). The
// app hears only what changed (ui/Speech.roc, Heard) and says what to do
// (Order).

let recording = null; // the one capture at a time: { serial, stop }
let stopped; // the last stop ordered

// Records for the composer of `pane` until stopped, and reports the
// transcript once the daemon holds every chunk of it.
export function capture({ pane, serial }, { emit, close }) {
  let stream, context, node, utterance = null, gone = false, stopping = false;
  const release = () => {
    stream?.getTracks().forEach((track) => track.stop());
    context?.close().catch(() => {});
    stream = context = undefined;
  };
  const ended = async () => {
    const said = utterance;
    utterance = null;
    if (!said) return;
    release();
    emit("Transcribing");
    try {
      await Promise.all(said.posts);
      const text = await transcript(said.id, said.seq - 1);
      if (!gone) emit({ Transcript: { text, ...selection(pane) } });
    } catch (error) {
      if (!gone) emit({ NotTranscribed: String(error?.message ?? error) });
    }
  };
  recording = { serial, stop: () => (node ? node.port.postMessage("flush") : (stopping = true)) };
  (async () => {
    if (!navigator.mediaDevices?.getUserMedia) throw new Error("the microphone needs a secure page: HTTPS, or localhost");
    stream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true } });
    context = new AudioContext();
    await context.audioWorklet.addModule(new URL("./voice-worklet.js", import.meta.url));
    if (gone) return release();
    node = new AudioWorkletNode(context, "liton-capture");
    context.createMediaStreamSource(stream).connect(node);
    utterance = { id: crypto.randomUUID(), seq: 0, posts: [] };
    node.port.onmessage = ({ data }) => {
      if (data.level !== undefined) emit({ Level: data.level });
      else if (data.chunk) utterance?.posts.push(post(utterance.id, utterance.seq++, data.chunk));
      else if (data.end) ended();
    };
    if (stopping) node.port.postMessage("flush");
  })().catch((error) => {
    release();
    close(error?.name === "NotAllowedError" || error?.name === "SecurityError" ? "Denied" : String(error?.message ?? error));
  });
  return () => {
    gone = true;
    release();
    if (recording?.serial === serial) recording = null;
  };
}

// Does what the app says, as it changes: ends a dictation.
export function order({ stop }) {
  if (stop !== stopped && recording?.serial === stop) recording.stop();
  stopped = stop;
}

const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Posts a chunk until the daemon holds it, waiting longer after each
// failure; one it refuses fails the utterance.
async function post(utterance_id, seq, pcm) {
  for (let pause = 250; ; pause = Math.min(pause * 2, 4000)) {
    try {
      const response = await fetch(`/liton/v1/audio/voice.v1/${utterance_id}/${seq}`, { method: "POST", headers: { "Content-Type": "audio/L16;rate=16000;channels=1" }, body: pcm });
      const answer = await response.json();
      if (answer.Ok) return;
      if (answer.Err?.code === "BadRequest" || answer.Err?.code === "Unsupported") throw new Error(answer.Err.message);
    } catch (error) {
      if (!(error instanceof TypeError || error instanceof SyntaxError)) throw error;
    }
    await wait(pause);
  }
}

// The transcript of the chunks 0 to `last_seq`, asked again while the
// daemon can't be reached.
async function transcript(utterance_id, last_seq) {
  for (let pause = 250; ; pause = Math.min(pause * 2, 4000)) {
    try {
      const response = await fetch("/liton/v1/call", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ capability: "voice.v1", request: { Finish: { utterance_id, last_seq } } }) });
      const answer = await response.json();
      if (answer.Ok?.Transcript) return answer.Ok.Transcript.text;
      throw new Error(answer.Ok?.Missing ? "some of the audio didn't reach the daemon" : answer.Err?.message ?? "the daemon didn't transcribe it");
    } catch (error) {
      if (!(error instanceof TypeError || error instanceof SyntaxError)) throw error;
    }
    await wait(pause);
  }
}

// Where the composer's selection is, as byte offsets into its text, for the
// transcript to replace; past the end when there is no composer.
function selection(pane) {
  const box = document.querySelector(`[data-voice-pane="${CSS.escape(pane)}"]`)?.closest("form")?.querySelector("textarea");
  if (!box) return { from: Number.MAX_SAFE_INTEGER, to: Number.MAX_SAFE_INTEGER };
  const bytes = (end) => new TextEncoder().encode(box.value.slice(0, end)).length;
  return { from: bytes(box.selectionStart), to: bytes(box.selectionEnd) };
}

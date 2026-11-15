// liton's voice, which ui/ports.mjs loads on first use: records utterances
// (voice-worklet.js), posts each 1 s chunk to the daemon's audio route until
// acked, and asks voice.v1 for the transcript (docs/protocol.md, Audio); and
// speaks a conversation's replies with the browser's speechSynthesis. The
// app hears only what changed (ui/Speech.roc, Heard) and says what to do
// (Order).

const key = "liton.voice";
let recording = null; // the one capture at a time: { serial, emit, stop, speaking }
let stopped; // the last stop ordered
const spoken = new Set(); // the replies spoken, as `<session>/<sequence>`
let queued = 0; // sentences speechSynthesis has yet to finish
let talking = false;

// Records for the composer of `pane`: one utterance until stopped, or, in a
// conversation, one each time the VAD hears speech, and reports each one's
// transcript once the daemon holds every chunk of it.
export function capture({ pane, mode, serial }, { emit, close }) {
  const continuous = mode === "Conversation";
  let stream, context, node, utterance = null, gone = false, stopping = false;
  const begin = () => (utterance = { id: crypto.randomUUID(), seq: 0, posts: [] });
  const release = () => {
    stream?.getTracks().forEach((track) => track.stop());
    context?.close().catch(() => {});
    stream = context = undefined;
  };
  const ended = async () => {
    const said = utterance;
    utterance = null;
    if (!said) return;
    if (!continuous) release();
    emit("Transcribing");
    try {
      await Promise.all(said.posts);
      const text = await transcript(said.id, said.seq - 1);
      if (!gone) emit({ Transcript: { text, ...selection(pane) } });
    } catch (error) {
      if (!gone) emit({ NotTranscribed: String(error?.message ?? error) });
    }
  };
  recording = { serial, emit, stop: () => (node ? node.port.postMessage("flush") : (stopping = true)), speaking: (speaking) => node?.port.postMessage({ speaking }) };
  (async () => {
    if (!navigator.mediaDevices?.getUserMedia) throw new Error("the microphone needs a secure page: HTTPS, or localhost");
    stream = await navigator.mediaDevices.getUserMedia({ audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true, autoGainControl: true } });
    context = new AudioContext();
    await context.audioWorklet.addModule(new URL("./voice-worklet.js", import.meta.url));
    if (gone) return release();
    node = new AudioWorkletNode(context, "liton-capture", { processorOptions: { continuous } });
    context.createMediaStreamSource(stream).connect(node);
    if (!continuous) begin();
    node.port.onmessage = ({ data }) => {
      if (data.level !== undefined) emit({ Level: data.level });
      else if (data.chunk) utterance?.posts.push(post(utterance.id, utterance.seq++, data.chunk));
      else if (data.begin) begin();
      else if (data.barge) {
        hush();
        emit("BargedIn");
      } else if (data.end) ended();
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
    if (continuous) hush();
  };
}

// Does what the app says, as it changes: ends a dictation, speaks the
// replies not spoken yet, and keeps the voice and rate picked.
export function order({ stop, session, replies, picked }) {
  if (stop !== stopped && recording?.serial === stop) recording.stop();
  stopped = stop;
  if (picked.Picked) localStorage.setItem(key, JSON.stringify(picked.Picked));
  for (const { sequence, text } of replies) {
    if (spoken.has(`${session}/${sequence}`)) continue;
    spoken.add(`${session}/${sequence}`);
    speak(text);
  }
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

const chosen = () => {
  try {
    return JSON.parse(localStorage.getItem(key)) ?? {};
  } catch {
    return {};
  }
};

async function listed() {
  let voices = speechSynthesis.getVoices();
  if (voices.length === 0) {
    await new Promise((resolve) => {
      speechSynthesis.addEventListener("voiceschanged", resolve, { once: true });
      setTimeout(resolve, 1000);
    });
    voices = speechSynthesis.getVoices();
  }
  const language = navigator.language.split("-")[0];
  const fitting = voices.filter((voice) => voice.lang.startsWith(language));
  return (fitting.length > 0 ? fitting : voices).sort((a, b) => b.localService - a.localService);
}

// The voices settings offer, those on the device first, and the voice and
// rate picked.
export async function voices() {
  const { voice = "default", rate = "1" } = chosen();
  return { voices: (await listed()).slice(0, 11).map((offered) => ({ name: offered.name, local: offered.localService })), voice, rate };
}

// Speaks a reply sentence by sentence in the voice picked, else the first
// on the device: an online voice, which sends the text away, only if picked.
async function speak(text) {
  const { voice: name, rate = "1" } = chosen();
  const offered = await listed();
  const voice = offered.find((candidate) => candidate.name === name) ?? offered.find((candidate) => candidate.localService);
  if (!voice) return;
  for (const sentence of sentences(text)) {
    const said = Object.assign(new SpeechSynthesisUtterance(sentence), { voice, lang: voice.lang, rate: Number(rate) || 1 });
    said.onstart = () => speaking(true);
    said.onend = said.onerror = () => (queued = Math.max(0, queued - 1)) || speaking(false);
    queued++;
    speechSynthesis.speak(said);
  }
}

function speaking(now) {
  if (talking === now) return;
  talking = now;
  recording?.speaking(now);
  recording?.emit({ Speaking: now });
}

function hush() {
  queued = 0;
  speechSynthesis.cancel();
  speaking(false);
}

// A reply's sentences, its Markdown read as text: a code block or a list of
// more than four items is named, not read.
export function sentences(text) {
  const said = [];
  text.split(/^\s*```.*$/m).forEach((part, index) => {
    if (index % 2 === 1) {
      const lines = part.trim().split("\n").length;
      return said.push(`A code block of ${lines} line${lines === 1 ? "" : "s"}.`);
    }
    for (const block of part.split(/\n\s*\n/)) {
      const lines = block.split("\n");
      const item = (line) => /^\s*([-*+]|\d+[.)])\s/.test(line);
      const items = lines.filter(item).length;
      const read = (items > 4 ? lines.filter((line) => !item(line)) : lines).map((line) => (item(line) && !/[.!?:]$/.test(line.trim()) ? `${line}.` : line));
      said.push(...plain(read.join("\n")).split(/(?<=[.!?])\s+/));
      if (items > 4) said.push(`A list of ${items} items.`);
    }
  });
  return said.map((sentence) => sentence.trim()).filter((sentence) => /\w/.test(sentence));
}

const plain = (markdown) =>
  markdown
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/`([^`]*)`/g, "$1")
    .replace(/^\s*(#+|>|[-*+]|\d+[.)])\s+/gm, "")
    .replace(/[*_~]+/g, "")
    .replace(/\n/g, " ");

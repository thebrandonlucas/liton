// liton's capture, in the audio thread (ui/voice.mjs adds it): resamples the
// microphone to 16 kHz 16-bit mono, posts it in 1 s chunks and its level, of
// each 100 ms, in dBFS from -60 to -10 as 0 to 100, and finds speech with an
// energy VAD on 20 ms frames, against a noise floor that follows the
// quietest frames and rises slowly. Speech starts 12 dB over the floor for
// 60 ms and ends after 700 ms under it. A conversation records only from
// 300 ms before speech starts to its end, each an utterance of its own, and
// not at all while a reply is spoken and for 400 ms after, as the microphone
// would hear the speakers; dictation records until flushed.
const rate = 16000, frame = 320, preroll = 4800, tail = 0.4;

class Capture extends AudioWorkletProcessor {
  constructor({ processorOptions }) {
    super();
    this.continuous = processorOptions.continuous;
    this.step = sampleRate / rate; // input samples per output sample
    this.next = 1;
    this.previous = 0;
    this.smooth = 0;
    this.alpha = 1 - Math.exp((-2 * Math.PI * 7000) / sampleRate); // a one-pole low-pass under 8 kHz
    this.chunk = new Int16Array(rate);
    this.posted = 0;
    this.filled = 0;
    this.ring = new Int16Array(preroll);
    this.ringAt = 0;
    this.energy = 0;
    this.counted = 0;
    this.frames = 0;
    this.floor = Infinity;
    this.loud = 0;
    this.quiet = 0;
    this.speech = false;
    this.paused = 0; // the time to listen again from, while a reply is spoken
    this.recording = !this.continuous;
    this.port.onmessage = ({ data }) => {
      if (data === "flush") this.end();
      else if (this.continuous) this.pause(data.speaking);
    };
  }

  process(inputs) {
    const input = inputs[0]?.[0];
    if (!input) return true;
    for (let i = 0; i < input.length; i++) {
      this.smooth += this.alpha * (input[i] - this.smooth);
      for (; this.next <= 1; this.next += this.step) this.sample(this.previous + (this.smooth - this.previous) * this.next);
      this.next -= 1;
      this.previous = this.smooth;
    }
    return true;
  }

  sample(value) {
    if (currentTime < this.paused) return;
    const pcm = Math.max(-32768, Math.min(32767, Math.round(value * 32767)));
    if (this.recording) this.keep(pcm);
    else {
      this.ring[this.ringAt] = pcm;
      this.ringAt = (this.ringAt + 1) % preroll;
    }
    this.energy += value * value;
    if (++this.counted === frame) this.frameEnded();
  }

  frameEnded() {
    const db = 10 * Math.log10(this.energy / frame + 1e-12);
    this.energy = this.counted = 0;
    if (++this.frames % 5 === 0) this.port.postMessage({ level: Math.round(Math.max(0, Math.min(100, ((db + 60) / 50) * 100))) });
    this.floor = db < this.floor ? db : this.floor + 0.02;
    if (db > this.floor + 12 && db > -55) {
      this.quiet = 0;
      if (!this.speech && ++this.loud >= 3) this.started();
    } else {
      this.loud = 0;
      if (this.speech && ++this.quiet >= 35) {
        this.speech = false;
        if (this.continuous) this.end();
      }
    }
  }

  // Stops listening as a reply starts being spoken, ending the utterance
  // there, and listens again, afresh, `tail` after it stops.
  pause(speaking) {
    if (!speaking) {
      if (this.paused === Infinity) this.paused = currentTime + tail;
      return;
    }
    this.paused = Infinity;
    this.end();
    this.speech = false;
    this.loud = this.quiet = this.energy = this.counted = 0;
    this.ring.fill(0);
    this.port.postMessage({ level: 0 });
  }

  started() {
    this.speech = true;
    if (this.recording) return;
    this.recording = true;
    this.port.postMessage({ begin: true });
    for (let i = 0; i < preroll; i++) this.keep(this.ring[(this.ringAt + i) % preroll]);
  }

  keep(pcm) {
    this.chunk[this.filled++] = pcm;
    if (this.filled === rate) this.post();
  }

  post() {
    const chunk = this.chunk.slice(0, this.filled);
    this.port.postMessage({ chunk }, [chunk.buffer]);
    this.posted++;
    this.filled = 0;
  }

  // Posts what is left of the utterance, at least 100 ms of it, and ends it.
  end() {
    if (!this.recording) return;
    if (this.posted === 0) while (this.filled < frame * 5) this.chunk[this.filled++] = 0;
    if (this.filled > 0) this.post();
    this.recording = false;
    this.posted = 0;
    this.port.postMessage({ end: true });
  }
}

registerProcessor("liton-capture", Capture);

// liton's capture, in the audio thread (ui/voice.mjs adds it): resamples the
// microphone to 16 kHz 16-bit mono, posts it in 1 s chunks until flushed,
// and its level, of each 100 ms, in dBFS from -60 to -10 as 0 to 100.
const rate = 16000, frame = 320;

class Capture extends AudioWorkletProcessor {
  constructor() {
    super();
    this.step = sampleRate / rate; // input samples per output sample
    this.next = 1;
    this.previous = 0;
    this.smooth = 0;
    this.alpha = 1 - Math.exp((-2 * Math.PI * 7000) / sampleRate); // a one-pole low-pass under 8 kHz
    this.chunk = new Int16Array(rate);
    this.posted = 0;
    this.filled = 0;
    this.energy = 0;
    this.counted = 0;
    this.frames = 0;
    this.recording = true;
    this.port.onmessage = ({ data }) => {
      if (data === "flush") this.end();
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
    if (this.recording) this.keep(Math.max(-32768, Math.min(32767, Math.round(value * 32767))));
    this.energy += value * value;
    if (++this.counted === frame) this.frameEnded();
  }

  frameEnded() {
    const db = 10 * Math.log10(this.energy / frame + 1e-12);
    this.energy = this.counted = 0;
    if (++this.frames % 5 === 0) this.port.postMessage({ level: Math.round(Math.max(0, Math.min(100, ((db + 60) / 50) * 100))) });
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

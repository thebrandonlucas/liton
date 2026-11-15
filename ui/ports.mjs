// liton: what the app (app.wasm, from ui/) asks of the page that
// roc-signals 0.5.0 does not model. The ports are declared in ui/Ports.roc.

// Enter in a chat's composer sends the message, and Shift+Enter starts a
// new line. On a touch screen, whose keyboard has no Shift+Enter, Enter
// starts a new line and Send sends. roc-signals 0.5.0 tells a key handler
// no modifiers, nor lets it keep only some keys from the box (roc-issues
// RS-004, lukewilliamboswell/roc-signals#212).
document.addEventListener("keydown", (event) => {
  const box = event.target;
  if (event.key !== "Enter" || event.shiftKey || event.isComposing || !box.matches?.(".composer textarea")) return;
  if (matchMedia("(pointer: coarse)").matches) return;
  event.preventDefault();
  box.form.requestSubmit();
}, true);

// Voice (ui/Speech.roc) loads ui/voice.mjs and its worklet on first use only.
const voice = () => import("./voice.mjs");

export default {
  // Copies text, answering whether the browser let it. The clipboard API
  // needs a secure context; a page served over plain HTTP from another
  // machine falls back to the older copy command.
  "liton/copy": {
    call: async (text) => {
      try {
        await navigator.clipboard.writeText(text);
        return true;
      } catch {
        const area = Object.assign(document.createElement("textarea"), { value: text });
        area.style.position = "fixed";
        area.style.opacity = "0";
        document.body.append(area);
        area.select();
        const copied = document.execCommand("copy");
        area.remove();
        return copied;
      }
    },
  },
  "liton/voice/capture": {
    subscribe(asked, port) {
      let stop, gone;
      voice().then((v) => gone || (stop = v.capture(asked, port)), port.close);
      return () => (gone = true) && stop?.();
    },
  },
  "liton/voice/order": { command: (asked) => voice().then((v) => v.order(asked)) },
  "liton/voice/voices": { call: () => voice().then((v) => v.voices()) },
};

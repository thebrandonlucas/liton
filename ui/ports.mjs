// liton: what the app (app.wasm, from ui/) asks of the page that
// roc-signals does not model. The ports are declared in ui/Ports.roc.

// A chat shows its latest entries; scrolling up to within a screen of its
// Show earlier button presses it, so earlier entries come as they are read.
document.addEventListener("scroll", (event) => {
  const box = event.target;
  const earlier = box.matches?.(".timeline-scroll") && box.querySelector(":scope > .earlier > .show-earlier");
  if (earlier && earlier.getBoundingClientRect().bottom > box.getBoundingClientRect().top - box.clientHeight) earlier.click();
}, { capture: true, passive: true });

// FIXME: roc-signals's boot doesn't tell the platform, so the page writes
// whether it is a Mac, whose keys liton writes as ⌘B, for the app to read
// at boot (`Liton.platform_key`). Drop this once the boot carries it.
try {
  const platform = navigator.userAgentData?.platform ?? navigator.platform ?? "";
  sessionStorage.setItem("liton.platform", /^(mac|iphone|ipad|ipod)/i.test(platform) ? "mac" : "other");
} catch {}

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

// liton: what the app (app.wasm, from ui/) asks of the page that
// roc-signals 0.5.0 does not model. The ports are declared in ui/Ports.roc.
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
};

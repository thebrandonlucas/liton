## What the UI asks of the page's JavaScript (ui/ports.mjs) that
## roc-signals 0.5.0 does not model: copying text to the clipboard, and
## voice (ui/Speech.roc).
import pf.Engine
import pf.Port
import Speech

Ports := [].{

	## Copies text, answering whether the browser let it.
	copy : Port.Call(Str, Bool)
	copy = Port.call({ name: "liton/copy", timeout: Ms(5000) })

	registrations : List(Engine.PortRegistration)
	registrations = [Ports.copy.registration()].concat(Speech.registrations)
}

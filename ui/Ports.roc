## What the UI asks of the page's JavaScript (ui/ports.mjs) that
## roc-signals does not model: copying text where the clipboard API is not
## offered (a page served over plain HTTP from another machine), and
## voice (ui/Speech.roc).
import pf.Engine
import pf.Port
import Speech

Ports := [].{

	## Copies text, answering whether the browser let it.
	copy : Port.Call(Str, Bool)
	copy = Port.call({ name: "liton/copy", timeout: Ms(5000) })

	registrations : List(Engine.PortRegistration)
	registrations = Port.registrations({ copy: Ports.copy, capture: Speech.capture, order: Speech.order, voices: Speech.voices })
}

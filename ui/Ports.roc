## What the UI asks of the page's JavaScript (ui/ports.mjs) that
## roc-signals does not model: copying text where the clipboard API is not
## offered (a page served over plain HTTP from another machine), voice
## (ui/Speech.roc), and the pointer while a pane is dragged (ui/Drag.roc).
import pf.Engine
import pf.Port
import Drag
import Speech

Ports := [].{

	## Copies text, answering whether the browser let it.
	copy : Port.Call(Str, Bool)
	copy = Port.call({ name: "liton/copy", timeout: Ms(5000) })

	registrations : List(Engine.PortRegistration)
	registrations = Port.registrations({ copy: Ports.copy, capture: Speech.capture, drag: Drag.pointer, order: Speech.order, voices: Speech.voices })
}

## What the UI asks of the page's JavaScript (ui/ports.mjs) that
## roc-signals does not model: copying text where the clipboard API is not
## offered (a page served over plain HTTP from another machine), voice
## (ui/Speech.roc), the pointer while a pane is dragged (ui/Drag.roc), and a
## trackpad's swipe across the page.
import pf.Engine
import pf.Port
import Drag
import Speech

Ports := [].{

	## Copies text, answering whether the browser let it.
	copy : Port.Call(Str, Bool)
	copy = Port.call({ name: "liton/copy", timeout: Ms(5000) })

	## A two-finger swipe across a trackpad, not over something that
	## scrolls across, as "next" or "previous": the deck's next surface is
	## where the fingers move away from, as a page is turned.
	swipe : Port.Subscription({}, Str)
	swipe = Port.subscription({ name: "liton/deck/swipe", delivery: Every(8) })

	registrations : List(Engine.PortRegistration)
	registrations = Port.registrations({ copy: Ports.copy, capture: Speech.capture, drag: Drag.pointer, order: Speech.order, voices: Speech.voices, swipe: Ports.swipe })
}

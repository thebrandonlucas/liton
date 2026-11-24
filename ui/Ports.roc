## What the UI asks of the page's JavaScript (ui/ports.mjs) that
## roc-signals does not model: copying text where the clipboard API is not
## offered (a page served over plain HTTP from another machine), voice
## (ui/Speech.roc), the pointer while a pane is dragged (ui/Drag.roc),
## a trackpad's swipe across the page, and passkeys, which the browser
## makes and uses (navigator.credentials).
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

	## A passkey made (`create`), or used to sign in, as the daemon's
	## `options` ask, called `name` and for the person `person_name`
	## names: what /liton/v1/login/finish or
	## /liton/v1/passkeys/register/finish takes, as JSON.
	passkey : Port.Call({ create : Bool, options : Str, name : Str, person_name : Str }, Str)
	passkey = Port.call({ name: "liton/passkey", timeout: Ms(300000) })

	## The ports the page's JavaScript answers.
	registrations : List(Engine.PortRegistration)
	registrations = Port.registrations({ copy: Ports.copy, capture: Speech.capture, drag: Drag.pointer, order: Speech.order, voices: Speech.voices, swipe: Ports.swipe, passkey: Ports.passkey })
}

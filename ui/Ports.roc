## What the UI asks of the page's JavaScript (ui/ports.mjs) that
## roc-signals does not model: copying text where the clipboard API is not
## offered (a page served over plain HTTP from another machine), voice
## (ui/Speech.roc), the pointer while a pane is dragged (ui/Drag.roc), a
## trackpad's swipe across the page, and this browser's Nostr key, which
## signs the events of the rooms that take them (ui/nostr.mjs).
import pf.Engine
import pf.Port
import Model
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

	## This browser's Nostr public key, as hex, its secret made on first use.
	key : Port.Call({}, Str)
	key = Port.call({ name: "liton/nostr/key", timeout: Ms(10000) })

	## The event of a kind, tags and content, made now and signed.
	sign : Port.Call({ kind : U32, tags : List(List(Str)), content : Str }, Model.Signed)
	sign = Port.call({ name: "liton/nostr/sign", timeout: Ms(10000) })

	## The ports the page's JavaScript answers.
	registrations : List(Engine.PortRegistration)
	registrations = Port.registrations({ copy: Ports.copy, capture: Speech.capture, drag: Drag.pointer, order: Speech.order, voices: Speech.voices, swipe: Ports.swipe, key: Ports.key, sign: Ports.sign })
}

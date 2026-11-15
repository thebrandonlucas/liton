## What voice in the chat composer is doing, and the ports to the page's
## JavaScript that records (ui/voice.mjs, which ui/ports.mjs loads on first
## use). The audio itself never reaches the app: the page posts it to the
## daemon's audio route (docs/protocol.md, Audio), asks voice.v1 for its
## transcript, and tells the app only what changed.
import cap.Voice
import pf.Engine
import pf.Port

Speech := [].{

	## `engine` is the daemon's speech engine. The microphone records for the
	## pane `pane`, `serial` counting recordings. `held` follows a press of
	## the mic button, held once the page reports levels for a moment, which
	## records until released; `swallow_click` eats the click that ends such
	## a press. `stopping` asks the page to end the recording numbered so.
	State : {
		engine : Voice.Engine,
		pane : Str,
		phase : [Idle, Listening, Transcribing, Failed(Str)],
		serial : U64,
		level : U8,
		held : [Up, Pressed(U8), Held],
		swallow_click : Bool,
		stopping : U64,
	}

	initial : State
	initial = {
		engine: Down("checking the speech engine"),
		pane: "",
		phase: Idle,
		serial: 0,
		level: 0,
		held: Up,
		swallow_click: Bool.False,
		stopping: 0,
	}

	## What the page tells of a recording: the input's level, 0 to 100; the
	## utterance ended and is being transcribed; its transcript, and where
	## the composer's selection then was, as byte offsets into the draft, or
	## why there is none.
	Heard : [Level(U8), Transcribing, Transcript({ text : Str, from : U64, to : U64 }), NotTranscribed(Str)]

	## Records from the microphone while subscribed, until stopped.
	capture : Port.Subscription({ pane : Str, serial : U64 }, Heard)
	capture = Port.subscription({ name: "liton/voice/capture", delivery: Every(64) })

	## What the page is to do, as it changes: end the dictation numbered
	## `stop`, posting what is left.
	Order : { stop : U64 }

	order : Port.Command(Order)
	order = Port.command({ name: "liton/voice/order" })

	registrations : List(Engine.PortRegistration)
	registrations = [Speech.capture.registration(), Speech.order.registration()]

	## Whether the microphone is in use.
	active : State -> Bool
	active = |voice| voice.phase == Listening or voice.phase == Transcribing

	## `text` put in place of the bytes `from` to `to` of `draft`, a space
	## apart from the words beside it.
	insert : Str, U64, U64, Str -> Str
	insert = |draft, from, to, text| {
		bytes = draft.to_utf8()
		start = from.min(bytes.len())
		before = Str.from_utf8_lossy(bytes.take_first(start))
		after = Str.from_utf8_lossy(bytes.drop_first(to.min(bytes.len()).max(start)))
		lead = if (!before.is_empty() and !before.ends_with(" ") and !before.ends_with("\n")) " " else ""
		trail = if (!after.is_empty() and !after.starts_with(" ") and !after.starts_with("\n")) " " else ""
		"${before}${lead}${text.trim()}${trail}${after}"
	}
}

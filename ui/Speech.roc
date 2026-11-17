## What voice in the chat composer is doing, and the ports to the page's
## JavaScript that record and speak (ui/voice.mjs, which ui/ports.mjs loads
## on first use). The audio itself never reaches the app: the page posts it
## to the daemon's audio route (docs/protocol.md, Audio), asks voice.v1 for
## its transcript, and tells the app only what changed.
import cap.Voice
import pf.Engine
import pf.Port

Speech := [].{

	## Dictation types what is said into the composer; a conversation sends
	## each utterance and speaks the agent's replies.
	Mode : [Dictation, Conversation]

	## `engine` is the daemon's speech engine. The microphone records for the
	## pane `pane`, whose session a conversation talks with (`session`),
	## `serial` counting recordings. `held` follows a press of the mic
	## button, held once the page reports levels for a moment, which records
	## until released; `swallow_click` eats the click that ends such a
	## press. `stopping` asks the page to end the recording numbered so, and
	## `transcribing` counts the utterances it is transcribing; `sending`
	## sends the dictation's transcript once it comes. A
	## conversation speaks the agent's messages after the entry `spoken`,
	## and `hush` counts the taps that stopped them being spoken.
	## `voices` and `picked` are settings' speech choices, which the page
	## keeps.
	State : {
		engine : Voice.Engine,
		pane : Str,
		session : Str,
		mode : Mode,
		phase : [Idle, Listening, Transcribing, Failed(Str)],
		serial : U64,
		level : U8,
		held : [Up, Pressed(U8), Held],
		swallow_click : Bool,
		speaking : Bool,
		stopping : U64,
		transcribing : U64,
		sending : Bool,
		spoken : U64,
		hush : U64,
		voices : List({ name : Str, local : Bool }),
		picked : Picked,
	}

	## The voice and rate settings picked, unknown until settings ask the page.
	Picked : [Unknown, Picked({ voice : Str, rate : Str })]

	initial : State
	initial = {
		engine: Down("checking the speech engine"),
		pane: "",
		session: "",
		mode: Dictation,
		phase: Idle,
		serial: 0,
		level: 0,
		held: Up,
		swallow_click: Bool.False,
		speaking: Bool.False,
		stopping: 0,
		transcribing: 0,
		sending: Bool.False,
		spoken: 0,
		hush: 0,
		voices: [],
		picked: Unknown,
	}

	## What the page tells of a recording: the input's level, 0 to 100; an
	## utterance ended and is being transcribed; its transcript, and where
	## the composer's selection then was, as byte offsets into the draft, or
	## why there is none; or a reply being spoken started or stopped, which
	## pauses a conversation's listening until shortly after.
	Heard : [Level(U8), Transcribing, Transcript({ text : Str, from : U64, to : U64 }), NotTranscribed(Str), Speaking(Bool)]

	## Records from the microphone while subscribed: until stopped for
	## dictation, or utterance after utterance, each ended by silence, for a
	## conversation.
	capture : Port.Subscription({ pane : Str, mode : Mode, serial : U64 }, Heard)
	capture = Port.subscription({ name: "liton/voice/capture", delivery: Every(64) })

	## What the page is to do, as it changes: end the dictation numbered
	## `stop`, posting what is left; speak the agent's messages in a
	## conversation's session (`replies`) it hasn't, sentence by sentence,
	## naming code rather than reading it, and stop speaking when `hush`
	## changes; and keep the voice and rate picked.
	Order : { stop : U64, hush : U64, session : Str, replies : List({ sequence : U64, text : Str }), picked : Picked }

	order : Port.Command(Order)
	order = Port.command({ name: "liton/voice/order" })

	## The browser's voices, those on the device first, and the voice and rate
	## picked before.
	voices : Port.Call({}, { voices : List({ name : Str, local : Bool }), voice : Str, rate : Str })
	voices = Port.call({ name: "liton/voice/voices", timeout: Ms(5000) })

	registrations : List(Engine.PortRegistration)
	registrations = [Speech.capture.registration(), Speech.order.registration(), Speech.voices.registration()]

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

	## Whether `heard` is mostly `reply` read back, as a microphone near the
	## speakers hears it: over 70% of its words, at least three, are the
	## reply's.
	echoes : Str, Str -> Bool
	echoes = |heard, reply| {
		words = |text| Str.from_utf8_lossy(text.with_ascii_lowercased().to_utf8().map(|byte| if ((byte >= 48 and byte <= 57) or (byte >= 97 and byte <= 122) or byte >= 128) byte else 32)).split_on(" ").drop_if(Str.is_empty)
		said = words(heard)
		replied = words(reply)
		said.len() >= 3 and said.keep_if(|word| replied.contains(word)).len() * 10 > said.len() * 7
	}
}

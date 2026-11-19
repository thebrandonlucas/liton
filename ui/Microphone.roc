## Voice in a chat pane's composer (docs/research/voice.md): a mic button
## that dictates into the draft, tapped to start and stop or held to talk,
## and a conversation toggle that sends each utterance and speaks the
## agent's replies, not listening while it does (or it would hear the
## speakers), a tap on the mic stopping one. Each shows its state at once,
## before the page or the daemon answers.
import pf.Engine exposing [Elem, Signal, State]
import pf.Html
import cap.Capability
import Model
import Speech
import Dropdown

Microphone := [].{

	## How a pane's voice controls look: the mic button's class, which the
	## stylesheet draws, its name, tooltip and input level, the word beside
	## it, and the conversation toggle's state.
	Look : { hidden : Bool, disabled : Bool, class : Str, label : Str, title : Str, status : Str, level : U8, talking : Bool, talk_disabled : Bool }

	## How the mic of pane `pane_id` looks, from the voice's state.
	look : Model.State, Str -> Look
	look = |state, pane_id| {
		voice = state.voice
		mine = voice.pane == pane_id
		base = {
			hidden: !state.capabilities.contains(Capability.voice_v1),
			disabled: Bool.False,
			class: "mic",
			label: "Dictate",
			title: "Dictate: tap to start and to stop, or hold to talk",
			status: "",
			level: 0,
			talking: Bool.False,
			talk_disabled: Model.session_of(state, Model.pane(state, pane_id)).is_empty(),
		}
		unavailable = |reason| { ..base, disabled: Bool.True, class: "mic unavailable", title: "Voice is unavailable: ${reason}", talk_disabled: Bool.True }
		match (voice.engine, voice.phase) {
			(_, Listening) if mine and voice.mode == Conversation and voice.speaking => { ..base, class: "mic conversation speaking", label: "Stop speaking", title: "Stop speaking, and listen", status: "Speaking", talking: Bool.True }
			(_, Listening) if mine and voice.mode == Conversation => { ..base, class: "mic conversation", label: "End the conversation", title: "End the conversation", status: if (voice.transcribing > 0) "Transcribing…" else "Listening", level: voice.level, talking: Bool.True }
			(_, Listening) if mine => { ..base, class: "mic listening", label: "Stop dictating", title: "Stop dictating", status: "Listening", level: voice.level }
			(_, Transcribing) if mine => { ..base, disabled: Bool.True, class: "mic transcribing", label: "Transcribing", title: "Transcribing what you said", status: "Transcribing…" }
			(_, Failed(reason)) if mine and reason == "Denied" => { ..base, class: "mic denied", title: "The browser blocked the microphone: allow it in this site's settings, then tap to try again", status: "Microphone blocked" }
			(Ready, Failed(reason)) if mine => { ..base, class: "mic failed", title: reason, status: "Not transcribed: ${reason}" }
			_ if Speech.active(voice) => { ..base, disabled: Bool.True, title: "The microphone is in use in another chat", talk_disabled: Bool.True }
			(Ready, _) => base
			(Loading, _) => unavailable("the speech engine is loading its model")
			(Down(reason), _) => unavailable(reason)
		}
	}

	## Whether a pane may record: the engine is up and the microphone isn't
	## in use for another pane.
	usable : Model.State, Str -> Bool
	usable = |state, pane_id| state.capabilities.contains(Capability.voice_v1) and state.voice.engine == Ready and (!Speech.active(state.voice) or state.voice.pane == pane_id)

	## Records for a pane, shown as listening at once; a conversation needs a
	## session to talk with, and speaks only what it says from now on.
	start : Model.State, Str, Speech.Mode -> Model.State
	start = |state, pane_id, mode| {
		voice = state.voice
		session_id = Model.session_of(state, Model.pane(state, pane_id))
		if (!Microphone.usable(state, pane_id) or (mode == Conversation and session_id.is_empty()))
			state
		else
			{ ..state, voice: { ..voice, pane: pane_id, session: session_id, mode, phase: Listening, serial: voice.serial + 1, level: 0, held: Up, swallow_click: Bool.False, speaking: Bool.False, transcribing: 0, sending: Bool.False, spoken: Model.last_sequence(state, session_id) } }
	}

	## Ends a dictation, shown as transcribing at once, or a conversation.
	stop : Model.State -> Model.State
	stop = |state| {
		voice = { ..state.voice, held: Up, level: 0 }
		match (voice.mode, voice.phase) {
			(Conversation, _) => { ..state, voice: { ..voice, phase: Idle, speaking: Bool.False } }
			(Dictation, Listening) => { ..state, voice: { ..voice, phase: Transcribing, stopping: voice.serial } }
			_ => state
		}
	}

	## A click of the mic: starts dictating, or stops what it does, unless it
	## ends a press that started it. While a reply is spoken it stops only
	## the speaking, to listen again; the agent works on, its Stop apart.
	tap : Model.State, Str -> Model.State
	tap = |state, pane_id| {
		voice = state.voice
		if (voice.swallow_click)
			{ ..state, voice: { ..voice, swallow_click: Bool.False } }
		else if (voice.pane == pane_id and voice.mode == Conversation and voice.phase == Listening and voice.speaking)
			{ ..state, voice: { ..voice, speaking: Bool.False, hush: voice.hush + 1 } }
		else if (voice.pane == pane_id and voice.phase == Listening)
			Microphone.stop(state)
		else
			Microphone.start(state, pane_id, Dictation)
	}

	## Send in a composer: while it dictates, stops the dictation, shown as
	## transcribing at once, to send what was typed and the transcript
	## after it once it comes; else sends what was typed.
	send : Model.State, Str -> Model.State
	send = |state, pane_id| {
		voice = state.voice
		if (voice.pane == pane_id and voice.mode == Dictation and Speech.active(voice)) Microphone.stop({ ..state, voice: { ..voice, sending: Bool.True } }) else Model.submit(state, pane_id)
	}

	## A press of the mic starts dictating at once; held while the page
	## reports a few levels (`heard`), its release stops it. A press while it
	## records leaves the click to stop it.
	press : Model.State, Str -> Model.State
	press = |state, pane_id| {
		started = Microphone.start(state, pane_id, Dictation)
		if (Speech.active(state.voice))
			{ ..state, voice: { ..state.voice, swallow_click: Bool.False } }
		else if (Speech.active(started.voice))
			{ ..started, voice: { ..started.voice, held: Pressed(0), swallow_click: Bool.True } }
		else
			state
	}

	## A release of the mic: it stops a dictation held long enough, and
	## leaves one only pressed recording until the mic is clicked.
	release : Model.State -> Model.State
	release = |state|
		match state.voice.held {
			Held => Microphone.stop(state)
			Pressed(_) => { ..state, voice: { ..state.voice, held: Up } }
			Up => state
		}

	## A press the browser took over, to scroll say, ends with no click.
	cancel_press : Model.State -> Model.State
	cancel_press = |state| {
		released = Microphone.release(state)
		{ ..released, voice: { ..released.voice, swallow_click: Bool.False } }
	}

	## Turns a conversation on or off.
	converse : Model.State, Str -> Model.State
	converse = |state, pane_id| if (state.voice.pane == pane_id and state.voice.mode == Conversation and state.voice.phase == Listening) Microphone.stop(state) else Microphone.start(state, pane_id, Conversation)

	## What the page records, while the microphone is in use or a dictation's
	## transcript is on its way.
	recording : Model.State -> [Recording({ pane : Str, mode : Speech.Mode, serial : U64 }), NotRecording]
	recording = |state| {
		voice = state.voice
		if (voice.phase == Listening or (voice.phase == Transcribing and voice.mode == Dictation)) Recording({ pane: voice.pane, mode: voice.mode, serial: voice.serial }) else NotRecording
	}

	## Takes what the page heard. A transcript dictated goes into the draft
	## where the selection was, for editing, or, if Send stopped it, after
	## what was typed, sent with it; one said in a conversation is sent,
	## unless it is mostly the last reply, heard from the speakers. A
	## microphone the browser refused, or that stopped, fails the recording.
	heard : Model.State, Try(Speech.Heard, _) -> Model.State
	heard = |state, message| {
		voice = state.voice
		changed_to = |changed| { ..state, voice: changed }
		done = { ..voice, transcribing: if (voice.transcribing > 0) voice.transcribing - 1 else 0, phase: if (voice.mode == Dictation) Idle else voice.phase, sending: Bool.False }
		match message {
			Ok(Level(level)) =>
				match voice.held {
					Pressed(count) if count >= 3 => changed_to({ ..voice, level, held: Held })
					Pressed(count) => changed_to({ ..voice, level, held: Pressed(count + 1) })
					_ => changed_to({ ..voice, level })
				}
			Ok(Transcribing) => changed_to({ ..voice, transcribing: voice.transcribing + 1, phase: if (voice.mode == Dictation) Transcribing else voice.phase })
			Ok(Transcript({ text, .. })) if text.trim().is_empty() => changed_to(if (voice.sending) { ..done, phase: Failed("no speech was heard") } else done)
			Ok(Transcript({ text, .. })) if voice.sending => {
				draft = Model.draft(state, voice.pane)
				end = draft.to_utf8().len()
				Model.submit(Model.set_draft(changed_to(done), voice.pane, Speech.insert(draft, end, end, text)), voice.pane)
			}
			Ok(Transcript({ text, from, to })) if voice.mode == Dictation => {
				typed = Model.set_draft(state, voice.pane, Speech.insert(Model.draft(state, voice.pane), from, to, text))
				{ ..typed, drafts_rewritten: { pane: voice.pane, count: typed.drafts_rewritten.count + 1 }, voice: done }
			}
			Ok(Transcript({ text, .. })) if Speech.echoes(text, Microphone.replies(state).last().map_ok(|reply| reply.text) ?? "") => { ..changed_to(done), notice: "Not sent: it sounded like the reply read back" }
			Ok(Transcript({ text, .. })) => Model.send(changed_to(done), SendMessage({ session_id: voice.session, text: text.trim(), while_running: Err(Missing) }))
			Ok(NotTranscribed(reason)) if voice.mode == Dictation => changed_to({ ..done, phase: Failed(reason) })
			Ok(NotTranscribed(reason)) => { ..changed_to(done), notice: "Not transcribed: ${reason}" }
			Ok(Speaking(speaking)) => changed_to({ ..voice, speaking })
			Err(Threw(reason)) => changed_to({ ..voice, phase: Failed(reason), held: Up, swallow_click: Bool.False, speaking: Bool.False })
			Err(Closed) if voice.phase == Listening => changed_to({ ..voice, phase: Failed("the microphone stopped"), held: Up, speaking: Bool.False })
			Err(_) => state
		}
	}

	## What the page is to do: end a dictation, speak a conversation's
	## replies or stop when tapped to, and keep the voice and rate picked.
	order : Model.State -> Speech.Order
	order = |state| {
		voice = state.voice
		spoken = if (voice.mode != Conversation or voice.phase != Listening) [] else Microphone.replies(state)
		{ stop: voice.stopping, hush: voice.hush, session: voice.session, replies: spoken, picked: voice.picked }
	}

	## The agent's messages in a conversation's session since it started.
	replies : Model.State -> List({ sequence : U64, text : Str })
	replies = |state|
		Model.entries(state, state.voice.session).keep_oks(
			|entry|
				match entry.event {
					AgentMessage({ text }) if entry.sequence > state.voice.spoken => Ok({ sequence: entry.sequence, text })
					_ => Err(NotReply)
				},
		)

	## The voice picked and the voices settings offer: the first on the
	## device, "default", then the browser's, an online one said so.
	voice_picked : Model.State -> { voice : Str, rate : Str }
	voice_picked = |state|
		match state.voice.picked {
			Picked(picked) => picked
			Unknown => { voice: "default", rate: "1" }
		}

	## The voices settings offer: the device's default, then the browser's,
	## those online named so.
	voice_choices : Model.State -> List({ value : Str, label : Str })
	voice_choices = |state| state.voice.voices.map(|offered| { value: offered.name, label: if (offered.local) offered.name else "${offered.name} (online)" }).prepend({ value: "default", label: "Default on-device voice" })

	## The recording, what the page is to do, and the voices settings offer.
	effects : State(ctx, Model.State) -> List(Elem(ctx))
	effects = |model| [
		Engine.watch_latest(
			model.signal().map(Microphone.recording),
			|asked_for|
				match asked_for {
					Recording(asked) => [Speech.capture.ask(asked)]
					NotRecording => []
				},
			model.on_result(|state, _, res| Microphone.heard(state, res)),
		),
		Engine.watch_changes(model.signal().map(Microphone.order), |asked| [Engine.command(Speech.order.send(asked))], Engine.ignore({})),
		Engine.watch_changes(
			model.signal().map(|state| state.show_settings and state.capabilities.contains(Capability.voice_v1)),
			|shown| if (shown) [Speech.voices.ask({})] else [],
			model.on_result(
				|state, _, res|
					match res {
						Ok({ voices, voice, rate }) => { ..state, voice: { ..state.voice, voices, picked: Picked({ voice, rate: if (rate.is_empty()) "1" else rate }) } }
						Err(_) => state
					},
			),
		),
	]

	## The mic button and the conversation toggle in a chat pane's composer,
	## with a word saying what they are doing. A press holds the button
	## (`press`), and the click ending it is a tap (`tap`).
	controls : State(ctx, Model.State), Signal(ctx, Str) -> Elem(ctx)
	controls = |model, id| {
		looks = id.map2(model.signal(), |pane_id, state| Microphone.look(state, pane_id))
		Html.div_attrs(
			[Engine.class("voice"), Engine.test_id("voice"), Html.boolean("hidden", looks.map(|shown| shown.hidden))],
			[
				Html.span_s(looks.map(|shown| shown.status), [Engine.class("voice-status"), Engine.test_id("voice-status"), Engine.attr("aria-live", "polite")]),
				Engine.element(
					"button",
					[
						Engine.attr("type", "button"),
						Engine.class_s(looks.map(|shown| shown.class)),
						Engine.attr_s("aria-label", looks.map(|shown| shown.label)),
						Engine.attr_s("title", looks.map(|shown| shown.title)),
						Html.flag_maybe("aria-disabled", looks.map(|shown| shown.disabled)),
						Engine.attr_s("style", looks.map(|shown| "--level: ${shown.level.to_str()}")),
						Engine.attr_s("data-voice-pane", id),
						Engine.on_click(model.update_by(id, Microphone.tap)),
						Engine.on("pointerdown", model.update_by(id, Microphone.press)),
						Engine.on("pointerup", model.update(Microphone.release)),
						Engine.on("pointerout", model.update(Microphone.release)),
						Engine.on("pointercancel", model.update(Microphone.cancel_press)),
						Engine.on_with("contextmenu", { prevent: Bool.True }, model.update(|state| state)),
					],
					[],
				),
				Engine.element(
					"button",
					[
						Engine.attr("type", "button"),
						Engine.class("talk"),
						Html.aria_label("Conversation"),
						Engine.attr("title", "Conversation: talk with the agent, which speaks its replies"),
						Html.flag("aria-pressed", looks.map(|shown| shown.talking)),
						Html.flag_maybe("aria-disabled", looks.map(|shown| shown.talk_disabled)),
						Engine.on_click(model.update_by(id, Microphone.converse)),
					],
					[],
				),
			],
		)
	}

	## Settings' speech choices for conversations: the voice, drop-down
	## `choices`, and the rate.
	settings : State(ctx, Model.State), (Signal(ctx, List({ value : Str, label : Str })) -> List(Elem(ctx))) -> Elem(ctx)
	settings = |model, choices| {
		picked = model.signal().map(Microphone.voice_picked)
		set = |change| model.set_value(|state, text| { ..state, voice: { ..state.voice, picked: Picked(change(Microphone.voice_picked(state), text)) } })
		Html.div_attrs(
			[Engine.class("voice-settings"), Html.boolean("hidden", model.signal().map(|state| !state.capabilities.contains(Capability.voice_v1)))],
			[
				Html.h3("Voice", ""),
				Engine.element("label", [Engine.class("setting")], [Engine.text("Speaking voice"), Dropdown.select(Engine.const("Speaking voice"), picked.map(|shown| shown.voice), [], choices(model.signal().map(Microphone.voice_choices)), set(|shown, voice| { ..shown, voice }))]),
				Engine.element("label", [Engine.class("setting")], [Engine.text("Speaking rate"), Dropdown.select(Engine.const("Speaking rate"), picked.map(|shown| shown.rate), [], ["0.75", "1", "1.25", "1.5", "2"].map(|rate| Dropdown.option(rate, "${rate}×")), set(|shown, rate| { ..shown, rate }))]),
				Html.p("A conversation speaks the agent's replies in this voice. An on-device voice keeps them on this device; an online one sends their text to its provider.", "help"),
			],
		)
	}
}

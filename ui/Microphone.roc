## Voice in a chat pane's composer (docs/research/voice.md): a mic button
## that dictates into the draft, tapped to start and stop or held to talk.
## It shows its state at once, before the page or the daemon answers.
import pf.Engine exposing [Elem, Signal, State]
import pf.Html
import cap.Capability
import Model
import Speech

Microphone := [].{

	## How a pane's mic button looks: its class, which the stylesheet draws,
	## its name, tooltip and input level, and the word beside it.
	Look : { hidden : Bool, disabled : Bool, class : Str, label : Str, title : Str, status : Str, level : U8 }

	look : Model.State, Str -> Look
	look = |state, pane_id| {
		voice = state.voice
		mine = voice.pane == pane_id
		base = { hidden: !state.capabilities.contains(Capability.voice_v1), disabled: Bool.False, class: "mic", label: "Dictate", title: "Dictate: tap to start and to stop, or hold to talk", status: "", level: 0 }
		unavailable = |reason| { ..base, disabled: Bool.True, class: "mic unavailable", title: "Voice is unavailable: ${reason}" }
		match (voice.engine, voice.phase) {
			(_, Listening) if mine => { ..base, class: "mic listening", label: "Stop dictating", title: "Stop dictating", status: "Listening", level: voice.level }
			(_, Transcribing) if mine => { ..base, disabled: Bool.True, class: "mic transcribing", label: "Transcribing", title: "Transcribing what you said", status: "Transcribing…" }
			(_, Failed(reason)) if mine and reason == "Denied" => { ..base, class: "mic denied", title: "The browser blocked the microphone: allow it in this site's settings, then tap to try again", status: "Microphone blocked" }
			(Ready, Failed(reason)) if mine => { ..base, class: "mic failed", title: reason, status: "Not transcribed: ${reason}" }
			_ if Speech.active(voice) => { ..base, disabled: Bool.True, title: "The microphone is in use in another chat" }
			(Ready, _) => base
			(Loading, _) => unavailable("the speech engine is loading its model")
			(Down(reason), _) => unavailable(reason)
		}
	}

	## Whether a pane may record: the engine is up and the microphone isn't
	## in use for another pane.
	usable : Model.State, Str -> Bool
	usable = |state, pane_id| state.capabilities.contains(Capability.voice_v1) and state.voice.engine == Ready and (!Speech.active(state.voice) or state.voice.pane == pane_id)

	## Records for a pane, shown as listening at once.
	start : Model.State, Str -> Model.State
	start = |state, pane_id| {
		voice = state.voice
		if (!Microphone.usable(state, pane_id)) state else { ..state, voice: { ..voice, pane: pane_id, phase: Listening, serial: voice.serial + 1, level: 0, held: Up, swallow_click: Bool.False } }
	}

	## Ends a dictation, shown as transcribing at once.
	stop : Model.State -> Model.State
	stop = |state| {
		voice = { ..state.voice, held: Up, level: 0 }
		if (voice.phase == Listening) { ..state, voice: { ..voice, phase: Transcribing, stopping: voice.serial } } else state
	}

	## A click of the mic: starts dictating, or stops, unless it ends a press
	## that started it.
	tap : Model.State, Str -> Model.State
	tap = |state, pane_id| {
		voice = state.voice
		if (voice.swallow_click)
			{ ..state, voice: { ..voice, swallow_click: Bool.False } }
		else if (voice.pane == pane_id and voice.phase == Listening)
			Microphone.stop(state)
		else
			Microphone.start(state, pane_id)
	}

	## A press of the mic starts dictating at once; held while the page
	## reports a few levels (`heard`), its release stops it. A press while it
	## records leaves the click to stop it.
	press : Model.State, Str -> Model.State
	press = |state, pane_id| {
		started = Microphone.start(state, pane_id)
		if (Speech.active(state.voice))
			{ ..state, voice: { ..state.voice, swallow_click: Bool.False } }
		else if (Speech.active(started.voice))
			{ ..started, voice: { ..started.voice, held: Pressed(0), swallow_click: Bool.True } }
		else
			state
	}

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

	## What the page records, while the microphone is in use or the
	## transcript is on its way.
	recording : Model.State -> [Recording({ pane : Str, serial : U64 }), NotRecording]
	recording = |state| {
		voice = state.voice
		if (Speech.active(voice)) Recording({ pane: voice.pane, serial: voice.serial }) else NotRecording
	}

	## Takes what the page heard. The transcript goes into the draft where
	## the selection was, for editing. A microphone the browser refused, or
	## that stopped, fails the recording.
	heard : Model.State, Try(Speech.Heard, _) -> Model.State
	heard = |state, message| {
		voice = state.voice
		changed_to = |changed| { ..state, voice: changed }
		match message {
			Ok(Level(level)) =>
				match voice.held {
					Pressed(count) if count >= 3 => changed_to({ ..voice, level, held: Held })
					Pressed(count) => changed_to({ ..voice, level, held: Pressed(count + 1) })
					_ => changed_to({ ..voice, level })
				}
			Ok(Transcribing) => changed_to({ ..voice, phase: Transcribing })
			Ok(Transcript({ text, .. })) if text.trim().is_empty() => changed_to({ ..voice, phase: Idle })
			Ok(Transcript({ text, from, to })) => {
				count = (state.cleared.find_first(|composer| composer.pane == voice.pane).map_ok(|composer| composer.count) ?? 0) + 1
				typed = Model.set_draft(state, voice.pane, Speech.insert(Model.draft(state, voice.pane), from, to, text))
				{ ..typed, cleared: typed.cleared.drop_if(|composer| composer.pane == voice.pane).append({ pane: voice.pane, count }), voice: { ..voice, phase: Idle } }
			}
			Ok(NotTranscribed(reason)) => changed_to({ ..voice, phase: Failed(reason) })
			Err(Threw(reason)) => changed_to({ ..voice, phase: Failed(reason), held: Up, swallow_click: Bool.False })
			Err(Closed) if voice.phase == Listening => changed_to({ ..voice, phase: Failed("the microphone stopped"), held: Up })
			Err(_) => state
		}
	}

	## The recording, and what the page is to do.
	effects : State(ctx, Model.State) -> List(Elem(ctx))
	effects = |model| [
		Engine.watch_latest(
			model.signal().map(Microphone.recording),
			|asked_for|
				match asked_for {
					Recording(asked) => [Speech.capture.subscribe(asked)]
					NotRecording => []
				},
			model.on_result(|state, _, res| Microphone.heard(state, Speech.capture.message(res))),
		),
		Engine.watch_changes(model.signal().map(|state| { stop: state.voice.stopping }), |asked| [Speech.order.send(asked)], Engine.ignore({})),
	]

	## The mic button in a chat pane's composer, with a word saying what it
	## is doing. A press holds the button (`press`), and the click ending it
	## is a tap (`tap`).
	controls : State(ctx, Model.State), Signal(ctx, Str) -> Elem(ctx)
	controls = |model, id| {
		looks = id.map2(model.signal(), |pane_id, state| Microphone.look(state, pane_id))
		Html.div_attrs(
			[Engine.class("voice"), Engine.test_id("voice"), Html.flag_maybe("hidden", looks.map(|shown| shown.hidden))],
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
						Engine.on("contextmenu:prevent", model.update(|state| state)),
					],
					[],
				),
			],
		)
	}
}

## A conversation, as chat and rooms show one: a timeline of entries, the
## newest at the bottom, over a composer. Each caller draws its own kinds of
## entry; this draws what they share.
import pf.Engine exposing [Elem, Handler, Signal, State]
import pf.Html
import Model

Conversation := [].{

	## A timeline of the entries a caller draws, as a list of class `class`
	## and part `part`, with "Loading…" under it while `loading`. Its key
	## names the pane's jumps and anchor. With `jump`, Jump to latest scrolls
	## back to the newest entry; while `earlier`, Show earlier shows more.
	timeline : State(ctx, Model.State), Signal(ctx, Str), { class : Str, part : Str, jump : Bool, earlier : Signal(ctx, Bool), loading : Signal(ctx, Bool) }, List(Elem(ctx)) -> List(Elem(ctx))
	timeline = |model, key, { class, part, jump, earlier, loading }, entries| {
		# Shown by CSS once scrolled up from the newest entry, where browsers
		# can (animation-timeline). Jumping builds this pane's anchor anew,
		# so it is the one `Liton.effects` focuses.
		latest =
			if (jump)
				[
					Html.div("jump", [Html.button("Jump to latest", [Engine.class("jump-to-latest")], model.update_by(key, Model.jump_to_latest))]),
					Engine.remount_on(key.map2(model.signal(), |jump_key, state| Model.jumps_of(state, jump_key)), || Engine.element("span", [Engine.ref_s(key.map(|jump_key| "latest-${jump_key}")), Engine.attr("tabindex", "-1"), Engine.class("latest-anchor")], [])),
				]
			else
				[]
		[
			# Reversed in CSS, so the scroll position stays on the newest entry.
			Html.div(
				"timeline-scroll",
				latest.concat([
					Html.ul([Engine.class(class), Engine.attr("data-part", part)], entries),
					# Last, so shown first: the timeline is reversed. ui/ports.mjs
					# presses it as it scrolls into view.
					Engine.when(earlier, || Html.div("earlier", [Html.button("Show earlier", [Engine.class("show-earlier")], model.update_by(key, Model.show_earlier))]), || Engine.text("")),
				]),
			),
			Engine.when(loading, || Html.p("Loading…", "missing"), || Engine.text("")),
		]
	}

	## A composer of the draft kept under `key`, a form named `form`: the
	## names `completions` offers for what is being typed, such as a room's
	## members for a mention, each of which completes it; the box; and under
	## it a row of what the caller puts there, such as chips, dictation and
	## Send or Stop. Submitting it sends the draft with `send`.
	composer : State(ctx, Model.State), Signal(ctx, Str), { form : Str, name : Str, placeholder : Signal(ctx, Str), send : Model.State, Str -> Model.State, completions : Model.State, Str -> List(Str) }, List(Elem(ctx)) -> Elem(ctx)
	composer = |model, key, { form, name, placeholder, send, completions }, row|
		Html.form(
			form,
			[Engine.class("composer"), Engine.attr("data-part", "composer"), Engine.on("submit", model.update_by(key, send))],
			[
				Html.div(
					"mention-choices",
					[
						Engine.each(
							key.map2(model.signal(), |draft_key, state| completions(state, draft_key)),
							|choice| choice,
							|choice| Html.button_s(choice.key().map(|named| "@${named}"), [], model.lift_row().update_by(choice.key().map2(key.lift_row(), |named, draft_key| { key: draft_key, name: named }), Model.mention)),
						),
					],
				),
				Conversation.input(model, key, { name: name, placeholder: placeholder }, send),
				Html.div("composer-row", row),
			],
		)

	## The composer's round Send button, named `name` for screen readers.
	send_button : Str -> Elem(ctx)
	send_button = |name| Html.submit_button("", [Engine.class("send"), Html.aria_label(name)])

	## A box that grows with the draft kept under `key` to a few lines, with
	## the reference `composer-<key>`, which no other box shares. Enter sends it and Shift+Enter starts a new line,
	## except on a touch screen, where Enter starts one and Send sends. Enter
	## that ends an IME composition is never heard.
	input : State(ctx, Model.State), Signal(ctx, Str), { name : Str, placeholder : Signal(ctx, Str) }, (Model.State, Str -> Model.State) -> Elem(ctx)
	input = |model, key, { name, placeholder }, send| {
		enter = Engine.Chord.plain("Enter")
		sends = model.signal().map(|state| Engine.Keymap.prevent(if (state.coarse_pointer) [] else [enter].concat(enter.primary())))
		Html.textarea(Engine.const(name), key.map2(model.signal(), |draft_key, state| Model.draft(state, draft_key)), [Engine.attr("rows", "1"), Engine.attr_s("placeholder", placeholder), Engine.ref_s(key.map(|draft_key| "composer-${draft_key}")), Engine.on_key({ keymap: sends }, model.update_by(key, send))], model.set_value_by(key, Model.set_draft))
	}

	## How an entry sent but not yet in the timeline stands, `status` being
	## "Sending…" or why it wasn't sent, or "" for nothing to say; and while
	## it `failed`, a button for each of `actions`, such as Retry.
	sent_state : { status : Signal(ctx, Str), failed : Signal(ctx, Bool), test_id : Str }, List({ label : Str, handler : Handler(ctx) }) -> Elem(ctx)
	sent_state = |{ status, failed, test_id }, actions| {
		buttons = actions.map(|action| Html.button(action.label, [], action.handler))
		Engine.when(
			status.map(|said| !said.is_empty()),
			|| Html.div("sent-state", [Html.span_s(status, [Engine.class("sent-status"), Engine.test_id(test_id)]), Engine.when(failed, || Html.div("sent-actions", buttons), || Engine.text(""))]),
			|| Engine.text(""),
		)
	}
}

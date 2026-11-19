## A conversation, as chat and rooms show one: a timeline of entries, the
## newest at the bottom, over a composer. Each caller draws its own kinds of
## entry; this draws what they share.
import pf.Engine exposing [Elem, HandlerOf, Signal, State]
import pf.Html
import Model
import Spinner

Conversation := [].{

	## A timeline of the entries a caller draws, as a list of class `class`
	## and part `part`, with a spinner in its place while `loading`. Its key
	## names the pane's jumps and anchor. A `jump` button, such as Jump to
	## latest, scrolls back to the newest entry ("" for none); while
	## `earlier`, Show earlier shows more.
	timeline : State(ctx, Model.State), Signal(ctx, Str), { class : Str, part : Str, jump : Str, earlier : Signal(ctx, Bool), loading : Signal(ctx, Bool) }, List(Elem(ctx)) -> List(Elem(ctx))
	timeline = |model, key, { class, part, jump, earlier, loading }, entries| {
		# Shown by CSS once scrolled up from the newest entry, where browsers
		# can (animation-timeline). Jumping builds this pane's anchor anew,
		# so it is the one `Liton.effects` focuses.
		latest =
			if (!jump.is_empty())
				[
					Html.div("jump", [Html.button(jump, [Engine.class("jump-to-latest")], model.update_by(key, Model.jump_to_latest))]),
					Engine.remount_on(key.map2(model.signal(), |jump_key, state| Model.jumps_of(state, jump_key)), || Engine.element("span", [Engine.ref_s(key.map(|jump_key| "latest-${jump_key}")), Engine.attr("tabindex", "-1"), Engine.class("latest-anchor"), Engine.test_id("latest")], [])),
				]
			else
				[]
		[
			# Reversed in CSS, so the scroll position stays on the newest entry.
			Html.div(
				"timeline-scroll",
				latest.concat([
					Html.ul([Engine.class(class), Engine.attr("data-part", part)], entries),
					# Last, so shown first: the timeline is reversed. It shows
					# more once scrolled to within a screen of it, so earlier
					# entries come as they are read.
					Engine.when(earlier, || Html.div("earlier", [Html.button("Show earlier", [Engine.class("show-earlier"), Engine.on_seen({ ahead: Bool.True }, model.set_value_by(key, |state, pane_id, seen| if (seen.intersecting) Model.show_earlier(state, pane_id) else state))], model.update_by(key, Model.show_earlier))]), || Engine.text("")),
				]),
			),
			Engine.when(loading, || Spinner.spinner("Loading", Pane), || Engine.text("")),
		]
	}

	## A composer of the draft kept under `key`, a form named `form`: the
	## names `completions` offers for what is being typed, such as a room's
	## members for a mention, each of which completes it; the box; and under
	## it a row of what the caller puts there, such as chips, dictation and
	## Send or Stop. Submitting it sends the draft with `send`; Shift+Tab in
	## the box runs `shift_tab`, if any, such as a chat's switch of mode.
	composer : State(ctx, Model.State), Signal(ctx, Str), { form : Str, name : Str, placeholder : Signal(ctx, Str), send : Model.State, Str -> Model.State, completions : Model.State, Str -> List(Str), shift_tab : [Ignored, Runs((Model.State, Str -> Model.State))] }, List(Elem(ctx)) -> Elem(ctx)
	composer = |model, key, { form, name, placeholder, send, completions, shift_tab }, row|
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
				Conversation.input(model, key, { name: name, placeholder: placeholder, shift_tab: shift_tab }, send),
				Html.div("composer-row", row),
			],
		)

	## The composer's round Send button, named `name` for screen readers.
	send_button : Str -> Elem(ctx)
	send_button = |name| Html.submit_button("", [Engine.class("send"), Html.aria_label(name)])

	## A box that grows with the draft kept under `key` to a few lines, with
	## the reference `composer-<key>`, which no other box shares. Enter sends it and Shift+Enter starts a new line,
	## except on a touch screen, where Enter starts one and Send sends; Shift+Tab
	## runs `shift_tab`, if any. Enter
	## that ends an IME composition is never heard.
	input : State(ctx, Model.State), Signal(ctx, Str), { name : Str, placeholder : Signal(ctx, Str), shift_tab : [Ignored, Runs((Model.State, Str -> Model.State))] }, (Model.State, Str -> Model.State) -> Elem(ctx)
	input = |model, key, { name, placeholder, shift_tab }, send| {
		enter = Engine.Chord.plain("Enter")
		shifted = match shift_tab {
			Runs(_) => [Engine.Chord.plain("Tab").with_shift()]
			Ignored => []
		}
		heard = model.signal().map(|state| Engine.Keymap.prevent((if (state.coarse_pointer) [] else [enter].concat(enter.primary())).concat(shifted)))
		pressed = |state, draft_key, typed|
			match shift_tab {
				Runs(run) if typed.key == "Tab" => run(state, draft_key)
				_ => send(state, draft_key)
			}
		Html.textarea(Engine.const(name), key.map2(model.signal(), |draft_key, state| Model.draft(state, draft_key)), [Engine.attr("rows", "1"), Engine.attr_s("placeholder", placeholder), Engine.ref_s(key.map(|draft_key| "composer-${draft_key}")), Engine.on_key({ keymap: heard }, model.set_value_by(key, pressed))], model.set_value_by(key, Model.set_draft))
	}

	## How an entry sent but not yet in the timeline stands, `status` being
	## "Sending…" or why it wasn't sent, or "" for nothing to say; and while
	## it `failed`, a button for each of `actions`, such as Retry.
	sent_state : { status : Signal(ctx, Str), failed : Signal(ctx, Bool), test_id : Str }, List({ label : Str, handler : HandlerOf(ctx, Engine.Click) }) -> Elem(ctx)
	sent_state = |{ status, failed, test_id }, actions| {
		buttons = actions.map(|action| Html.button(action.label, [], action.handler))
		Engine.when(
			status.map(|said| !said.is_empty()),
			|| Html.div("sent-state", [Html.span_s(status, [Engine.class("sent-status"), Engine.test_id(test_id)]), Engine.when(failed, || Html.div("sent-actions", buttons), || Engine.text(""))]),
			|| Engine.text(""),
		)
	}
}

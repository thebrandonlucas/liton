## A conversation, as chat and rooms show one: a timeline of entries, the
## newest at the bottom, over a composer. Each caller draws its own kinds of
## entry; this draws what they share.
import pf.Engine exposing [Elem, Signal, State]
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
}

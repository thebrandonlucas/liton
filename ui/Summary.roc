## A session's Goal / Done / Now summary, a part any pane that shows a
## session can hold: the chat's header area holds it, and the Inbox's
## preview can.
import pf.Engine exposing [Elem, Signal, State]
import pf.Html
import Model

Summary := [].{

	## A session's summary, as Paseo's inbox shows one, for the pane
	## `pane_id` that shows the session: its goal, what it has done and what
	## happens now, each beside its icon, under a heading that folds them
	## (`Model.toggle_summary`). Nothing while the session has none, or the
	## pane's Summary option hides it (`Model.summary_of`).
	view : State(ctx, Model.State), Signal(ctx, Str) -> Elem(ctx)
	view = |model, pane_id| {
		shown = pane_id.map2(model.signal(), |id, state| Model.summary_of(state, id))
		open = shown.map(|known| known.map_ok(|{ open: opened, .. }| opened) ?? Bool.False)
		line = |name, class, pick|
			Html.div_attrs(
				[Engine.class("summary-line ${class}")],
				[Html.span_s(Engine.const(name), [Engine.class("summary-label")]), Html.span_s(shown.map(|known| known.map_ok(|{ summary: written, .. }| pick(written)) ?? ""), [Engine.class("summary-text"), Engine.test_id("summary-${class}")])],
			)
		Engine.when(
			shown.map(|known| known.is_ok()),
			||
				Html.div_attrs(
					[Engine.class("session-summary"), Engine.attr("data-part", "summary"), Engine.test_id("summary")],
					[
						Engine.element(
							"button",
							[Engine.attr("type", "button"), Engine.class_s(open.map(|opened| if (opened) "summary-toggle open" else "summary-toggle")), Engine.attr_s("aria-expanded", open.map(|opened| if (opened) "true" else "false")), Engine.on_click(model.update_by(pane_id, Model.toggle_summary))],
							[Engine.text("Summary")],
						),
						Engine.when(
							open,
							|| Html.div("summary-lines", [line("Goal", "goal", |written| written.goal), line("Done", "done", |written| written.done), line("Now", "now", |written| written.now)]),
							|| Engine.text(""),
						),
					],
				),
			|| Engine.text(""),
		)
	}
}

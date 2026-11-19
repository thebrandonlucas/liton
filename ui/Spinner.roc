## A spinner where something is loading, named for screen readers by what
## is loading. It turns by CSS, and stands still where reduced motion is
## asked for.
import pf.Engine exposing [Attr, Elem, Signal]
import pf.Html

Spinner := [].{

	## A spinner named `label`: small, beside what is loading, or `Pane`,
	## larger and centred in the space of what is loading as a whole.
	spinner : Str, [Inline, Pane] -> Elem(ctx)
	spinner = |label, size| {
		turning = Engine.element("span", [Engine.class(if (size == Pane) "spinner large" else "spinner"), Engine.attr("role", "status"), Html.aria_label(label)], [])
		if (size == Pane) Html.div("spinner-pane", [turning]) else turning
	}

	## What `status` says, in a paragraph with `attrs`, or while `Loading`, a
	## spinner of `size` named Loading: a small one in that paragraph, or a
	## pane's in its place.
	or_text : Signal(ctx, [Loading, Said(Str)]), [Inline, Pane], List(Attr(ctx)) -> Elem(ctx)
	or_text = |status, size, attrs|
		Engine.when(
			status.map(|shown| shown == Loading),
			|| if (size == Pane) Spinner.spinner("Loading", Pane) else Engine.element("p", attrs, [Spinner.spinner("Loading", Inline)]),
			||
				Html.p_s(
					status.map(
						|shown|
							match shown {
								Said(text) => text
								Loading => ""
							},
					),
					attrs,
				),
		)
}

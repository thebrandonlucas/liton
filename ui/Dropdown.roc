## A drop-down of plain options. roc-signals's `Html.select` draws its
## options with `Engine.each`, which costs the module far more than the few
## fixed options liton draws (`Liton.choices`).
import pf.Engine exposing [Attr, Elem, Handler, Signal]

Dropdown := [].{

	## A drop-down named `name` showing the option whose value `value`
	## holds; `handler` receives the value of the option chosen.
	select : Signal(ctx, Str), Signal(ctx, Str), List(Attr(ctx)), List(Elem(ctx)), Handler(ctx) -> Elem(ctx)
	select = |name, value, attrs, options, handler| Engine.element("select", [Engine.attr_s("aria-label", name), Engine.prop_s(Engine.Prop.value, value), Engine.on("change", handler)].concat(attrs), options)

	## An option of a select, its `value` shown as `label`.
	option : Str, Str -> Elem(ctx)
	option = |value, label| Engine.element("option", [Engine.prop(Engine.Prop.value, value)], [Engine.text(label)])

	## An option whose value and label both follow `value`.
	option_s : Signal(ctx, Str) -> Elem(ctx)
	option_s = |value| Engine.element("option", [Engine.prop_s(Engine.Prop.value, value)], [Engine.text_s(value)])
}

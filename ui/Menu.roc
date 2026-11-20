## Every menu: a pane's, a row's, the new tab one, a room's and the context
## meter's. `Model.State`'s `menu` names the one open, so opening one closes
## another. Its button opens it, or closes it when open; a click outside it
## (`Liton.page`'s backdrop), Escape (`Commands`' close), focus moving
## outside it (`Menu.focused`) and each of its items close it.
import pf.Engine exposing [Attr, Elem, HandlerOf, Signal, State]
import pf.Html
import Model

Menu := [].{

	## What a menu's button and items hold as their value, so focus moving
	## to them doesn't close it (`Menu.focused`).
	inside : Str
	inside = "liton-menu"

	## The menu `key` names: `host`'s class on its wrapper, its button with
	## `button`'s attributes, and while open `items` in the page's top layer
	## beside the button (style.css), over any pane that would clip it, with
	## `kind`'s class beside `menu` and `attrs`, which hold no class.
	menu : State(ctx, Model.State), Signal(ctx, Str), Str, List(Attr(ctx)), Str, List(Attr(ctx)), List(Elem(ctx)) -> Elem(ctx)
	menu = |model, key, host, button, kind, attrs, items| {
		open = key.map2(model.signal(), |menu_key, state| state.menu == menu_key)
		Html.div(
			"menu-host ${host}",
			[
				Engine.element("button", [Engine.attr("type", "button"), Engine.attr("value", Menu.inside), Engine.attr("aria-haspopup", "true"), Html.flag("aria-expanded", open), Engine.on_click(model.update_by(key, Model.toggle_menu))].concat(button), []),
				Engine.when(open, || Html.popover("Menu", { open, on_toggle: model.set_value(|state, _shown| state), dismiss: Manual }, [Engine.class(if (kind.is_empty()) "menu" else "menu ${kind}")].concat(attrs), items), || Engine.text("")),
			],
		)
	}

	## An item of a menu: a button named `label`, with the icon `icon` names
	## (style.css's `.item-<icon>`), doing `handler`, which closes the menu.
	item : Signal(ctx, Str), Signal(ctx, Str), HandlerOf(ctx, Engine.Click) -> Elem(ctx)
	item = |icon, label, handler| Html.button_s(label, [Engine.attr("type", "button"), Engine.class_s(icon.map(|name| "menu-item item-${name}")), Engine.attr("value", Menu.inside)], handler)

	## Focus moved to an element whose value is `value`: anything but a
	## menu's button or item closes the menu open.
	focused : Model.State, Str -> Model.State
	focused = |state, value| if (state.menu.is_empty() or value == Menu.inside) state else { ..state, menu: "" }
}

expect Menu.focused({ ..Model.initial(""), menu: "pane-1" }, Menu.inside).menu == "pane-1" and Menu.focused({ ..Model.initial(""), menu: "pane-1" }, "draft").menu == ""

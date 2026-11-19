## The background this browser shows over its theme's own, which it keeps
## apart from the snapshot, as it does Glass: an image's URL, the theme's own
## background for "", and how far the image shown is dimmed.
import pf.Engine exposing [Elem, State]
import pf.Html
import setup.Setup
import Model

Wallpaper := [].{

	## Where the browser keeps the image's URL, "" for the theme's background.
	url_key : Str
	url_key = "liton.wallpaper"

	## The dim in percent, or "" for the theme's.
	dim_key : Str
	dim_key = "liton.dim"

	## The choice this browser kept.
	restored : Model.State, Str, Str -> Model.State
	restored = |state, url, dim| { ..state, wallpaper: { url, dim: U8.from_str(dim).map_ok(|percent| Dim(percent)) ?? ThemeDim } }

	## `theme` with this browser's background: the theme's own image or the
	## image chosen, dimmed as chosen or as the theme's image is (45% for a
	## theme without one).
	over : Setup.Theme, Model.State -> Setup.Theme
	over = |theme, { wallpaper, .. }| {
		own : Try({ url : Str, dim : U8 }, [NoImage])
		own =
			match theme.background {
				Image(image) => Ok(image)
				_ => Err(NoImage)
			}
		url = if (wallpaper.url.is_empty()) own.map_ok(|image| image.url) else Ok(wallpaper.url)
		dim =
			match wallpaper.dim {
				Dim(percent) => percent
				ThemeDim => own.map_ok(|image| image.dim) ?? 45
			}
		match url {
			Ok(shown) => { ..theme, background: Image({ url: shown, dim }) }
			Err(_) => theme
		}
	}

	## The dim of the image shown, or none without one.
	dim_shown : Model.State -> Try(U8, [NoImage])
	dim_shown = |state|
		match Wallpaper.over(Model.theme_shown(state), state).background {
			Image(image) => Ok(image.dim)
			_ => Err(NoImage)
		}

	## The images the setup's themes show, by their themes' names, after the
	## theme's own background.
	choices : Model.State -> List({ name : Str, url : Str })
	choices = |state| {
		images = state.themes.keep_oks(
			|theme|
				match theme.background {
					Image(image) => Ok({ name: theme.name, url: image.url })
					_ => Err(NoImage)
				},
		)
		images.prepend({ name: "The theme's", url: "" })
	}

	## Settings' background choices, an image's URL and the dim slider, shown
	## while an image is.
	settings : State(ctx, Model.State) -> Elem(ctx)
	settings = |model| Html.div(
		"wallpaper",
		[
			Html.div(
				"choices",
				[
					Engine.each(
						model.signal().map(Wallpaper.choices),
						|choice| choice.url,
						|row|
							Engine.element(
								"button",
								[
									Engine.attr("type", "button"),
									Engine.attr_s("aria-label", row.field(|choice| "${choice.name} background")),
									Html.flag("aria-pressed", row.key().map2(model.signal().lift_row(), |url, state| state.wallpaper.url == url)),
									Engine.on_click(model.lift_row().update_by(row.key(), |state, url| { ..state, wallpaper: { ..state.wallpaper, url } })),
								],
								[Engine.text_s(row.field(|choice| choice.name))],
							),
					),
				],
			),
			Html.text_input(
				Engine.const("Background image URL"),
				"url",
				model.signal().map(|state| state.wallpaper.url),
				[Engine.attr("placeholder", "Or an image's URL")],
				model.set_value(|state, url| { ..state, wallpaper: { ..state.wallpaper, url: url.trim() } }),
			),
			Engine.element(
				"label",
				[Engine.class("toggle"), Html.boolean("hidden", model.signal().map(|state| Wallpaper.dim_shown(state).is_err()))],
				[
					Engine.text("Dim"),
					Html.text_input(
						Engine.const("Dim"),
						"range",
						model.signal().map(|state| (Wallpaper.dim_shown(state) ?? 0).to_str()),
						[Engine.attr("min", "0"), Engine.attr("max", "90"), Engine.attr("step", "5")],
						model.set_value(|state, text| { ..state, wallpaper: { ..state.wallpaper, dim: U8.from_str(text).map_ok(|percent| Dim(percent)) ?? state.wallpaper.dim } }),
					),
				],
			),
			Html.p("Shows this browser an image behind the tiles in place of the theme's background, dimmed to keep text readable.", "help"),
		],
	)

	## Keeps the choice in this browser.
	effects : State(ctx, Model.State) -> List(Elem(ctx))
	effects = |model| [
		Engine.watch_changes(
			model.signal().map(|state| state.wallpaper),
			|{ url, dim }|
				[
					Engine.command(StorageSet(Wallpaper.url_key, url)),
					Engine.command(
						StorageSet(
							Wallpaper.dim_key,
							match dim {
								Dim(percent) => percent.to_str()
								ThemeDim => ""
							},
						),
					),
				],
			Engine.ignore({}),
		),
	]
}

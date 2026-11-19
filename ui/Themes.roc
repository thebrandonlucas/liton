## A theme as the custom properties the stylesheet draws with, set on the
## root, so no widget holds code of its own for themes.
import setup.Setup

Themes := [].{

	## The root's style: the theme's scheme, colors, glass, background,
	## spacing, fonts and motion. A theme whose focused edge is no brighter
	## than the others dims no pane either. Without `glass`, the tiles keep their tint
	## but blur nothing, which spares the graphics card.
	style : Setup.Theme, Bool -> Str
	style = |theme, glass| {
		blurred = glass and theme.glass.blur > 0
		backdrop = |blur, saturate| if (blurred) "blur(${blur.to_str()}px) saturate(${saturate}%)" else "none"
		background =
			match theme.background {
				Gradient({ base, from, to, glow }) => "radial-gradient(70vmax 50vmax at 6% -10%, color-mix(in srgb, ${glow} 20%, transparent), transparent 65%), radial-gradient(80vmax 70vmax at 105% 110%, ${to}, transparent 70%), linear-gradient(160deg, ${from}, ${base} 60%)"
				Flat(color) => color
				Image(picture) => Themes.image(theme, picture)
			}
		properties = [
			("color-scheme", if (theme.scheme == Light) "light" else "dark"),
			("--accent", theme.accent),
			("--accent-to", theme.accent_to),
			("--text", theme.text),
			("--muted", theme.muted),
			("--edge-alpha", "${theme.edge.to_str()}%"),
			("--edge-active-alpha", "${theme.edge_active.to_str()}%"),
			("--unfocused-opacity", if (theme.edge_active > theme.edge) ".86" else "1"),
			("--glass-tint", theme.glass.tint),
			("--glass-alpha", "${theme.glass.opacity.to_str()}%"),
			("--backdrop", backdrop(theme.glass.blur, "110")),
			("--backdrop-bar", backdrop(theme.glass.blur * 3, "120")),
			# Settings, over the tiles, hides them unless it blurs them.
			("--sheet-alpha", if (blurred) "90%" else "100%"),
			("--background", background),
			("--gap", "${theme.gap.to_str()}px"),
			("--radius", "${theme.radius.to_str()}px"),
			("--font-ui", theme.fonts.ui),
			("--font-mono", theme.fonts.mono),
			("--font-display", theme.fonts.display),
			("--motion", if (theme.motion == Reduced) "0" else "1"),
		]
		Str.join_with(properties.map(|(name, value)| "${name}: ${value}"), "; ")
	}

	## An image covering the root, dimmed towards black (white in a light
	## theme) by `dim` percent at its centre and 30 more at its edges, over the
	## glass tint while it loads. A quote or backslash in the URL is escaped.
	image : Setup.Theme, { url : Str, dim : U8 } -> Str
	image = |theme, { url, dim }| {
		shade = if (theme.scheme == Light) "255 255 255" else "0 0 0"
		edge = if (dim > 70) 100 else dim + 30
		quoted = url.replace_each("\\", "%5C").replace_each("\"", "%22").replace_each("\n", "")
		"radial-gradient(rgb(${shade} / ${dim.to_str()}%), rgb(${shade} / ${edge.to_str()}%)), url(\"${quoted}\") center / cover no-repeat, ${theme.glass.tint}"
	}

	## A theme's swatch in the picker: its accent edge over its background.
	swatch : Setup.Theme -> Str
	swatch = |theme| {
		ground =
			match theme.background {
				Gradient({ from, .. }) => from
				Flat(color) => color
				Image(picture) => Themes.image(theme, picture)
			}
		"background: linear-gradient(135deg, transparent 0 45%, ${theme.accent} 55%, ${theme.accent_to}), ${ground}"
	}
}

expect {
	style = Themes.style({ name: "Plain", scheme: Light, accent: "#3559e0", accent_to: "#3559e0", text: "#1d1d1b", muted: "#5f5f5a", edge: 18, edge_active: 80, glass: { tint: "#ffffff", opacity: 100, blur: 0 }, background: Flat("#f2f2ef"), gap: 8, radius: 8, fonts: { ui: "system-ui", mono: "monospace", display: "serif" }, motion: Reduced }, Bool.True)
	style == "color-scheme: light; --accent: #3559e0; --accent-to: #3559e0; --text: #1d1d1b; --muted: #5f5f5a; --edge-alpha: 18%; --edge-active-alpha: 80%; --unfocused-opacity: .86; --glass-tint: #ffffff; --glass-alpha: 100%; --backdrop: none; --backdrop-bar: none; --sheet-alpha: 100%; --background: #f2f2ef; --gap: 8px; --radius: 8px; --font-ui: system-ui; --font-mono: monospace; --font-display: serif; --motion: 0"
}

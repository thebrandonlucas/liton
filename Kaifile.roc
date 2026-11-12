# liton's development environment.
app [kaifile] {
	pf: platform "https://github.com/thebrandonlucas/kai/releases/download/v0.0.12/G3CQ6Ed3h7vyvV4eDvwH1J8UqBv2wEtkb9jLJhFkU5ny.tar.zst",
	std: "https://github.com/thebrandonlucas/kai/releases/download/v0.0.12/std-6VuNBrdv6tT7ZAVD4bWGBYYwk1KJoXP7gCnFip5VSK11.tar.zst",
}

import std.FlakeRef
import std.Std
import std.Tool

import ".roc-overlay" as roc_overlay : Str
import ".roc-version" as roc_version : Str

# The Roc compiler .roc-version pins, from the roc-overlay .roc-overlay pins.
overlay =
	FlakeRef.from_quote(roc_overlay.trim()).map_ok(|ref| [Overlay("roc", ref)])
		?? []

roc = Tool.from_quote("rocpkgs.${roc_version.trim()}").map_ok(|t| [t]) ?? []

kaifile = Std.kaifile(
	[
		Name("liton"),
		Systems(["x86_64-linux", "aarch64-linux", "aarch64-darwin"]),
	].concat(overlay).concat([
		Environment(
			"dev",
			[
				Overlays(["roc"]),
				Tools(roc.concat(["zig_0_16", "git", "nodejs"])),
			],
		),
		Shell("default", [Use("dev")]),
		Task("test", [Use("dev"), Run(["zig", "build", "test"])]),
		Task("fmt", [Use("dev"), Run(["zig", "build", "fmt"])]),
	]),
)

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
import "ui/.roc-version" as ui_roc_version : Str

# The Roc compilers .roc-version and ui/.roc-version pin, from the roc-overlay
# .roc-overlay pins: the daemon's as roc, the UI's as roc-ui.
overlay =
	FlakeRef.from_quote(roc_overlay.trim()).map_ok(|ref| [Overlay("roc", ref)])
		?? []

roc = Tool.from_quote("rocpkgs.${roc_version.trim()}").map_ok(|t| [t]) ?? []

# The UI's platform, roc-signals 0.5.0, needs a later nightly than the daemon's,
# basic-webserver 0.21.0, runs on. Once basic-webserver runs on it, move
# .roc-version to it, delete ui/.roc-version and ui_roc, and make build.zig's
# roc-ui default roc.
ui_roc =
	Tool.from_quote("rocpkgs.${ui_roc_version.trim()}").map_ok(|t| [Alias("roc-ui", t, "roc")])
		?? []

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
			].concat(ui_roc),
		),
		Shell("default", [Use("dev")]),
		Task("test", [Use("dev"), Run(["zig", "build", "test"])]),
		Task("fmt", [Use("dev"), Run(["zig", "build", "fmt"])]),
	]),
)

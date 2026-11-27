# The browser UI's build and its specs, which build.zig runs with the UI's
# Roc compiler and roc-signals's release bundle.
import pf.Cmd
import pf.OsStr
import pf.Path
import Exec

Ui := [].{

	## The browser UI, its page and roc-signals's runtime files, into
	## `output`. `flags` go to roc-ui's build, such as --opt=size and
	## --specialize=no.
	build! : Str, Str, List(Str), List(Str) => Try({}, _)
	build! = |roc_ui, output, runtime_files, flags| {
		Path.create_all!(Path.utf8(output))?
		# FIXME: the LLVM backend never reuses a function's stack slots
		# (roc-lang/roc#13320, #13094, #13319, #13321), so the UI's view
		# functions have frames of up to 3 MB, and mounting the page needs
		# more than wasm's default 8 MB stack: it traps with "memory access
		# out of bounds". So the stack is 32 MB. Drop --wasm-stack-size once
		# a Roc nightly fixes those and the page mounts on the default.
		Exec.call!(".", roc_ui, ["build", "--wasm-stack-size=33554432"].concat(flags).concat(["--target=wasm32", "ui/main.roc", "--output=${output}/app.wasm"]))?
		for file in ["index.html", "style.css", "ports.mjs", "voice.mjs", "voice-worklet.js"].map(|name| "ui/${name}").concat(runtime_files) {
			name = Path.display(Path.filename(Path.utf8(file)) ?? Path.utf8(file))
			Path.copy!(Path.utf8(file), Path.utf8("${output}/${name}"))?
		}
		Path.copy_dir_with!(Path.utf8("ui/backgrounds"), Path.utf8("${output}/backgrounds"), { symlinks: Follow, destination: Merge })?
		Path.copy_dir_with!(Path.utf8("ui/previews"), Path.utf8("${output}/previews"), { symlinks: Follow, destination: Merge })
	}

	## The UI's .scm specs, in `runner`, the native runner roc-signals builds
	## the UI into.
	specs! : Str => Try({}, _)
	specs! = |runner| {
		specs = Path.list!(Path.utf8("ui/specs"))?.map(Path.display).keep_if(|path| path.ends_with(".scm"))
		Cmd.new(OsStr.from_str(runner)).args(Ui.ordered(specs).map(OsStr.from_str)).call!()
	}

	## `paths` in a shell glob's order, by their bytes.
	ordered : List(Str) -> List(Str)
	ordered = |paths| paths.sort_with(|left, right| compared(left.to_utf8(), right.to_utf8()))
}

# Str has no compare yet, so this compares two strings' bytes.
compared : List(U8), List(U8) -> [Before, Same, After]
compared = |left, right|
	match (left, right) {
		([], []) => Same
		([], _) => Before
		(_, []) => After
		([first_left, .. as rest_left], [first_right, .. as rest_right]) =>
			if first_left < first_right {
				Before
			} else if first_left > first_right {
				After
			} else {
				compared(rest_left, rest_right)
			}
	}

expect Ui.ordered(["ui/specs/b.scm", "ui/specs/a-b.scm", "ui/specs/a.scm"]) == ["ui/specs/a-b.scm", "ui/specs/a.scm", "ui/specs/b.scm"]

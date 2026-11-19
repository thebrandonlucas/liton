# liton's API documentation: `roc docs` of each package and app, from their
# `##` comments, and a page linking them.
import pf.Path
import Exec

Docs := [].{

	## The packages and apps documented, by their directories. The devtool and
	## the CLI are left out: on basic-cli 0.28.1, `roc docs` of an app on it
	## fails, since Cmd.roc's comments link methods through the alias
	## `Command`, which this Roc doesn't resolve
	## (https://github.com/roc-lang/roc/issues/13018, fixed by
	## https://github.com/roc-lang/roc/pull/13082). A Roc nightly after
	## 2026-11-15 allows adding them.
	documented : List(Str)
	documented = ["capabilities", "setup", "transformers", "providers/mock", "providers/paseo", "providers/remote", "providers/local-speech", "daemon", "ui"]

	## Each of `documented` into its directory under `output`, the UI's with
	## `roc_ui` and the rest with `roc`, and `output`'s index.html.
	build! : Str, Str, Str => Try({}, _)
	build! = |roc, roc_ui, output| {
		Path.create_all!(Path.utf8(output))?
		var $summaries = []
		for directory in Docs.documented {
			compiler = if (directory == "ui") roc_ui else roc
			Exec.call!(".", compiler, ["docs", "${directory}/main.roc", "--output=${output}/${directory}"])?
			source = Path.read_utf8!(Path.utf8("${directory}/main.roc"))?
			$summaries = $summaries.append((directory, Docs.summary(source)))
		}
		Path.write_utf8!(Path.utf8("${output}/index.html"), Docs.index($summaries))
	}

	## The first paragraph of the `##` comment `source` starts with.
	summary : Str -> Str
	summary = |source| {
		var $lines = []
		for line in source.split_on("\n") {
			if line == "##" or !line.starts_with("## ") {
				break
			}
			$lines = $lines.append(line.drop_prefix("## "))
		}
		Str.join_with($lines, " ")
	}

	## The page linking each documented directory, with its summary.
	index : List((Str, Str)) -> Str
	index = |summaries| {
		items = summaries.map(|(directory, text)| "<li><a href=\"${directory}/\">${directory}</a>: ${escaped(text)}</li>")
		\\<!DOCTYPE html>
		\\<html lang="en">
		\\<head>
		\\<meta charset="utf-8">
		\\<meta name="viewport" content="width=device-width">
		\\<title>liton API docs</title>
		\\<link rel="stylesheet" href="capabilities/styles.css">
		\\</head>
		\\<body>
		\\<main style="max-width: 50rem; margin: 2rem auto; padding: 0 1rem">
		\\<h1>liton API docs</h1>
		\\<p>From the <code>##</code> comments of liton's packages and apps.</p>
		\\<ul>
		\\${Str.join_with(items, "\n")}
		\\</ul>
		\\</main>
		\\</body>
		\\</html>
		\\
	}
}

# `text` as HTML text, its markup characters escaped.
escaped : Str -> Str
escaped = |text| text.replace_each("&", "&amp;").replace_each("<", "&lt;").replace_each(">", "&gt;")

expect Docs.summary("## A package.\n## Pure.\n##\n## More.\npackage [A] {}") == "A package. Pure."
expect Docs.summary("package [A] {}") == ""
expect Docs.index([("setup", "a < b")]).contains("<li><a href=\"setup/\">setup</a>: a &lt; b</li>")

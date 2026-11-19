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
			for page in html_files!("${output}/${directory}")? {
				Path.write_utf8!(Path.utf8(page), Docs.filed(Path.read_utf8!(Path.utf8(page))?))?
			}
			source = Path.read_utf8!(Path.utf8("${directory}/main.roc"))?
			$summaries = $summaries.append((directory, Docs.summary(source)))
		}
		Path.write_utf8!(Path.utf8("${output}/index.html"), Docs.index($summaries))
	}

	## `html` with its links to a directory linking its index.html, since the
	## daemon's file routes, which serve the docs, look up no index.
	filed : Str -> Str
	filed = |html| {
		pieces = html.split_on("href=\"")
		linked = pieces.drop_first(1).map(
			|piece|
				match piece.split_first("\"") {
					Ok({ before, after }) => "${filed_link(before)}\"${after}"
					Err(_) => piece
				},
		)
		Str.join_with(pieces.take_first(1).concat(linked), "href=\"")
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
		items = summaries.map(|(directory, text)| "<li><a href=\"${directory}/index.html\">${directory}</a>: ${escaped(text)}</li>")
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

# `link`, if relative and to a directory, to its index.html.
filed_link : Str -> Str
filed_link = |link| {
	(path, fragment) = match link.split_first("#") {
		Ok({ before, after }) => (before, "#${after}")
		Err(_) => (link, "")
	}
	if link.starts_with("#") or link.starts_with("/") or link.contains(":") {
		link
	} else if path == "" or path == "." or path.ends_with("/") {
		"${path.drop_suffix(".")}index.html${fragment}"
	} else {
		link
	}
}

# The .html files under `directory`, at any depth.
html_files! : Str => Try(List(Str), _)
html_files! = |directory| {
	var $found = []
	for entry in Path.list!(Path.utf8(directory))? {
		path = Path.display(entry)
		if Path.is_dir!(entry)? {
			$found = $found.concat(html_files!(path)?)
		} else if path.ends_with(".html") {
			$found = $found.append(path)
		}
	}
	Ok($found)
}

# `text` as HTML text, its markup characters escaped.
escaped : Str -> Str
escaped = |text| text.replace_each("&", "&amp;").replace_each("<", "&lt;").replace_each(">", "&gt;")

expect Docs.summary("## A package.\n## Pure.\n##\n## More.\npackage [A] {}") == "A package. Pure."
expect Docs.summary("package [A] {}") == ""
expect Docs.index([("setup", "a < b")]).contains("<li><a href=\"setup/index.html\">setup</a>: a &lt; b</li>")
expect Docs.filed("<a href=\"Chat/#Chat.Event\">E</a><a href=\"../\"></a><a href=\".\"></a><a href=\"#x\"></a><a href=\"styles.css\"></a><a href=\"https://roc-lang.org/\"></a>") == "<a href=\"Chat/index.html#Chat.Event\">E</a><a href=\"../index.html\"></a><a href=\"index.html\"></a><a href=\"#x\"></a><a href=\"styles.css\"></a><a href=\"https://roc-lang.org/\"></a>"
expect Docs.filed("<article data-href=\"Chat/\"></article>") == "<article data-href=\"Chat/index.html\"></article>"

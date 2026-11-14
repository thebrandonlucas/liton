## Markdown as data the chat draws as elements: no HTML is made, so an
## agent's text can't inject any. Ported from the kai website's
## signals/Markdown.roc (the same developer's), which makes HTML instead.
##
## Blocks: ATX headings, paragraphs, block quotes, fenced and indented code,
## bullet and ordered lists (nested by indentation), thematic breaks and
## tables, as their source. Inline: code spans, emphasis, strong emphasis,
## strikethrough, links (http, https and mailto only; images show as links
## to them), autolinks (`<url>` and bare `https://` links), backslash
## escapes, a few entities and hard line breaks. Raw HTML is text.
##
## roc-signals 0.5.0 draws a tree from data only to a depth fixed in the
## code (roc-issues RS-013), so blocks are flat: a nested list is one list
## whose items have depths, and what sits in a quote or list item has its
## `quote` and `indent`.
import Highlight

Markdown := [].{

	## A run of text set alike: `class` is some of `strong`, `em`, `del` and
	## `code`, space-separated; `href` is a link's target, or "".
	Span : { text : Str, class : Str, href : Str }

	## A list item: how deep it is nested, its bullet or number, its text.
	Item : { depth : U64, marker : Str, spans : List(Markdown.Span) }

	## `level` is a heading's. `code` is a code block's, highlighted line by
	## line.
	Block : {
		key : Str,
		kind : [Paragraph, Heading, Code, List, Rule],
		level : U64,
		indent : U64,
		quote : U64,
		spans : List(Markdown.Span),
		items : List(Markdown.Item),
		code : { language : Str, text : Str, lines : List(List(Highlight.Token)) },
	}

	blocks : Str -> List(Markdown.Block)
	blocks = |source| parse(source.replace_each("\r\n", "\n").replace_each("\t", "    ").split_on("\n"), 0, 0).map_with_index(|block, index| { ..block, key: index.to_str() })
}

block_of : [Paragraph, Heading, Code, List, Rule], U64, U64 -> Markdown.Block
block_of = |kind, indent, quote| { key: "", kind, level: 0, indent, quote, spans: [], items: [], code: { language: "", text: "", lines: [] } }

parse : List(Str), U64, U64 -> List(Markdown.Block)
parse = |lines, indent, quote| {
	var $out = []
	var $i = 0
	while $i < lines.len() {
		found = next_block(lines, $i, indent, quote)
		$out = $out.concat(found.blocks)
		$i = found.next
	}
	$out
}

Found : { blocks : List(Markdown.Block), next : U64 }

next_block : List(Str), U64, U64, U64 -> Found
next_block = |lines, i, indent, quote| {
	line = lines.get(i) ?? ""
	if is_blank(line) {
		{ blocks: [], next: i + 1 }
	} else if indent_of(line) >= 4 {
		indented_code(lines, i, indent, quote)
	} else {
		match (fence_of(line), heading_of(line), quote_of(line), marker_of(line)) {
			(Ok(fence), _, _, _) => fenced_code(lines, i, fence, indent, quote)
			(_, Ok({ level, text }), _, _) => { blocks: [{ ..block_of(Heading, indent, quote), level, spans: inline(text) }], next: i + 1 }
			_ if is_rule(line) => { blocks: [block_of(Rule, indent, quote)], next: i + 1 }
			(_, _, Ok(_), _) => quoted(lines, i, indent, quote)
			(_, _, _, Ok(marker)) => list(lines, i, marker, indent, quote)
			_ if is_table_start(lines, i) => table(lines, i, indent, quote)
			_ => paragraph(lines, i, indent, quote)
		}
	}
}

# ---- Lines

is_blank : Str -> Bool
is_blank = |line| line.trim().is_empty()

indent_of : Str -> U64
indent_of = |line| run_of(line.to_utf8(), 0, ' ')

## `line` without up to `n` leading spaces.
dedent : Str, U64 -> Str
dedent = |line, n| Str.from_utf8_lossy(line.to_utf8().drop_first(indent_of(line).min(n)))

## A line that starts another block, so it ends a paragraph.
interrupts : Str -> Bool
interrupts = |line|
	is_blank(line)
		or fence_of(line).is_ok()
		or heading_of(line).is_ok()
		or is_rule(line)
		or quote_of(line).is_ok()
		or (
			match marker_of(line) {
				Ok(marker) => !is_blank(marker.rest) and (!marker.ordered or marker.start == 1)
				Err(_) => Bool.False
			}
		)

heading_of : Str -> Try({ level : U64, text : Str }, [NotHeading])
heading_of = |line| {
	bytes = line.trim_start().to_utf8()
	level = run_of(bytes, 0, '#')
	after = bytes.get(level) ?? ' '
	if indent_of(line) <= 3 and level >= 1 and level <= 6 and after == ' ' {
		text = Str.from_utf8_lossy(bytes.drop_first(level)).trim()
		# A closing run of #s, after a space, is not part of the text.
		closed = drop_trailing(text.to_utf8(), |b| b == '#')
		Ok({ level, text: if (closed.is_empty() or (closed.last() ?? 0) == ' ') Str.from_utf8_lossy(closed).trim_end() else text })
	} else {
		Err(NotHeading)
	}
}

## How many `c`s there are in a row from `at`.
run_of : List(U8), U64, U8 -> U64
run_of = |bytes, at, c| {
	var $n = 0
	while (bytes.get(at + $n) ?? 0) == c {
		$n = $n + 1
	}
	$n
}

is_rule : Str -> Bool
is_rule = |line| {
	bytes = line.to_utf8().drop_if(|b| b == ' ')
	match bytes.first() {
		Ok(c) => indent_of(line) <= 3 and (c == '-' or c == '*' or c == '_') and bytes.len() >= 3 and bytes.all(|b| b == c)
		Err(_) => Bool.False
	}
}

# ---- Code

Fence : { char : U8, len : U64, indent : U64, info : Str }

fence_of : Str -> Try(Fence, [NotFence])
fence_of = |line| {
	indent = indent_of(line)
	bytes = line.to_utf8().drop_first(indent)
	char = bytes.first() ?? 0
	len = run_of(bytes, 0, char)
	info = Str.from_utf8_lossy(bytes.drop_first(len)).trim()
	if (indent <= 3 and (char == '`' or char == '~') and len >= 3 and !(char == '`' and info.contains("`"))) Ok({ char, len, indent, info }) else Err(NotFence)
}

fenced_code : List(Str), U64, Fence, U64, U64 -> Found
fenced_code = |lines, i, fence, indent, quote| {
	var $j = i + 1
	var $body = []
	var $open = Bool.True
	while $open and $j < lines.len() {
		line = lines.get($j) ?? ""
		closing = match fence_of(line) {
			Ok(other) => other.char == fence.char and other.len >= fence.len and other.info.is_empty()
			Err(_) => Bool.False
		}
		if closing {
			$open = Bool.False
		} else {
			$body = $body.append(dedent(line, fence.indent))
		}
		$j = $j + 1
	}
	{ blocks: [code_block($body, fence.info.split_on(" ").first() ?? "", indent, quote)], next: $j }
}

indented_code : List(Str), U64, U64, U64 -> Found
indented_code = |lines, i, indent, quote| {
	var $j = i
	var $body = []
	while $j < lines.len() and (indent_of(lines.get($j) ?? "") >= 4 or is_blank(lines.get($j) ?? "")) {
		$body = $body.append(dedent(lines.get($j) ?? "", 4))
		$j = $j + 1
	}
	{ blocks: [code_block(trim_blank_end($body), "", indent, quote)], next: $j }
}

code_block : List(Str), Str, U64, U64 -> Markdown.Block
code_block = |lines, language, indent, quote| { ..block_of(Code, indent, quote), code: { language, text: Str.join_with(lines, "\n"), lines: Highlight.lines(language, lines) } }

trim_blank_end : List(Str) -> List(Str)
trim_blank_end = |lines|
	match lines.last() {
		Ok(last) if is_blank(last) => trim_blank_end(lines.drop_last(1))
		_ => lines
	}

# ---- Quotes

quote_of : Str -> Try(Str, [NotQuote])
quote_of = |line| {
	trimmed = line.trim_start()
	if (indent_of(line) > 3 or !trimmed.starts_with(">")) Err(NotQuote) else Ok(if (trimmed.starts_with("> ")) trimmed.drop_prefix("> ") else trimmed.drop_prefix(">"))
}

quoted : List(Str), U64, U64, U64 -> Found
quoted = |lines, i, indent, quote| {
	var $j = i
	var $inner = []
	var $more = Bool.True
	while $more and $j < lines.len() {
		line = lines.get($j) ?? ""
		match quote_of(line) {
			Ok(rest) => {
				$inner = $inner.append(rest)
				$j = $j + 1
			}
			# A lazy continuation of the quote's last paragraph.
			Err(_) if !interrupts(line) and !is_blank($inner.last() ?? "") => {
				$inner = $inner.append(line)
				$j = $j + 1
			}
			Err(_) => {
				$more = Bool.False
			}
		}
	}
	{ blocks: parse($inner, indent, quote + 1), next: $j }
}

# ---- Lists

## A list item's marker: `indent` spaces, the bullet or number, and the
## spaces after it, `width` in all; `rest` is the line after them.
Marker : { ordered : Bool, bullet : U8, start : U64, indent : U64, width : U64, rest : Str }

marker_of : Str -> Try(Marker, [NotMarker])
marker_of = |line| {
	indent = indent_of(line)
	bytes = line.to_utf8().drop_first(indent)
	first = bytes.first() ?? 0
	digits = take_while(bytes, is_digit).len()
	after_digits = bytes.get(digits) ?? 0
	found =
		if first == '-' or first == '*' or first == '+' {
			Ok({ ordered: Bool.False, bullet: first, start: 1, len: 1 })
		} else if digits >= 1 and digits <= 9 and (after_digits == '.' or after_digits == ')') {
			Ok({ ordered: Bool.True, bullet: after_digits, start: bytes.take_first(digits).fold(0, |n, b| n * 10 + (b - '0').to_u64()), len: digits + 1 })
		} else {
			Err(NotMarker)
		}
	match found {
		Ok(m) => {
			after = bytes.drop_first(m.len)
			spaces = run_of(after, 0, ' ')
			if indent > 3 or (spaces == 0 and !after.is_empty()) {
				Err(NotMarker)
			} else {
				# More than four spaces start indented code inside the item.
				gap = if (spaces > 4 or after.is_empty()) 1 else spaces
				Ok({ ordered: m.ordered, bullet: m.bullet, start: m.start, indent, width: indent + m.len + gap, rest: Str.from_utf8_lossy(after.drop_first(gap)) })
			}
		}
		Err(e) => Err(e)
	}
}

## Each item's first paragraph is its text; a list nested in it joins this
## one, deeper; anything else in it ends the list, which goes on after it.
list : List(Str), U64, Marker, U64, U64 -> Found
list = |lines, i, first, indent, quote| {
	var $j = i
	var $out = []
	var $number = first.start
	var $more = Bool.True
	while $more {
		marker = marker_of(lines.get($j) ?? "") ?? first
		item = list_item(lines, $j, marker)
		content = parse(item.lines, indent + 1, quote)
		(spans, rest) = match content.first() {
			Ok(lead) if lead.kind == Paragraph => (lead.spans, content.drop_first(1))
			_ => ([], content)
		}
		$out = with_item($out, { depth: 0, marker: if (first.ordered) "${$number.to_str()}." else "•", spans }, first.ordered, indent, quote)
		$out = rest.fold(
			$out,
			|so_far, block|
				if (block.kind == List and block.indent == indent + 1 and block.quote == quote)
					block.items.fold(so_far, |deeper, nested| with_item(deeper, { ..nested, depth: nested.depth + 1, marker: if (nested.marker == "•") "◦" else nested.marker }, first.ordered, indent, quote))
				else
					so_far.append(block),
		)
		$number = $number + 1
		$j = item.next
		$more = match marker_of(lines.get($j) ?? "") {
			Ok(other) => other.ordered == first.ordered and other.bullet == first.bullet and other.indent < first.width
			_ => Bool.False
		}
	}
	{ blocks: $out, next: $j }
}

with_item : List(Markdown.Block), Markdown.Item, Bool, U64, U64 -> List(Markdown.Block)
with_item = |blocks, item, ordered, indent, quote|
	match blocks.last() {
		Ok(last) if last.kind == List and last.indent == indent and last.quote == quote => blocks.drop_last(1).append({ ..last, items: last.items.append(item) })
		_ => blocks.append({ ..block_of(List, indent, quote), level: if (ordered) 1 else 0, items: [item] })
	}

list_item : List(Str), U64, Marker -> { lines : List(Str), next : U64 }
list_item = |lines, i, marker| {
	var $body = [marker.rest]
	var $j = i + 1
	var $blank = Bool.False
	var $more = Bool.True
	while $more and $j < lines.len() {
		line = lines.get($j) ?? ""
		if is_blank(line) {
			$blank = Bool.True
			$body = $body.append("")
			$j = $j + 1
		} else if indent_of(line) >= marker.width {
			$blank = Bool.False
			$body = $body.append(dedent(line, marker.width))
			$j = $j + 1
		} else if !$blank and !interrupts(line) {
			# A lazy continuation of the item's paragraph.
			$body = $body.append(line.trim_start())
			$j = $j + 1
		} else {
			$more = Bool.False
		}
	}
	{ lines: trim_blank_end($body), next: $j }
}

# ---- Tables

## A table shows as its source, in a code block: drawn as a table, its
## cells nest a level deeper than roc-signals 0.5.0 draws cheaply (about
## 780 KB more of the UI's download).
is_table_start : List(Str), U64 -> Bool
is_table_start = |lines, i| {
	head = lines.get(i) ?? ""
	delimiter = lines.get(i + 1) ?? ""
	cells = cells_of(delimiter)
	head.contains("|") and delimiter.contains("-") and cells_of(head).len() == cells.len() and cells.all(|cell| !cell.drop_prefix(":").drop_suffix(":").is_empty() and cell.drop_prefix(":").drop_suffix(":").to_utf8().all(|b| b == '-'))
}

## A row's cells: split on `|`s that are not escaped or in code, without the
## outer pipes.
cells_of : Str -> List(Str)
cells_of = |line| {
	inner = line.trim().drop_prefix("|")
	bytes = (if (inner.ends_with("\\|")) inner else inner.drop_suffix("|")).to_utf8()
	var $cells = []
	var $cell = []
	var $code = Bool.False
	var $i = 0
	while $i < bytes.len() {
		b = bytes.get($i) ?? 0
		if b == '\\' and (bytes.get($i + 1) ?? 0) == '|' {
			$cell = $cell.append('|')
			$i = $i + 2
		} else {
			$code = if (b == '`') !$code else $code
			if b == '|' and !$code {
				$cells = $cells.append(Str.from_utf8_lossy($cell).trim())
				$cell = []
			} else {
				$cell = $cell.append(b)
			}
			$i = $i + 1
		}
	}
	$cells.append(Str.from_utf8_lossy($cell).trim())
}

table : List(Str), U64, U64, U64 -> Found
table = |lines, i, indent, quote| {
	rows = lines.drop_first(i).find_first_index(|line| is_blank(line) or !line.contains("|")) ?? (lines.len() - i)
	{ blocks: [code_block(lines.sublist({ start: i, len: rows }).map(Str.trim), "", indent, quote)], next: i + rows }
}

paragraph : List(Str), U64, U64, U64 -> Found
paragraph = |lines, i, indent, quote| {
	var $j = i + 1
	var $text = [(lines.get(i) ?? "").trim_start()]
	while $j < lines.len() and !interrupts(lines.get($j) ?? "") {
		$text = $text.append((lines.get($j) ?? "").trim_start())
		$j = $j + 1
	}
	{ blocks: [{ ..block_of(Paragraph, indent, quote), spans: inline(Str.join_with($text, "\n").trim_end()) }], next: $j }
}

# ---- Inline

Style : { class : Str, href : Str }

inline : Str -> List(Markdown.Span)
inline = |text| merged(spans_of(text.to_utf8(), { class: "", href: "" }))

## Spans set alike, side by side, as one.
merged : List(Markdown.Span) -> List(Markdown.Span)
merged = |spans|
	spans.fold(
		[],
		|so_far, span|
			match so_far.last() {
				Ok(last) if last.class == span.class and last.href == span.href => so_far.drop_last(1).append({ ..last, text: last.text.concat(span.text) })
				_ if span.text.is_empty() => so_far
				_ => so_far.append(span)
			},
	)

## A run of inline Markdown, each character set as `style` unless a
## construct sets it otherwise.
spans_of : List(U8), Style -> List(Markdown.Span)
spans_of = |bytes, style| {
	var $out = []
	var $run = []
	var $i = 0
	while $i < bytes.len() {
		found = span_at(bytes, $i, style)
		match found.out {
			Plain(text) => {
				$run = $run.concat(text)
			}
			Spans(spans) => {
				$out = $out.append({ text: Str.from_utf8_lossy($run), class: style.class, href: style.href }).concat(spans)
				$run = []
			}
		}
		$i = found.next
	}
	$out.append({ text: Str.from_utf8_lossy($run), class: style.class, href: style.href })
}

Spanned : { out : [Plain(List(U8)), Spans(List(Markdown.Span))], next : U64 }

## The span that starts at `i`: a construct, or one character.
span_at : List(U8), U64, Style -> Spanned
span_at = |bytes, i, style| {
	c = bytes.get(i) ?? 0
	next = bytes.get(i + 1) ?? 0
	prev = if (i == 0) ' ' else bytes.get(i - 1) ?? ' '
	plain = { out: Plain([c]), next: i + 1 }
	if c == '\\' and next == '\n' {
		{ out: Plain(['\n']), next: i + 2 }
	} else if c == '\\' and is_punct(next) {
		{ out: Plain([next]), next: i + 2 }
	} else if c == '`' {
		code_span(bytes, i, style)
	} else if c == '*' or c == '_' or (c == '~' and next == '~') {
		emphasis(bytes, i, style) ?? plain
	} else if c == '!' and next == '[' {
		link(bytes, i + 1, style) ?? plain
	} else if c == '[' {
		link(bytes, i, style) ?? plain
	} else if c == '<' {
		autolink(bytes, i, style) ?? plain
	} else if c == '&' {
		entity(bytes, i) ?? plain
	} else if c == 'h' and !is_alnum(prev) and style.href.is_empty() {
		bare_url(bytes, i, style) ?? plain
	} else if c == ' ' {
		spaces = run_of(bytes, i, ' ')
		# Spaces end a line, or two or more break it.
		if ((bytes.get(i + spaces) ?? 0) == '\n') { out: Plain([]), next: i + spaces } else plain
	} else {
		plain
	}
}

with_class : Style, Str -> Style
with_class = |style, class| { ..style, class: if (style.class.is_empty()) class else "${style.class} ${class}" }

code_span : List(U8), U64, Style -> Spanned
code_span = |bytes, i, style| {
	len = run_of(bytes, i, '`')
	start = i + len
	match closing_ticks(bytes, start, len) {
		Ok(end) => {
			raw = Str.from_utf8_lossy(bytes.sublist({ start, len: end - start })).replace_each("\n", " ")
			text = if (raw.starts_with(" ") and raw.ends_with(" ") and !raw.trim().is_empty()) raw.drop_prefix(" ").drop_suffix(" ") else raw
			{ out: Spans([{ text, class: with_class(style, "code").class, href: style.href }]), next: end + len }
		}
		Err(_) => { out: Plain(bytes.sublist({ start: i, len })), next: start }
	}
}

## Where a run of exactly `len` backticks starts, from `from` on.
closing_ticks : List(U8), U64, U64 -> Try(U64, [NotFound])
closing_ticks = |bytes, from, len| {
	var $at = from
	var $found = Bool.False
	while !$found and $at < bytes.len() {
		run = run_of(bytes, $at, '`')
		if run == len {
			$found = Bool.True
		} else {
			$at = $at + U64.max(run, 1)
		}
	}
	if ($found) Ok($at) else Err(NotFound)
}

## `*em*`, `**strong**`, `***both***` (or with `_`) and `~~del~~`. An
## underscore inside a word is a character, not emphasis.
emphasis : List(U8), U64, Style -> Try(Spanned, [NotEmphasis])
emphasis = |bytes, i, style| {
	c = bytes.get(i) ?? 0
	prev = if (i == 0) ' ' else bytes.get(i - 1) ?? ' '
	run = run_of(bytes, i, c)
	if is_space(bytes.get(i + run) ?? ' ') or (c == '_' and is_alnum(prev)) {
		Err(NotEmphasis)
	} else {
		tries = if (c == '~') [2] else if (run >= 3) [3, 2, 1] else if (run == 2) [2, 1] else [1]
		tries.fold_until(
			Err(NotEmphasis),
			|_, n|
				match closing_delimiter(bytes, i + n, c, n) {
					Ok(end) => {
						set = if (c == '~') with_class(style, "del") else if (n == 3) with_class(with_class(style, "strong"), "em") else if (n == 2) with_class(style, "strong") else with_class(style, "em")
						Break(Ok({ out: Spans(spans_of(bytes.sublist({ start: i + n, len: end - i - n }), set)), next: end + n }))
					}
					Err(_) => Continue(Err(NotEmphasis))
				},
		)
	}
}

## Where the delimiter run of `n` `c`s that closes one opened before `from`
## starts. Code spans and longer runs are stepped over.
closing_delimiter : List(U8), U64, U8, U64 -> Try(U64, [NotFound])
closing_delimiter = |bytes, from, c, n| {
	var $at = from
	var $found = Bool.False
	var $end = 0
	while !$found and $at < bytes.len() {
		b = bytes.get($at) ?? 0
		if b == '`' {
			len = run_of(bytes, $at, '`')
			$at = match closing_ticks(bytes, $at + len, len) {
				Ok(end) => end + len
				Err(_) => $at + len
			}
		} else if b == '\\' {
			$at = $at + 2
		} else if b == c {
			run = run_of(bytes, $at, c)
			closes = $at > from and !is_space(bytes.get($at - 1) ?? ' ') and !(c == '_' and is_alnum(bytes.get($at + run) ?? ' '))
			if closes and (run == n or (n < 3 and run == 3)) {
				$found = Bool.True
				$end = $at + run - n
			} else {
				{}
			}
			$at = $at + run
		} else {
			$at = $at + 1
		}
	}
	if ($found) Ok($end) else Err(NotFound)
}

## Whether a link may go to `url`: the web or mail, never a script.
safe : Str -> Bool
safe = |url| ["https://", "http://", "mailto:"].any(|scheme| url.with_ascii_lowercased().starts_with(scheme))

## `[text](url "title")`, or `![alt](src)` from the `[`, as a link to it.
link : List(U8), U64, Style -> Try(Spanned, [NotLink])
link = |bytes, i, style|
	match matching(bytes, i, '[', ']') {
		Ok(close) if (bytes.get(close + 1) ?? 0) == '(' =>
			match matching(bytes, close + 1, '(', ')') {
				Ok(end) => {
					label = bytes.sublist({ start: i + 1, len: close - i - 1 })
					target = Str.from_utf8_lossy(bytes.sublist({ start: close + 2, len: end - close - 2 })).trim()
					url = (target.split_first(" ").map_ok(|parts| parts.before) ?? target).drop_prefix("<").drop_suffix(">")
					Ok({ out: Spans(spans_of(label, if (safe(url) and style.href.is_empty()) { ..style, href: url } else style)), next: end + 1 })
				}
				Err(_) => Err(NotLink)
			}
		_ => Err(NotLink)
	}

## The index of the bracket that closes the one at `i`.
matching : List(U8), U64, U8, U8 -> Try(U64, [NotFound])
matching = |bytes, i, open, close| {
	var $depth = 0
	var $at = i
	var $found = Bool.False
	while !$found and $at < bytes.len() {
		b = bytes.get($at) ?? 0
		if b == '\\' {
			$at = $at + 2
		} else if b == close and $depth == 1 {
			$found = Bool.True
		} else {
			$depth = if (b == open) $depth + 1 else if (b == close) $depth - 1 else $depth
			$at = $at + 1
		}
	}
	if ($found) Ok($at) else Err(NotFound)
}

## `<https://...>`.
autolink : List(U8), U64, Style -> Try(Spanned, [NotLink])
autolink = |bytes, i, style|
	match bytes.drop_first(i + 1).find_first_index(|b| b == '>') {
		Ok(len) => {
			inside = Str.from_utf8_lossy(bytes.sublist({ start: i + 1, len }))
			if (safe(inside) and !inside.contains(" ")) Ok({ out: Spans([{ text: inside.drop_prefix("mailto:"), class: style.class, href: inside }]), next: i + len + 2 }) else Err(NotLink)
		}
		Err(_) => Err(NotLink)
	}

## The entities agents write most.
entity : List(U8), U64 -> Try(Spanned, [NotEntity])
entity = |bytes, i| {
	known = [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", "\u(a0)")]
	rest = bytes.drop_first(i)
	known.find_first(|(name, _)| rest.starts_with(name.to_utf8())).map_ok(|(name, text)| { out: Plain(text.to_utf8()), next: i + name.count_utf8_bytes() }).map_err(|_| NotEntity)
}

## A bare `https://` or `http://` link, without the punctuation that ends a
## sentence.
bare_url : List(U8), U64, Style -> Try(Spanned, [NotUrl])
bare_url = |bytes, i, style| {
	rest = bytes.drop_first(i)
	if rest.starts_with("https://".to_utf8()) or rest.starts_with("http://".to_utf8()) {
		url = Str.from_utf8_lossy(drop_trailing(take_while(rest, |b| !is_space(b) and b != '<'), |b| b == '.' or b == ',' or b == ':' or b == ';' or b == ')' or b == '"' or b == '\'' or b == '!' or b == '?'))
		Ok({ out: Spans([{ text: url, class: style.class, href: url }]), next: i + url.count_utf8_bytes() })
	} else {
		Err(NotUrl)
	}
}

# ---- Bytes

take_while : List(U8), (U8 -> Bool) -> List(U8)
take_while = |bytes, keep| bytes.take_first(bytes.find_first_index(|b| !keep(b)) ?? bytes.len())

drop_trailing : List(U8), (U8 -> Bool) -> List(U8)
drop_trailing = |bytes, drop|
	match bytes.last() {
		Ok(b) if drop(b) => drop_trailing(bytes.drop_last(1), drop)
		_ => bytes
	}

is_space : U8 -> Bool
is_space = |b| b == ' ' or b == '\n'

is_digit : U8 -> Bool
is_digit = |b| b >= '0' and b <= '9'

## Letters and digits, and every byte of a non-ASCII character.
is_alnum : U8 -> Bool
is_alnum = |b| (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or is_digit(b) or b >= 128

is_punct : U8 -> Bool
is_punct = |b| (b >= '!' and b <= '/') or (b >= ':' and b <= '@') or (b >= '[' and b <= '`') or (b >= '{' and b <= '~')

expect inline("a *b* **c** `d` ~~e~~") == [{ text: "a ", class: "", href: "" }, { text: "b", class: "em", href: "" }, { text: " ", class: "", href: "" }, { text: "c", class: "strong", href: "" }, { text: " ", class: "", href: "" }, { text: "d", class: "code", href: "" }, { text: " ", class: "", href: "" }, { text: "e", class: "del", href: "" }]
expect inline("snake_case_name &lt;b&gt;") == [{ text: "snake_case_name <b>", class: "", href: "" }]
expect inline("[Roc](https://www.roc-lang.org) [x](javascript:alert(1)) see https://example.org.") == [{ text: "Roc", class: "", href: "https://www.roc-lang.org" }, { text: " x see ", class: "", href: "" }, { text: "https://example.org", class: "", href: "https://example.org" }, { text: ".", class: "", href: "" }]
expect Markdown.blocks("- a\n- b\n  1. c").map(|block| block.items.map(|item| (item.depth, item.marker))) == [[(0, "•"), (0, "•"), (1, "1.")]]
expect Markdown.blocks("> **hi**\n\n```sh\nnix run\n```").map(|block| (block.kind, block.quote, block.code.text)) == [(Paragraph, 1, ""), (Code, 0, "nix run")]
expect Markdown.blocks("1. Run:\n   ```\n   x\n   ```\n2. Done").map(|block| (block.kind, block.indent)) == [(List, 0), (Code, 1), (List, 0)]
expect Markdown.blocks("| a | b |\n|---|:-:|\n| 1 | `x|y` |\nafter").map(|block| (block.kind, block.code.text)) == [(Code, "| a | b |\n|---|:-:|\n| 1 | `x|y` |"), (Paragraph, "")]
expect Markdown.blocks("## Plan ##").map(|block| (block.kind, block.level, block.spans)) == [(Heading, 2, [{ text: "Plan", class: "", href: "" }])]

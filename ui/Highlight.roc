## Code highlighting, line by line, for a code block's language: comments,
## strings (with interpolation where the language has it), keywords,
## types, calls and numbers, and a diff's added and removed lines. It
## doesn't parse any language. Grown from the kai website's
## signals/RocHighlight.roc (the same developer's), which knows only Roc.
Highlight := [].{

	## A run of a line and its class ("" for plain text).
	Token : { class : Str, text : Str }

	## The lines of a block of code in `language` (a fence's info word).
	lines : Str, List(Str) -> List(List(Highlight.Token))
	lines = |language, source|
		match syntax_of(language.with_ascii_lowercased()) {
			Diff => source.map(|line| [{ class: diff_class(line), text: line }])
			Plain => source.map(|line| [{ class: "", text: line }])
			Known(syntax) =>
				source.fold(
					{ lines: [], in_comment: Bool.False },
					|so_far, line| {
						done = tokens(line.to_utf8(), syntax, so_far.in_comment)
						{ lines: so_far.lines.append(merged(done.tokens)), in_comment: done.in_comment }
					},
				).lines
		}
}

## How a language writes comments and strings, and its keywords. `dollar`
## is whether `$name` and `${...}` stand out, in strings and out.
Syntax : { keywords : List(Str), line_comment : Str, block_comment : Bool, quotes : List(U8), dollar : Bool }

c_like : List(Str) -> Syntax
c_like = |keywords| { keywords, line_comment: "//", block_comment: Bool.True, quotes: ['"', '\'', '`'], dollar: Bool.False }

hashed : List(Str) -> Syntax
hashed = |keywords| { keywords, line_comment: "#", block_comment: Bool.False, quotes: ['"', '\''], dollar: Bool.False }

syntax_of : Str -> [Known(Syntax), Diff, Plain]
syntax_of = |language|
	if ["roc"].contains(language) {
		Known({ ..hashed(["app", "platform", "package", "module", "import", "exposing", "as", "if", "else", "match", "is", "expect", "dbg", "crash", "var", "for", "in", "return", "and", "or", "not", "while"]), dollar: Bool.True })
	} else if ["sh", "bash", "shell", "zsh", "console", "shellsession"].contains(language) {
		Known({ ..hashed(["if", "then", "else", "elif", "fi", "for", "in", "do", "done", "while", "until", "case", "esac", "function", "return", "export", "local", "set", "unset", "cd", "echo", "exit", "source", "sudo"]), dollar: Bool.True })
	} else if ["ts", "typescript", "js", "javascript", "jsx", "tsx", "mjs"].contains(language) {
		Known(c_like(["const", "let", "var", "function", "return", "if", "else", "for", "while", "of", "in", "new", "class", "extends", "import", "export", "from", "default", "async", "await", "type", "interface", "true", "false", "null", "undefined", "this", "throw", "try", "catch", "typeof", "switch", "case", "break"]))
	} else if ["rust", "rs"].contains(language) {
		Known({ ..c_like(["fn", "let", "mut", "pub", "use", "mod", "struct", "enum", "impl", "trait", "for", "in", "if", "else", "match", "return", "loop", "while", "self", "Self", "crate", "where", "async", "await", "move", "ref", "const", "static", "true", "false", "dyn", "unsafe", "as"]), quotes: ['"'] })
	} else if ["zig"].contains(language) {
		Known({ ..c_like(["const", "var", "fn", "pub", "return", "if", "else", "for", "while", "switch", "try", "catch", "defer", "errdefer", "struct", "enum", "union", "error", "comptime", "true", "false", "null", "undefined", "orelse", "and", "or"]), block_comment: Bool.False, quotes: ['"', '\''] })
	} else if ["go", "c", "cpp", "c++", "h", "java", "kotlin", "swift", "cs", "csharp"].contains(language) {
		Known(c_like(["func", "package", "import", "return", "if", "else", "for", "range", "switch", "case", "break", "continue", "struct", "type", "var", "const", "int", "void", "char", "class", "public", "private", "static", "new", "true", "false", "nil", "null", "defer", "go"]))
	} else if ["py", "python"].contains(language) {
		Known(hashed(["def", "class", "return", "if", "elif", "else", "for", "while", "in", "import", "from", "as", "with", "try", "except", "finally", "raise", "lambda", "yield", "None", "True", "False", "and", "or", "not", "is", "pass", "async", "await"]))
	} else if ["nix"].contains(language) {
		Known({ ..hashed(["let", "in", "with", "rec", "inherit", "if", "then", "else", "assert", "import", "true", "false", "null"]), block_comment: Bool.True, quotes: ['"'], dollar: Bool.True })
	} else if ["json", "jsonc", "json5"].contains(language) {
		Known(c_like(["true", "false", "null"]))
	} else if ["yaml", "yml", "toml", "ini", "dockerfile", "make", "makefile"].contains(language) {
		Known(hashed(["true", "false", "null", "yes", "no"]))
	} else if ["diff", "patch"].contains(language) {
		Diff
	} else {
		Plain
	}

diff_class : Str -> Str
diff_class = |line|
	if (line.starts_with("+++") or line.starts_with("---") or line.starts_with("@@")) "tok-meta" else if (line.starts_with("+")) "tok-added" else if (line.starts_with("-")) "tok-removed" else ""

token : Str, List(U8) -> Highlight.Token
token = |class, bytes| { class, text: Str.from_utf8_lossy(bytes) }

## A line's tokens, and whether a block comment is still open after it.
tokens : List(U8), Syntax, Bool -> { tokens : List(Highlight.Token), in_comment : Bool }
tokens = |bytes, syntax, in_comment| {
	var $out = []
	var $i = 0
	var $comment = in_comment
	while $i < bytes.len() {
		c = bytes.get($i) ?? 0
		rest = bytes.drop_first($i)
		if $comment {
			end = closing(rest, "*/".to_utf8())
			$out = $out.append(token("tok-comment", rest.take_first(end.len)))
			$comment = !end.closed
			$i = $i + end.len
		} else if syntax.block_comment and rest.starts_with("/*".to_utf8()) {
			$comment = Bool.True
			$out = $out.append(token("tok-comment", ['/', '*']))
			$i = $i + 2
		} else if !syntax.line_comment.is_empty() and rest.starts_with(syntax.line_comment.to_utf8()) and ($i == 0 or c != '#' or (bytes.get($i - 1) ?? 0) == ' ') {
			$out = $out.append(token("tok-comment", rest))
			$i = bytes.len()
		} else if syntax.quotes.contains(c) {
			end = closing(rest.drop_first(1), [c])
			$out = $out.concat(string_tokens(rest.take_first(end.len + 1), syntax.dollar))
			$i = $i + end.len + 1
		} else if syntax.dollar and c == '$' {
			name = variable(rest)
			$out = $out.append(token("tok-interp", name))
			$i = $i + name.len()
		} else if is_digit(c) {
			digits = take_while(rest, |d| is_alnum(d) or d == '.' or d == '_')
			$out = $out.append(token("tok-number", digits))
			$i = $i + digits.len()
		} else if is_alpha(c) or c == '_' {
			word = take_while(rest, |d| is_alnum(d) or d == '_' or d == '!')
			after = bytes.get($i + word.len()) ?? 0
			first = word.first() ?? 0
			class = if (syntax.keywords.contains(Str.from_utf8_lossy(word))) "tok-keyword" else if (first >= 'A' and first <= 'Z') "tok-type" else if (after == '(') "tok-call" else ""
			$out = $out.append(token(class, word))
			$i = $i + word.len()
		} else {
			# One character, whole: a byte of a longer UTF-8 character is no text.
			len = if (c < 128) 1 else take_while(rest.drop_first(1), |d| d >= 128 and d < 192).len() + 1
			$out = $out.append(token("", rest.take_first(len)))
			$i = $i + len
		}
	}
	{ tokens: $out, in_comment: $comment }
}

## How many bytes run to the end of `close`, past escapes, and whether it
## came before the line ended.
closing : List(U8), List(U8) -> { len : U64, closed : Bool }
closing = |bytes, close| {
	var $i = 0
	var $closed = Bool.False
	while !$closed and $i < bytes.len() {
		if bytes.drop_first($i).starts_with(close) {
			$closed = Bool.True
			$i = $i + close.len()
		} else {
			$i = $i + (if ((bytes.get($i) ?? 0) == '\\') 2 else 1)
		}
	}
	{ len: $i.min(bytes.len()), closed: $closed }
}

## `$name`, `${...}` or a lone `$`.
variable : List(U8) -> List(U8)
variable = |bytes|
	if (bytes.get(1) ?? 0) == '{' {
		bytes.take_first(closing(bytes.drop_first(2), ['}']).len + 2)
	} else {
		bytes.take_first(take_while(bytes.drop_first(1), |d| is_alnum(d) or d == '_').len() + 1)
	}

## A string, its `$name`s and `${...}`s apart when `dollar`.
string_tokens : List(U8), Bool -> List(Highlight.Token)
string_tokens = |bytes, dollar| {
	var $out = []
	var $run = []
	var $i = 0
	while $i < bytes.len() {
		c = bytes.get($i) ?? 0
		if dollar and c == '$' and $i > 0 and (is_alpha(bytes.get($i + 1) ?? 0) or (bytes.get($i + 1) ?? 0) == '{') {
			name = variable(bytes.drop_first($i))
			$out = $out.append(token("tok-string", $run)).append(token("tok-interp", name))
			$run = []
			$i = $i + name.len()
		} else {
			$run = $run.append(c)
			$i = $i + 1
		}
	}
	$out.append(token("tok-string", $run))
}

## Tokens set alike, side by side, as one.
merged : List(Highlight.Token) -> List(Highlight.Token)
merged = |tokens_in|
	tokens_in.fold(
		[],
		|so_far, next|
			match so_far.last() {
				_ if next.text.is_empty() => so_far
				Ok(last) if last.class == next.class => so_far.drop_last(1).append({ ..last, text: last.text.concat(next.text) })
				_ => so_far.append(next)
			},
	)

take_while : List(U8), (U8 -> Bool) -> List(U8)
take_while = |bytes, keep| bytes.take_first(bytes.find_first_index(|b| !keep(b)) ?? bytes.len())

is_digit : U8 -> Bool
is_digit = |b| b >= '0' and b <= '9'

is_alpha : U8 -> Bool
is_alpha = |b| (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z')

is_alnum : U8 -> Bool
is_alnum = |b| is_alpha(b) or is_digit(b)

expect Highlight.lines("roc", ["x = Ok(\"\${a}!\") # go"]) == [[{ class: "", text: "x = " }, { class: "tok-type", text: "Ok" }, { class: "", text: "(" }, { class: "tok-string", text: "\"" }, { class: "tok-interp", text: "\${a}" }, { class: "tok-string", text: "!\"" }, { class: "", text: ") " }, { class: "tok-comment", text: "# go" }]]
expect Highlight.lines("ts", ["/* a", "b */ const"]) == [[{ class: "tok-comment", text: "/* a" }], [{ class: "tok-comment", text: "b */" }, { class: "", text: " " }, { class: "tok-keyword", text: "const" }]]
expect Highlight.lines("sh", ["echo $HOME # x"]) == [[{ class: "tok-keyword", text: "echo" }, { class: "", text: " " }, { class: "tok-interp", text: "$HOME" }, { class: "", text: " " }, { class: "tok-comment", text: "# x" }]]
expect Highlight.lines("diff", ["+a", "-b"]) == [[{ class: "tok-added", text: "+a" }], [{ class: "tok-removed", text: "-b" }]]

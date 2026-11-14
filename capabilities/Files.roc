## `files.v1`: the files of the directory a session works in, or a workspace
## is: a directory's entries and a file's contents, each a snapshot topic a
## client follows while it shows them (docs/protocol.md). Only reads.
Files := [].{
	Kind : [File, Directory, Symlink]

	## `size` in bytes, `modified` a time such as 2026-01-01T09:00:00.000Z.
	Entry : { name : Str, kind : Kind, size : U64, modified : Str }

	## The one event of a `tree/<context>/<path>` topic: the entries of the
	## directory at `path`, relative to the workspace's own (`.`). `Unknown`
	## until the provider has read it, or when the context has no workspace;
	## `Unreadable` with why, such as when there is no such directory.
	Tree : { path : Str, listing : [Listed(List(Entry)), Unknown, Unreadable(Str)] }

	## The one event of a `file/<context>/<path>` topic: a text file's text,
	## its first `text_limit` bytes at most and `truncated` if it has more, or
	## that it is binary, or too large for the provider to send.
	Contents : {
		path : Str,
		read : [Text({ text : Str, truncated : Bool, size : U64, modified : Str }), Binary({ size : U64, modified : Str }), TooLarge, Unknown, Unreadable(Str)],
	}

	text_limit : U64
	text_limit = 262_144

	## A file's text, cut to its first `text_limit` bytes at most, before a
	## character that would not fit.
	capped : Str -> { text : Str, truncated : Bool }
	capped = |whole| {
		bytes = whole.to_utf8()
		if bytes.len() <= Files.text_limit {
			{ text: whole, truncated: Bool.False }
		} else {
			{ text: Str.from_utf8(bytes.take_first(starting(bytes, Files.text_limit))) ?? "", truncated: Bool.True }
		}
	}
}

## Where the character that `at` is in starts: before UTF-8's continuation
## bytes, 0b10xxxxxx.
starting : List(U8), U64 -> U64
starting = |bytes, at|
	match bytes.get(at) {
		Ok(byte) if byte >= 0x80 and byte < 0xC0 and at > 0 => starting(bytes, at - 1)
		_ => at
	}

expect Files.capped("short") == { text: "short", truncated: Bool.False }

expect {
	# Each "é" is 2 bytes, so the limit falls inside one.
	capped = Files.capped("a${Str.repeat("é", Files.text_limit.to_u64() // 2)}")
	capped.truncated and capped.text.count_utf8_bytes() == Files.text_limit - 1 and Str.from_utf8(capped.text.to_utf8()).is_ok()
}

expect {
	contents : Files.Contents
	contents = { path: "README.md", read: Text({ text: "Hi", truncated: Bool.False, size: 2, modified: "2026-01-01T09:00:00.000Z" }) }
	Json.to_str(contents) == "{\"path\":\"README.md\",\"read\":{\"Text\":{\"modified\":\"2026-01-01T09:00:00.000Z\",\"size\":2,\"text\":\"Hi\",\"truncated\":false}}}"
}

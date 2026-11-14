import cap.Files
import Paseo

## A directory's files.v1 from Paseo: `file_explorer_request`s on its
## WebSocket, listing a directory or reading a file of it, alike in Paseo 0.9
## and 0.15, and their answers read into files.v1's types. Only reads.
PaseoFiles := [].{

	## The largest file Paseo is asked to send, as much as its own editor
	## opens; it refuses a larger one, which is `TooLarge`.
	read_limit : U64
	read_limit = 1_048_576

	## How long a listing or a file is kept before it is fetched again, while
	## a poll watches it.
	lifetime_ms : I64
	lifetime_ms = 10_000

	## Paseo's kind is "file" or "directory", following links.
	Entry : { name : Str, kind : Str, size : U64, modified_at : Str }

	## Paseo's kind is "text", "image" or "binary".
	File : { kind : Str, content : Try(Str, [Missing]), size : U64, modified_at : Str }

	tree_request : Str, Str, Str -> Str
	tree_request = |directory, path, request_id| Json.to_str({ type: "session", message: { type: "file_explorer_request", cwd: directory, path, mode: "list", requestId: request_id } })

	contents_request : Str, Str, Str -> Str
	contents_request = |directory, path, request_id| Json.to_str({ type: "session", message: { type: "file_explorer_request", cwd: directory, path, mode: "file", maxBytes: PaseoFiles.read_limit, requestId: request_id } })

	## The listing of `path` in a `file_explorer_response`, or why Paseo
	## couldn't list it.
	tree_answer : Str, Str, Str -> Try(Files.Tree, [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str)])
	tree_answer = |text, path, request_id| {
		answered : Try({ message : { payload : { directory : Try({ entries : List(Entry) }, [Null]), error : Try(Str, [Null]) } } }, _)
		answered = Json.parser_camel()(Paseo.write_answer(text, "file_explorer_response", request_id)?)
		payload = answered?.message.payload
		listing =
			match (payload.error, payload.directory) {
				(Ok(reason), _) => Unreadable(reason)
				(_, Ok({ entries })) => Listed(entries.map(|entry| { name: entry.name, kind: if (entry.kind == "directory") Directory else File, size: entry.size, modified: entry.modified_at }))
				_ => Unreadable("Paseo listed no directory")
			}
		Ok({ path, listing })
	}

	## The file at `path` in a `file_explorer_response`: an image counts as
	## binary, and a file over `read_limit` is too large.
	contents_answer : Str, Str, Str -> Try(Files.Contents, [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str)])
	contents_answer = |text, path, request_id| {
		answered : Try({ message : { payload : { file : Try(File, [Null]), error : Try(Str, [Null]) } } }, _)
		answered = Json.parser_camel()(Paseo.write_answer(text, "file_explorer_response", request_id)?)
		payload = answered?.message.payload
		read =
			match (payload.error, payload.file) {
				(Ok("File is too large to display"), _) => TooLarge
				(Ok(reason), _) => Unreadable(reason)
				(_, Ok(file)) if file.kind == "text" => {
					capped = Files.capped(file.content ?? "")
					Text({ text: capped.text, truncated: capped.truncated, size: file.size, modified: file.modified_at })
				}
				(_, Ok(file)) => Binary({ size: file.size, modified: file.modified_at })
				_ => Unreadable("Paseo sent no file")
			}
		Ok({ path, read })
	}
}

# Synthetic fixtures in Paseo's shapes.

explored : Str, Str -> Str
explored = |mode, fields| "{\"type\":\"session\",\"message\":{\"type\":\"file_explorer_response\",\"payload\":{\"cwd\":\"/work/app\",\"path\":\"src\",\"mode\":\"${mode}\",\"requestId\":\"x1\",${fields}}}}"

expect PaseoFiles.tree_request("/work/app", "src", "x1") == "{\"message\":{\"cwd\":\"/work/app\",\"mode\":\"list\",\"path\":\"src\",\"requestId\":\"x1\",\"type\":\"file_explorer_request\"},\"type\":\"session\"}"
expect PaseoFiles.contents_request("/work/app", "a.roc", "x1") == "{\"message\":{\"cwd\":\"/work/app\",\"maxBytes\":1048576,\"mode\":\"file\",\"path\":\"a.roc\",\"requestId\":\"x1\",\"type\":\"file_explorer_request\"},\"type\":\"session\"}"

expect {
	entries = "[{\"name\":\"Login.roc\",\"path\":\"src/Login.roc\",\"kind\":\"file\",\"size\":120,\"modifiedAt\":\"2026-01-01T00:00:00.000Z\"},{\"name\":\"views\",\"path\":\"src/views\",\"kind\":\"directory\",\"size\":4096,\"modifiedAt\":\"2026-01-02T00:00:00.000Z\"}]"
	PaseoFiles.tree_answer(explored("list", "\"directory\":{\"path\":\"src\",\"entries\":${entries}},\"file\":null,\"error\":null"), "src", "x1")
		== Ok({ path: "src", listing: Listed([{ name: "Login.roc", kind: File, size: 120, modified: "2026-01-01T00:00:00.000Z" }, { name: "views", kind: Directory, size: 4096, modified: "2026-01-02T00:00:00.000Z" }]) })
		and PaseoFiles.tree_answer(explored("list", "\"directory\":null,\"file\":null,\"error\":\"Requested path is not a directory\""), "src", "x1") == Ok({ path: "src", listing: Unreadable("Requested path is not a directory") })
		and PaseoFiles.tree_answer(explored("list", "\"directory\":null,\"file\":null,\"error\":null"), "src", "x2").map_ok(|_| {}) == Err(OtherMessage)
}

expect {
	file = |fields| explored("file", "\"directory\":null,\"file\":{\"path\":\"src/a\",\"size\":5,\"modifiedAt\":\"2026-01-01T00:00:00.000Z\",\"revision\":\"1:2:5:3\",${fields}},\"error\":null")
	read = |text| PaseoFiles.contents_answer(text, "src/a", "x1").map_ok(|contents| contents.read)
	read(file("\"kind\":\"text\",\"encoding\":\"utf-8\",\"content\":\"hello\",\"mimeType\":\"text/plain\"")) == Ok(Text({ text: "hello", truncated: Bool.False, size: 5, modified: "2026-01-01T00:00:00.000Z" }))
		and read(file("\"kind\":\"binary\",\"encoding\":\"none\",\"mimeType\":\"application/octet-stream\"")) == Ok(Binary({ size: 5, modified: "2026-01-01T00:00:00.000Z" }))
		and read(file("\"kind\":\"image\",\"encoding\":\"base64\",\"content\":\"aGk=\",\"mimeType\":\"image/png\"")) == Ok(Binary({ size: 5, modified: "2026-01-01T00:00:00.000Z" }))
		and read(explored("file", "\"directory\":null,\"file\":null,\"error\":\"File is too large to display\"")) == Ok(TooLarge)
		and read(explored("file", "\"directory\":null,\"file\":null,\"error\":\"ENOENT: no such file\"")) == Ok(Unreadable("ENOENT: no such file"))
}

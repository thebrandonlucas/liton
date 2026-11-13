## `workspace.git.v1`: the git state of the directory a session works in, or a
## workspace is: its branch and how far it is from its base and upstream, the
## files that changed (uncommitted, against the base, or in one commit) and the
## branch's commits.
## A client follows a scope's changes and the hunks of the file it shows as
## topics (docs/protocol.md).
WorkspaceGit := [].{

	## `id` is the directory, `name` the repository's folder.
	Workspace : { id : Str, provider : Str, name : Str, directory : Str, repository_root : Str, kind : [Checkout, Worktree, NotGit] }

	## `ahead` and `behind` count commits against the base, `upstream`'s against
	## the branch's upstream.
	Status : { branch : [Branch(Str), Detached], base : [Base(Str), NoBase], dirty : Bool, ahead : U32, behind : U32, upstream : [Upstream({ ahead : U32, behind : U32 }), NoUpstream] }

	Scope : [Uncommitted, AgainstBase, Commit(Str)]

	## A rename's `from` is "" when the provider doesn't say.
	Change : [Added, Modified, Deleted, Renamed({ from : Str })]

	File : { path : Str, change : Change, additions : U32, deletions : U32, body : [Text, Binary, TooLarge] }

	LineKind : [Added, Removed, Context]

	## An added line's `old_line` is 0, as is a removed line's `new_line`.
	Line : { kind : LineKind, text : Str, old_line : U32, new_line : U32 }

	Hunk : { old_start : U32, old_count : U32, new_start : U32, new_count : U32, lines : List(Line) }

	FileDiff : { file : File, hunks : List(Hunk) }

	## `fingerprint` changes whenever the files or their hunks do.
	Changes : { scope : Scope, fingerprint : Str, files : List(File) }

	Commit : { sha : Str, short_sha : Str, subject : Str, author : Str, date : Str, pushed : Bool, on_base : Bool, files : List(File) }

	## What a client asks of a workspace: a scope, and a file of it whose hunks
	## it shows.
	Asked : { scope : Scope, file : [Selected(Str), NoFile] }

	## What a provider has of a workspace, to answer what is `Asked` from.
	## `diff` holds the scope's files, for a commit with only the selected
	## file's hunks, and `fingerprint` is theirs (see `fingerprint`), kept
	## with them so a poll doesn't hash them again.
	Found : { workspace : Workspace, status : [Status(Status), NoStatus], fingerprint : Str, diff : List(FileDiff), commits : List(Commit) }

	## The one event of a `changes/<context>/<scope>` topic: the workspace, its
	## status, the scope's changed files and the branch's commits.
	Snapshot : { workspace : [Known(Workspace), Unknown], status : [Status(Status), NoStatus], changes : Changes, commits : List(Commit) }

	## The one event of a `file/<context>/<scope>/<path>` topic: the file's
	## hunks, none when the scope has no such file or the workspace can't be
	## read.
	FileHunks : { path : Str, hunks : List(Hunk) }

	## A workspace's snapshot of `scope`, or the one of a workspace that can't
	## be read.
	snapshot : Scope, Try(Found, [Unknown]) -> Snapshot
	snapshot = |scope, found|
		match found {
			Ok({ workspace, status, fingerprint, diff, commits }) => { workspace: Known(workspace), status, changes: { scope, fingerprint, files: diff.map(|shown| shown.file) }, commits }
			Err(Unknown) => { workspace: Unknown, status: NoStatus, changes: { scope, fingerprint: WorkspaceGit.fingerprint(scope, []), files: [] }, commits: [] }
		}

	file_hunks : Str, Try(Found, [Unknown]) -> FileHunks
	file_hunks = |path, found| { path, hunks: found.map_ok(|{ diff, .. }| diff.find_first(|shown| shown.file.path == path).map_ok(|shown| shown.hunks) ?? []) ?? [] }

	## A hunk of `lines`, numbered from the hunk's starts.
	hunk : { old_start : U32, old_count : U32, new_start : U32, new_count : U32 }, List({ kind : LineKind, text : Str }) -> Hunk
	hunk = |{ old_start, old_count, new_start, new_count }, lines| {
		numbered = lines.fold(
			{ old_line: old_start, new_line: new_start, lines: [] },
			|so_far, { kind, text }|
				match kind {
					Added => { ..so_far, new_line: so_far.new_line + 1, lines: so_far.lines.append({ kind, text, old_line: 0, new_line: so_far.new_line }) }
					Removed => { ..so_far, old_line: so_far.old_line + 1, lines: so_far.lines.append({ kind, text, old_line: so_far.old_line, new_line: 0 }) }
					Context => { old_line: so_far.old_line + 1, new_line: so_far.new_line + 1, lines: so_far.lines.append({ kind, text, old_line: so_far.old_line, new_line: so_far.new_line }) }
				},
		)
		{ old_start, old_count, new_start, new_count, lines: numbered.lines }
	}

	## A 64-bit FNV-1a hash of the scope and its files with their hunks. A
	## commit never changes, so its files alone tell it.
	fingerprint : Scope, List(FileDiff) -> Str
	fingerprint = |scope, diff| {
		hashed = match scope {
			Commit(_) => Json.to_str((scope, diff.map(|shown| shown.file)))
			_ => Json.to_str((scope, diff))
		}
		hashed.to_utf8().fold(14695981039346656037.U64, |hash, byte| hash.bitwise_xor(byte.to_u64()).times_wrap(1099511628211)).to_str()
	}
}

readme : WorkspaceGit.FileDiff
readme = {
	file: { path: "README.md", change: Modified, additions: 1, deletions: 1, body: Text },
	hunks: [WorkspaceGit.hunk({ old_start: 3, old_count: 3, new_start: 3, new_count: 3 }, [{ kind: Context, text: "a" }, { kind: Removed, text: "b" }, { kind: Added, text: "c" }, { kind: Context, text: "d" }])],
}

expect readme.hunks.map(|shown| shown.lines.map(|line| (line.old_line, line.new_line))) == [[(3, 3), (4, 0), (0, 4), (5, 5)]]

expect {
	edited = { ..readme, hunks: readme.hunks.map(|shown| { ..shown, lines: shown.lines.map(|line| { ..line, text: "e" }) }) }
	WorkspaceGit.fingerprint(Uncommitted, [readme]) != WorkspaceGit.fingerprint(Uncommitted, [edited]) and WorkspaceGit.fingerprint(Uncommitted, [readme]) != WorkspaceGit.fingerprint(AgainstBase, [readme])
}

expect WorkspaceGit.fingerprint(Commit("c1"), [readme]) == WorkspaceGit.fingerprint(Commit("c1"), [{ ..readme, hunks: [] }])

expect {
	workspace = { id: "/work", provider: "mock", name: "work", directory: "/work", repository_root: "/work", kind: Checkout }
	found = { workspace, status: NoStatus, fingerprint: "", diff: [readme], commits: [] }
	WorkspaceGit.file_hunks("README.md", Ok(found)).hunks == readme.hunks and WorkspaceGit.file_hunks("a.roc", Ok(found)).hunks == [] and WorkspaceGit.file_hunks("README.md", Err(Unknown)).hunks == []
}

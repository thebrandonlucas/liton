## `workspace.git.v1`: the git state of the directory a session works in, or a
## workspace is: its branch and how far it is from its base and upstream, the
## files that changed (uncommitted, against the base, or in one commit) and the
## branch's commits.
## The UI polls it with the fingerprint of the changes it has, so unchanged
## changes don't travel again, and gets the hunks of the one file it shows.
import Context

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

	## `known` is the fingerprint of the changes the client has ("" for none).
	## A `Poll` is of a session's workspace, a `ContextPoll` of a session's or a
	## workspace's.
	Poll : { session_id : Str, scope : Scope, known : Str, file : [Selected(Str), NoFile] }

	ContextPoll : { context : Context.Id, scope : Scope, known : Str, file : [Selected(Str), NoFile] }

	Polled : {
		workspace : [Known(Workspace), Unknown],
		status : [Status(Status), NoStatus],
		changes : [Unchanged, Changed(Changes)],
		file : [Hunks({ path : Str, hunks : List(Hunk) }), NoFile],
		commits : List(Commit),
	}

	## What a provider has of a session's workspace, to answer a poll from.
	## `diff` holds the poll's scope's files, for a commit with only the
	## selected file's hunks, and `fingerprint` is theirs (see `fingerprint`),
	## kept with them so a poll doesn't hash them again.
	Found : { workspace : Workspace, status : [Status(Status), NoStatus], fingerprint : Str, diff : List(FileDiff), commits : List(Commit) }

	polled : Poll, Found -> Polled
	polled = |poll, { workspace, status, fingerprint, diff, commits }| {
		file =
			match poll.file {
				Selected(path) => diff.find_first(|shown| shown.file.path == path).map_ok(|shown| Hunks({ path, hunks: shown.hunks })) ?? NoFile
				NoFile => NoFile
			}
		{ workspace: Known(workspace), status, changes: changes(poll, fingerprint, diff), file, commits }
	}

	## The answer when the workspace can't be read, such as when its provider
	## can't be reached.
	unknown : Poll -> Polled
	unknown = |poll| { workspace: Unknown, status: NoStatus, changes: changes(poll, WorkspaceGit.fingerprint(poll.scope, []), []), file: NoFile, commits: [] }

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

changes : WorkspaceGit.Poll, Str, List(WorkspaceGit.FileDiff) -> [Unchanged, Changed(WorkspaceGit.Changes)]
changes = |poll, fingerprint, diff|
	if (fingerprint == poll.known) Unchanged else Changed({ scope: poll.scope, fingerprint, files: diff.map(|shown| shown.file) })

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
	poll = { session_id: "s1", scope: Uncommitted, known: "", file: Selected("README.md") }
	found = { workspace, status: NoStatus, fingerprint: WorkspaceGit.fingerprint(Uncommitted, [readme]), diff: [readme], commits: [] }
	first = WorkspaceGit.polled(poll, found)
	again = match first.changes {
		Changed(shown) => WorkspaceGit.polled({ ..poll, known: shown.fingerprint, file: NoFile }, found)
		Unchanged => first
	}
	first.file == Hunks({ path: "README.md", hunks: readme.hunks }) and again.changes == Unchanged and again.file == NoFile
}

expect {
	decoded : Try(WorkspaceGit.ContextPoll, _)
	decoded = Json.parse("{\"context\":{\"Workspace\":\"w1\"},\"file\":\"NoFile\",\"known\":\"\",\"scope\":\"Uncommitted\"}")
	session : Try(WorkspaceGit.ContextPoll, _)
	session = Json.parse("{\"file\":\"NoFile\",\"known\":\"\",\"scope\":\"Uncommitted\",\"session_id\":\"s1\"}")
	decoded == Ok({ context: Workspace("w1"), scope: Uncommitted, known: "", file: NoFile }) and session.is_err()
}

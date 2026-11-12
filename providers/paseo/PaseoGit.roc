import cap.WorkspaceGit
import Paseo

## A session's workspace.git.v1 from Paseo: requests for a directory's
## checkout status, diff and commits on Paseo's WebSocket, and their answers
## read into workspace.git.v1's types. Only reads: liton calls none of
## Paseo's git writes (commit, discard, merge, push...).
PaseoGit := [].{
	Failure : { code : Str, message : Str }

	## Paseo's checkout status: not a repository, a checkout or a worktree.
	## `ahead_behind` counts against the base.
	Checkout : {
		request_id : Str,
		is_git : Bool,
		is_paseo_owned_worktree : Bool,
		repo_root : Try(Str, [Null]),
		main_repo_root : Try(Try(Str, [Null]), [Missing]),
		current_branch : Try(Str, [Null]),
		is_dirty : Try(Bool, [Null]),
		base_ref : Try(Str, [Null]),
		upstream_ref : Try(Try(Str, [Null]), [Missing]),
		ahead_behind : Try({ ahead : U32, behind : U32 }, [Null]),
		ahead_of_origin : Try(U32, [Null]),
		behind_of_origin : Try(U32, [Null]),
		error : Try(Failure, [Null]),
	}

	DiffLine : { type : Str, content : Str }

	DiffHunk : { old_start : U32, old_count : U32, new_start : U32, new_count : U32, lines : List(DiffLine) }

	DiffFile : { path : Str, old_path : Try(Str, [Missing]), is_new : Bool, is_deleted : Bool, additions : U32, deletions : U32, status : Try(Str, [Missing]), hunks : List(DiffHunk) }

	CommitFile : { path : Str, additions : U32, deletions : U32, status : Try(Str, [Missing]) }

	Commit : { sha : Str, short_sha : Str, subject : Str, author_name : Str, author_date : Str, is_on_remote : Bool, is_on_base : Try(Bool, [Missing]), files : List(CommitFile) }

	## How old a diff gets before it is fetched again, since a file edited in
	## a tree already dirty leaves the status as it was. Paseo computes the
	## whole diff for each request.
	diff_lifetime_ms : I64
	diff_lifetime_ms = 15_000

	## Whether to fetch a directory's diff or commits again, now that its
	## status is `status`, given the status they were fetched at, and when (ms
	## since the epoch): the diff when the status changed or the diff is
	## `diff_lifetime_ms` old, the commits when the branch or how far it is
	## ahead changed. Either when nothing is cached.
	refresh : [Diff, Commits], Try({ status : WorkspaceGit.Status, fetched_at : I64 }, [NothingCached]), WorkspaceGit.Status, I64 -> Bool
	refresh = |what, cached, status, now|
		match (what, cached) {
			(_, Err(NothingCached)) => Bool.True
			(Diff, Ok(known)) => known.status != status or now - known.fetched_at >= PaseoGit.diff_lifetime_ms
			(Commits, Ok(known)) => known.status.branch != status.branch or known.status.ahead != status.ahead
		}

	status_request : Str, Str -> Str
	status_request = |directory, request_id| Json.to_str({ type: "session", message: { type: "checkout_status_request", cwd: directory, requestId: request_id } })

	diff_request : Str, WorkspaceGit.Scope, Str -> Str
	diff_request = |directory, scope, request_id|
		Json.to_str({ type: "session", message: { type: "checkout.diff.get.request", cwd: directory, compare: { mode: if (scope == Uncommitted) "uncommitted" else "base" }, requestId: request_id } })

	commits_request : Str, Str -> Str
	commits_request = |directory, request_id| Json.to_str({ type: "session", message: { type: "checkout.commits.list.request", cwd: directory, requestId: request_id } })

	commit_file_request : Str, Str, Str, Str -> Str
	commit_file_request = |directory, sha, path, request_id| Json.to_str({ type: "session", message: { type: "checkout.commits.file_diff.request", cwd: directory, sha, path, requestId: request_id } })

	## The workspace and status in a `checkout_status_response` answering
	## `request_id`; a directory outside git has no status.
	status_answer : Str, Str, Str -> Try({ workspace : WorkspaceGit.Workspace, status : [Status(WorkspaceGit.Status), NoStatus] }, [OtherMessage, GitFailed(Str), InvalidJson(Str), MissingRequiredField(Str)])
	status_answer = |text, directory, request_id| {
		answered : Try({ message : { payload : Checkout } }, _)
		answered = Json.parser_camel()(Paseo.answer_to(text, "checkout_status_response", request_id)?)
		checkout = answered?.message.payload
		repository_root = checkout.repo_root ?? directory
		workspace = { id: directory, provider: "paseo", name: repository_root.split_on("/").last() ?? repository_root, directory, repository_root, kind: Checkout }
		if !checkout.is_git {
			Ok({ workspace: { ..workspace, kind: NotGit }, status: NoStatus })
		} else {
			match checkout.error {
				Ok({ message, .. }) => Err(GitFailed(message))
				Err(Null) => {
					worktree = checkout.is_paseo_owned_worktree or (checkout.main_repo_root.map_ok(|main| main.map_ok(|root| root != repository_root) ?? Bool.False) ?? Bool.False)
					status = {
						branch: checkout.current_branch.map_ok(|name| Branch(name)) ?? Detached,
						base: checkout.base_ref.map_ok(|name| Base(name)) ?? NoBase,
						dirty: checkout.is_dirty ?? Bool.False,
						ahead: checkout.ahead_behind.map_ok(|counts| counts.ahead) ?? 0,
						behind: checkout.ahead_behind.map_ok(|counts| counts.behind) ?? 0,
						upstream: if (checkout.upstream_ref.map_ok(|upstream| upstream.is_ok()) ?? Bool.False) Upstream({ ahead: checkout.ahead_of_origin ?? 0, behind: checkout.behind_of_origin ?? 0 }) else NoUpstream,
					}
					Ok({ workspace: { ..workspace, kind: if (worktree) Worktree else Checkout }, status: Status(status) })
				}
			}
		}
	}

	## The files and hunks of a `checkout.diff.get.response`.
	diff_answer : Str, Str -> Try(List(WorkspaceGit.FileDiff), [OtherMessage, GitFailed(Str), InvalidJson(Str), MissingRequiredField(Str)])
	diff_answer = |text, request_id| {
		answered : Try({ message : { payload : { files : List(DiffFile), error : Try(Failure, [Null]) } } }, _)
		answered = Json.parser_camel()(Paseo.answer_to(text, "checkout.diff.get.response", request_id)?)
		payload = answered?.message.payload
		match payload.error {
			Ok({ message, .. }) => Err(GitFailed(message))
			Err(Null) => Ok(payload.files.map(file_diff))
		}
	}

	commits_answer : Str, Str -> Try(List(WorkspaceGit.Commit), [OtherMessage, GitFailed(Str), InvalidJson(Str), MissingRequiredField(Str)])
	commits_answer = |text, request_id| {
		answered : Try({ message : { payload : { commits : List(Commit), error : Try(Failure, [Null]) } } }, _)
		answered = Json.parser_camel()(Paseo.answer_to(text, "checkout.commits.list.response", request_id)?)
		payload = answered?.message.payload
		match payload.error {
			Ok({ message, .. }) => Err(GitFailed(message))
			Err(Null) =>
				Ok(
					payload.commits.map(
						|commit| {
							files = commit.files.map(|file| { path: file.path, change: commit_change(file.status ?? "modified"), additions: file.additions, deletions: file.deletions, body: Text })
							{ sha: commit.sha, short_sha: commit.short_sha, subject: commit.subject, author: commit.author_name, date: commit.author_date, pushed: commit.is_on_remote, on_base: commit.is_on_base ?? Bool.False, files }
						},
					),
				)
		}
	}

	## The hunks of one file in one commit; none when Paseo has no text diff.
	commit_file_answer : Str, Str -> Try(List(WorkspaceGit.Hunk), [OtherMessage, GitFailed(Str), InvalidJson(Str), MissingRequiredField(Str)])
	commit_file_answer = |text, request_id| {
		answered : Try({ message : { payload : { file : Try(DiffFile, [Null]), error : Try(Failure, [Null]) } } }, _)
		answered = Json.parser_camel()(Paseo.answer_to(text, "checkout.commits.file_diff.response", request_id)?)
		payload = answered?.message.payload
		match payload.error {
			Ok({ message, .. }) => Err(GitFailed(message))
			Err(Null) => Ok(payload.file.map_ok(|file| file_diff(file).hunks) ?? [])
		}
	}
}

## Paseo's diff of a file, without its hunks' header lines.
file_diff : PaseoGit.DiffFile -> WorkspaceGit.FileDiff
file_diff = |file| {
	change =
		if file.is_new {
			Added
		} else if file.is_deleted {
			Deleted
		} else {
			match file.old_path {
				Ok(from) if from != file.path => Renamed({ from: from })
				_ => Modified
			}
		}
	body =
		match file.status {
			Ok("too_large") => TooLarge
			Ok("binary") => Binary
			_ => Text
		}
	hunks = file.hunks.map(
		|shown| {
			lines = shown.lines.keep_oks(
				|line|
					match line.type {
						"add" => Ok({ kind: Added, text: line.content })
						"remove" => Ok({ kind: Removed, text: line.content })
						"context" => Ok({ kind: Context, text: line.content })
						_ => Err(Header)
					},
			)
			WorkspaceGit.hunk({ old_start: shown.old_start, old_count: shown.old_count, new_start: shown.new_start, new_count: shown.new_count }, lines)
		},
	)
	{ file: { path: file.path, change, additions: file.additions, deletions: file.deletions, body }, hunks }
}

commit_change : Str -> WorkspaceGit.Change
commit_change = |status|
	match status {
		"added" => Added
		"deleted" => Deleted
		"renamed" => Renamed({ from: "" })
		_ => Modified
	}

# Synthetic fixtures in Paseo's shapes.

session : Str, Str -> Str
session = |type, payload| "{\"type\":\"session\",\"message\":{\"type\":\"${type}\",\"payload\":${payload}}}"

checkout : Str -> Str
checkout = |fields| session("checkout_status_response", "{\"cwd\":\"/work/app\",\"requestId\":\"g1\",\"error\":null,${fields}}")

git_checkout : Str
git_checkout = checkout("\"isGit\":true,\"isPaseoOwnedWorktree\":false,\"repoRoot\":\"/work/app\",\"mainRepoRoot\":null,\"currentBranch\":\"fix-login\",\"isDirty\":true,\"baseRef\":\"main\",\"aheadBehind\":{\"ahead\":2,\"behind\":1},\"aheadOfOrigin\":1,\"behindOfOrigin\":0,\"hasRemote\":true,\"remoteUrl\":\"https://example.com/app.git\",\"upstreamRef\":\"refs/remotes/origin/fix-login\"")

status : WorkspaceGit.Status
status = { branch: Branch("fix-login"), base: Base("main"), dirty: Bool.True, ahead: 2, behind: 1, upstream: Upstream({ ahead: 1, behind: 0 }) }

expect PaseoGit.status_answer(git_checkout, "/work/app", "g1") == Ok({ workspace: { id: "/work/app", provider: "paseo", name: "app", directory: "/work/app", repository_root: "/work/app", kind: Checkout }, status: Status(status) })
expect PaseoGit.status_answer(git_checkout, "/work/app", "g2").map_ok(|_| {}) == Err(OtherMessage)
expect PaseoGit.status_answer(checkout("\"isGit\":false,\"isPaseoOwnedWorktree\":false,\"repoRoot\":null,\"currentBranch\":null,\"isDirty\":null,\"baseRef\":null,\"aheadBehind\":null,\"aheadOfOrigin\":null,\"behindOfOrigin\":null,\"hasRemote\":false,\"remoteUrl\":null"), "/work/app", "g1").map_ok(|answered| (answered.workspace.kind, answered.status)) == Ok((NotGit, NoStatus))

expect {
	worktree = checkout("\"isGit\":true,\"isPaseoOwnedWorktree\":true,\"repoRoot\":\"/work/app-wt\",\"mainRepoRoot\":\"/work/app\",\"currentBranch\":null,\"isDirty\":false,\"baseRef\":\"main\",\"aheadBehind\":null,\"aheadOfOrigin\":null,\"behindOfOrigin\":null,\"hasRemote\":false,\"remoteUrl\":null")
	PaseoGit.status_answer(worktree, "/work/app-wt", "g1").map_ok(|answered| (answered.workspace.kind, answered.status)) == Ok((Worktree, Status({ branch: Detached, base: Base("main"), dirty: Bool.False, ahead: 0, behind: 0, upstream: NoUpstream })))
}

expect {
	files =
		\\[{"path":"src/Login.roc","isNew":false,"isDeleted":false,"additions":1,"deletions":1,"status":"ok","hunks":[{"oldStart":10,"oldCount":3,"newStart":10,"newCount":3,"lines":[
		\\{"type":"header","content":"@@ -10,3 +10,3 @@"},{"type":"context","content":"go = |user|","tokens":[{"text":"go","style":null}]},{"type":"remove","content":"  login"},{"type":"add","content":"  user.came_from"},{"type":"context","content":"end"}]}]},
		\\{"path":"logo.png","isNew":true,"isDeleted":false,"additions":0,"deletions":0,"status":"binary","hunks":[]},
		\\{"path":"src/New.roc","oldPath":"src/Old.roc","isNew":false,"isDeleted":false,"additions":0,"deletions":0,"hunks":[]}]
	answered = PaseoGit.diff_answer(session("checkout.diff.get.response", "{\"cwd\":\"/work/app\",\"requestId\":\"d1\",\"files\":${files},\"error\":null}"), "d1")
	login = { file: { path: "src/Login.roc", change: Modified, additions: 1, deletions: 1, body: Text }, hunks: [{ old_start: 10, old_count: 3, new_start: 10, new_count: 3, lines: [{ kind: Context, text: "go = |user|", old_line: 10, new_line: 10 }, { kind: Removed, text: "  login", old_line: 11, new_line: 0 }, { kind: Added, text: "  user.came_from", old_line: 0, new_line: 11 }, { kind: Context, text: "end", old_line: 12, new_line: 12 }] }] }
	answered == Ok([login, { file: { path: "logo.png", change: Added, additions: 0, deletions: 0, body: Binary }, hunks: [] }, { file: { path: "src/New.roc", change: Renamed({ from: "src/Old.roc" }), additions: 0, deletions: 0, body: Text }, hunks: [] }])
}

expect PaseoGit.diff_answer(session("checkout.diff.get.response", "{\"cwd\":\"/tmp\",\"requestId\":\"d1\",\"files\":[],\"error\":{\"code\":\"NOT_GIT_REPO\",\"message\":\"not a git repository\"}}"), "d1") == Err(GitFailed("not a git repository"))

expect {
	commits =
		\\[{"sha":"abc123def","shortSha":"abc123d","subject":"Redirect back after login","authorName":"Ada","authorDate":"2026-01-01T00:00:00Z","isOnRemote":false,"isOnBase":false,"files":[{"path":"src/Login.roc","additions":3,"deletions":1,"status":"modified"},{"path":"src/Gone.roc","additions":0,"deletions":9,"status":"deleted"}]}]
	PaseoGit.commits_answer(session("checkout.commits.list.response", "{\"cwd\":\"/work/app\",\"baseRef\":\"main\",\"commits\":${commits},\"error\":null,\"requestId\":\"c1\"}"), "c1")
		== Ok([{ sha: "abc123def", short_sha: "abc123d", subject: "Redirect back after login", author: "Ada", date: "2026-01-01T00:00:00Z", pushed: Bool.False, on_base: Bool.False, files: [{ path: "src/Login.roc", change: Modified, additions: 3, deletions: 1, body: Text }, { path: "src/Gone.roc", change: Deleted, additions: 0, deletions: 9, body: Text }] }])
}

expect PaseoGit.commit_file_answer(session("checkout.commits.file_diff.response", "{\"cwd\":\"/work/app\",\"sha\":\"abc\",\"path\":\"logo.png\",\"file\":null,\"error\":null,\"requestId\":\"f1\"}"), "f1") == Ok([])

expect PaseoGit.diff_request("/work/app", AgainstBase, "d1") == "{\"message\":{\"compare\":{\"mode\":\"base\"},\"cwd\":\"/work/app\",\"requestId\":\"d1\",\"type\":\"checkout.diff.get.request\"},\"type\":\"session\"}"

expect {
	cached = Ok({ status, fetched_at: 10_000 })
	both = |cached_now, status_now, now| (PaseoGit.refresh(Diff, cached_now, status_now, now), PaseoGit.refresh(Commits, cached_now, status_now, now))
	both(Err(NothingCached), status, 0) == (Bool.True, Bool.True)
		and both(cached, status, 24_000) == (Bool.False, Bool.False)
		and both(cached, status, 25_000) == (Bool.True, Bool.False)
		and both(cached, { ..status, dirty: Bool.False }, 12_000) == (Bool.True, Bool.False)
		and both(cached, { ..status, ahead: 3 }, 12_000) == (Bool.True, Bool.True)
		and both(cached, { ..status, branch: Detached }, 12_000) == (Bool.True, Bool.True)
}

## `review.v1`: a review of a context's code, as crit.md does it. Comments
## on lines of a file or a diff gather into threads, beside comments on the
## whole review, as drafts; `Send` turns the drafts into one message to the
## agent, a round, and the threads stay open until resolved. The daemon
## hosts it for every context, storing each one's review.
Review := [].{

	## Whose lines a thread is on: a file as it is now (`File`), or a scope's
	## diff, on its new side or, for removed lines, its old one.
	Scope : [File, Uncommitted, AgainstBase, Commit(Str)]

	## The side of a diff a thread's lines are on: the new file or the old.
	Side : [New, Old]

	## The lines a thread is on, numbered from 1, and their text, `quote`,
	## by which the daemon finds them again once the file changes.
	Anchor : { path : Str, scope : Scope, side : Side, start_line : U32, end_line : U32, quote : Str }

	## A draft, or sent in the round numbered.
	Comment : { id : Str, author : [Me, Agent], text : Str, state : [Draft, Sent(U32)] }

	## `outdated` once its lines are gone from the file.
	Thread : { id : Str, anchor : Anchor, outdated : Bool, resolved : Bool, comments : List(Comment) }

	## The one event of a `threads/<context>` topic. `round` counts the
	## reviews sent, `comments` are on the whole review, and `next` numbers
	## the next thread or comment added.
	Snapshot : { round : U32, next : U64, threads : List(Thread), comments : List(Comment) }

	## Where a comment goes: under a thread, on lines as a new thread, or on
	## the whole review.
	Place : [Thread(Str), Lines(Anchor), Overall]

	## Each names its context as topics do (`Context.to_str`). Only a draft
	## is edited or deleted, and a thread whose last comment is deleted goes
	## too. `Send` sends the drafts to the session `session_id` as one chat.v1
	## message (`message`), and answers once it took it.
	Request : [
		AddComment({ context : Str, place : Place, author : [Me, Agent], text : Str }),
		EditComment({ context : Str, comment_id : Str, text : Str }),
		DeleteComment({ context : Str, comment_id : Str }),
		Resolve({ context : Str, thread_id : Str }),
		Reopen({ context : Str, thread_id : Str }),
		Send({ context : Str, session_id : Str }),
	]

	## What a request answers: that the daemon took it, or the round `Send`
	## sent the drafts as.
	Response : [Accepted, Sent({ round : U32 })]

	## A context with no threads or comments, before its first round.
	empty : Snapshot
	empty = { round: 0, next: 1, threads: [], comments: [] }

	## The context a request is about.
	context : Request -> Str
	context = |request|
		match request {
			AddComment({ context: request_context, .. }) | EditComment({ context: request_context, .. }) | DeleteComment({ context: request_context, .. }) | Resolve({ context: request_context, .. }) | Reopen({ context: request_context, .. }) | Send({ context: request_context, .. }) => request_context
		}

	## A review as a request changes it, numbering what it adds by `next`,
	## so a client applying a request to the review it has shows what the
	## daemon will. An agent's comments are sent at once.
	applied : Snapshot, Request -> Try(Snapshot, [NotFound(Str), NotDraft, NothingToSend])
	applied = |review, request| {
		id = |prefix| "${prefix}${review.next.to_str()}"
		numbered = { ..review, next: review.next + 1 }
		comment = |author, text| { id: id("c"), author, text, state: if (author == Agent) Sent(review.round) else Draft }
		threaded = |thread_id, next, change|
			if (review.threads.any(|thread| thread.id == thread_id)) Ok({ ..review, next, threads: review.threads.map(|thread| if (thread.id == thread_id) change(thread) else thread) }) else Err(NotFound(thread_id))
		draft = |comment_id, change| {
			found = review.comments.concat(review.threads.join_map(|thread| thread.comments)).find_first(|shown| shown.id == comment_id)
			edit = |comments| comments.keep_oks(|shown| if (shown.id == comment_id) change(shown) else Ok(shown))
			match found {
				Ok({ state: Draft, .. }) => Ok({ ..review, comments: edit(review.comments), threads: review.threads.map(|thread| { ..thread, comments: edit(thread.comments) }).drop_if(|thread| thread.comments.is_empty()) })
				Ok(_) => Err(NotDraft)
				Err(_) => Err(NotFound(comment_id))
			}
		}
		match request {
			AddComment({ place: Overall, author, text, .. }) => Ok({ ..numbered, comments: review.comments.append(comment(author, text)) })
			AddComment({ place: Lines(anchor), author, text, .. }) => Ok({ ..numbered, next: review.next + 2, threads: review.threads.append({ id: "t${(review.next + 1).to_str()}", anchor, outdated: Bool.False, resolved: Bool.False, comments: [comment(author, text)] }) })
			AddComment({ place: Thread(thread_id), author, text, .. }) => threaded(thread_id, numbered.next, |thread| { ..thread, resolved: Bool.False, comments: thread.comments.append(comment(author, text)) })
			EditComment({ comment_id, text, .. }) => draft(comment_id, |shown| Ok({ ..shown, text }))
			DeleteComment({ comment_id, .. }) => draft(comment_id, |_| Err(Deleted))
			Resolve({ thread_id, .. }) => threaded(thread_id, review.next, |thread| { ..thread, resolved: Bool.True })
			Reopen({ thread_id, .. }) => threaded(thread_id, review.next, |thread| { ..thread, resolved: Bool.False })
			Send(_) if Review.drafts(review) == 0 => Err(NothingToSend)
			Send(_) => {
				round = review.round + 1
				sent = |comments| comments.map(|shown| if (shown.state == Draft) { ..shown, state: Sent(round) } else shown)
				Ok({ ..review, round, comments: sent(review.comments), threads: review.threads.map(|thread| { ..thread, comments: sent(thread.comments) }) })
			}
		}
	}

	## Why a request couldn't change a review.
	refusal : [NotFound(Str), NotDraft, NothingToSend] -> Str
	refusal = |problem|
		match problem {
			NotFound(id) => "no comment or thread ${id}"
			NotDraft => "only a draft can be changed"
			NothingToSend => "no drafts to send"
		}

	## How many comments are drafts.
	drafts : Snapshot -> U64
	drafts = |review| review.comments.concat(review.threads.join_map(|thread| thread.comments)).keep_if(|shown| shown.state == Draft).len()

	## The drafts as one message to the agent, in Markdown: each thread with
	## drafts as `path:start-end`, its lines quoted, what was said before and
	## the drafts, in the order of their files and lines, then the comments
	## on the whole review.
	message : Snapshot -> Str
	message = |review| {
		drafted = |comments| comments.keep_if(|shown| shown.state == Draft)
		said = |comments| Str.join_with(comments.map(|shown| shown.text.trim()), "\n\n")
		earlier = |thread| thread.comments.keep_if(|shown| shown.state != Draft).map(|shown| "> ${if (shown.author == Me) "Me" else "You"}: ${Str.join_with(shown.text.trim().split_on("\n"), "\n> ")}")
		with_drafts = review.threads.keep_if(|thread| !drafted(thread.comments).is_empty())
		paths = with_drafts.fold([], |so_far, thread| if (so_far.contains(thread.anchor.path)) so_far else so_far.append(thread.anchor.path))
		threads = paths.join_map(|path| with_drafts.keep_if(|thread| thread.anchor.path == path).sort_with(|a, b| if (a.anchor.start_line < b.anchor.start_line) Before else if (a.anchor.start_line > b.anchor.start_line) After else Same))
		section = |thread| {
			{ path, quote, .. } = thread.anchor
			fence = if (quote.contains("```")) "````" else "```"
			language = if (path.contains(".")) path.split_last(".").map_ok(|parts| parts.after) ?? "" else ""
			Str.join_with(["## ${Review.lines(thread.anchor)}${placed(thread.anchor)}", "${fence}${language}\n${quote}\n${fence}"].concat(earlier(thread)).append(said(drafted(thread.comments))), "\n\n")
		}
		overall = if (drafted(review.comments).is_empty()) [] else ["## Overall\n\n${said(drafted(review.comments))}"]
		count = Review.drafts(review)
		intro = "# Review, round ${(review.round + 1).to_str()}\n\n${count.to_str()} ${if (count == 1) "comment" else "comments"}. Each heading is a file and its lines, with the lines quoted; reply to each by its heading, then revise."
		Str.join_with(threads.map(section).concat(overall).prepend(intro), "\n\n")
	}

	## An anchor's lines as `path:start-end`, or `path:line`.
	lines : Anchor -> Str
	lines = |{ path, start_line, end_line, .. }| if (start_line == end_line) "${path}:${start_line.to_str()}" else "${path}:${start_line.to_str()}-${end_line.to_str()}"

	## The threads of a file's lines as `text` has them now, each moved to
	## where its quote is, the nearest if there are several, or outdated when
	## it is nowhere. A commit's and removed lines don't change.
	relocated : Snapshot, Str, Str -> Snapshot
	relocated = |review, path, text| {
		shown = text.split_on("\n")
		moved = |thread| {
			{ anchor, .. } = thread
			quoted = anchor.quote.split_on("\n")
			at = |start| start >= 1 and shown.sublist({ start: start.to_u64() - 1, len: quoted.len() }) == quoted
			nearest = shown.map_with_index(|_, index| index.to_u32_wrap() + 1).keep_if(at).fold(0, |best, start| if (best != 0 and distance(best, anchor.start_line) <= distance(start, anchor.start_line)) best else start)
			match (anchor.scope, anchor.side) {
				(Commit(_), _) | (_, Old) => thread
				_ if anchor.path != path => thread
				_ if at(anchor.start_line) => { ..thread, outdated: Bool.False }
				_ =>
					match nearest {
						0 => { ..thread, outdated: Bool.True }
						start => { ..thread, outdated: Bool.False, anchor: { ..anchor, start_line: start, end_line: start + anchor.end_line - anchor.start_line } }
					}
			}
		}
		{ ..review, threads: review.threads.map(moved) }
	}

	## Whether a view of `path` in `scope` shows a thread's lines: a commit's
	## its own, and a file and the diffs of the working tree the new side's
	## of any of them, each diff its own old side too.
	shows : Anchor, Str, Scope -> Bool
	shows = |anchor, path, scope|
		anchor.path
			== path
			and match (anchor.scope, scope) {
				(Commit(a), Commit(b)) => a == b
				(Commit(_), _) | (_, Commit(_)) => Bool.False
				_ => anchor.side == New or anchor.scope == scope
			}
}

## Where a thread's lines are, beside its heading, unless in the file as it is.
placed : Review.Anchor -> Str
placed = |anchor| {
	side = if (anchor.side == Old) ", removed lines" else ""
	match anchor.scope {
		File => ""
		Uncommitted => " (the uncommitted diff${side})"
		AgainstBase => " (the diff against the base${side})"
		Commit(sha) => {
			short = Str.from_utf8(sha.to_utf8().take_first(7)) ?? sha
			" (commit ${short}${side})"
		}
	}
}

distance : U32, U32 -> U32
distance = |a, b| if (a > b) a - b else b - a

on_two_lines : Review.Anchor
on_two_lines = { path: "src/Auth.roc", scope: File, side: New, start_line: 2, end_line: 3, quote: "b\nc" }

added : Review.Snapshot
added = Review.applied(Review.empty, AddComment({ context: "s1", place: Lines(on_two_lines), author: Me, text: "Why?" })) ?? Review.empty

# A comment on lines starts a thread; its id and the thread's follow `next`.
expect added.threads.map(|thread| (thread.id, thread.comments.map(|shown| (shown.id, shown.state)))) == [("t2", [("c1", Draft)])] and added.next == 3

# Only drafts change, and a thread whose last draft goes goes too.
expect {
	edited = Review.applied(added, EditComment({ context: "s1", comment_id: "c1", text: "How?" }))
	deleted = Review.applied(added, DeleteComment({ context: "s1", comment_id: "c1" }))
	sent = Review.applied(added, Send({ context: "s1", session_id: "s1" })) ?? added
	edited.map_ok(|shown| shown.threads.join_map(|thread| thread.comments).map(|shown_comment| shown_comment.text)) == Ok(["How?"]) and deleted.map_ok(|shown| shown.threads) == Ok([]) and Review.applied(sent, DeleteComment({ context: "s1", comment_id: "c1" })) == Err(NotDraft) and Review.applied(added, Resolve({ context: "s1", thread_id: "t9" })) == Err(NotFound("t9"))
}

# Send makes the drafts a round; with none, there is nothing to send.
expect {
	both = Review.applied(added, AddComment({ context: "s1", place: Overall, author: Me, text: "Nice." })) ?? added
	sent = Review.applied(both, Send({ context: "s1", session_id: "s1" })) ?? both
	sent.round == 1 and Review.drafts(sent) == 0 and Review.drafts(both) == 2 and Review.applied(sent, Send({ context: "s1", session_id: "s1" })) == Err(NothingToSend)
}

expect {
	replied = Review.applied(Review.applied(added, Send({ context: "s1", session_id: "s1" })) ?? added, AddComment({ context: "s1", place: Thread("t2"), author: Me, text: "And?" })) ?? added
	both = Review.applied(replied, AddComment({ context: "s1", place: Overall, author: Me, text: "Nice." })) ?? replied
	Review.message(both)
		==
		"# Review, round 2\n\n2 comments. Each heading is a file and its lines, with the lines quoted; reply to each by its heading, then revise.\n\n## src/Auth.roc:2-3\n\n```roc\nb\nc\n```\n\n> Me: Why?\n\nAnd?\n\n## Overall\n\nNice."
}

# A thread follows its quote, the nearest of several, and is outdated without it.
expect {
	at = |review| review.threads.map(|thread| (thread.anchor.start_line, thread.anchor.end_line, thread.outdated))
	at(Review.relocated(added, "src/Auth.roc", "a\nb\nc")) == [(2, 3, Bool.False)]
		and at(Review.relocated(added, "src/Auth.roc", "x\nb\nc\nx\nx\nx\nb\nc")) == [(2, 3, Bool.False)]
		and at(Review.relocated(added, "src/Auth.roc", "x\nx\nx\nx\na\nb\nc")) == [(6, 7, Bool.False)]
		and at(Review.relocated(added, "src/Auth.roc", "a\nb\nd")) == [(2, 3, Bool.True)]
		and at(Review.relocated(added, "README.md", "")) == [(2, 3, Bool.False)]
}

expect Review.shows(on_two_lines, "src/Auth.roc", Uncommitted) and !Review.shows(on_two_lines, "src/Auth.roc", Commit("c1")) and !Review.shows({ ..on_two_lines, side: Old, scope: Uncommitted }, "src/Auth.roc", File) and !Review.shows(on_two_lines, "a.roc", File)

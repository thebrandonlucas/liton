## `tickets.v1`: issues and tickets of the trackers providers reach, such as
## GitHub Issues and Linear, merged, each with its provider, its source and a
## URL back to it. Listed and filtered, read with their comments, commented
## on, moved between statuses and assigned; and linked to the sessions
## working on them, inferred from a session's branch unless a link set by
## hand says otherwise.
Tickets := [].{

	## What a status means, whatever its source calls it.
	Kind : [Open, Started, Done, Canceled]

	## A status tickets move between, by its id and name, and what it means.
	Status : { id : Str, name : Str, kind : Kind }

	## Someone tickets can be assigned to, by their id and name.
	Person : { id : Str, name : Str }

	## A repository's issues or a team's tickets: whom it knows the user as
	## (`me`), the people its tickets can be assigned to, and the statuses
	## they move between.
	Source : { id : Str, provider : Str, name : Str, url : Str, me : Try(Person, [Missing]), people : List(Person), statuses : List(Status) }

	## A ticket as listed. `key` is how its source names it, such as `#3` or
	## `LIN-12`; `waiting_on` the ids of the people it waits on, such as for
	## a review or an answer; `branch` the branch its source suggests for it;
	## `updated` when it last changed, as 2026-01-01T09:00:00.000Z.
	Summary : { id : Str, provider : Str, source : Str, key : Str, title : Str, url : Str, status : Status, assignees : List(Person), labels : List(Str), waiting_on : List(Str), branch : Try(Str, [Missing]), updated : Str }

	## `body` is Markdown.
	Comment : { id : Str, author : Person, body : Str, created : Str }

	## A ticket with its description, as Markdown, and its comments, oldest
	## first.
	Ticket : { summary : Summary, body : Str, comments : List(Comment) }

	## The one event of the `list` topic.
	Listing : { sources : List(Source), tickets : List(Summary) }

	## The ticket a session works for: linked by hand, or `inferred` from its
	## branch.
	Link : { session_id : Str, ticket_id : Str, inferred : Bool }

	## A link set by hand; with `ticket_id` "", a session unlinked by hand.
	Linked : { session_id : Str, ticket_id : Str }

	## Which tickets to list: of the sources named (all for none), of the
	## kinds of status named (any for none), assigned to anyone, the user
	## (`Me`), nobody or a person by id, with a label ("" for any), and whose
	## key or title has `text`, ignoring case.
	Filter : { sources : List(Str), kinds : List(Kind), assignee : [Anyone, Me, Nobody, Person(Str)], label : Str, text : Str }

	## `GetTicket` answers the ticket with its comments. `Comment`,
	## `SetStatus` (one of its source's `statuses`) and `SetAssignees` (of its
	## source's `people`, none to unassign) change a ticket where its source
	## keeps it. `Link` links a session to a ticket by hand, and `Unlink`
	## unlinks it by hand, either winning over the ticket its branch names.
	## Each answers `Accepted`.
	Request : [
		ListTickets(Filter),
		GetTicket({ ticket_id : Str }),
		Comment({ ticket_id : Str, body : Str }),
		SetStatus({ ticket_id : Str, status_id : Str }),
		SetAssignees({ ticket_id : Str, person_ids : List(Str) }),
		Link({ session_id : Str, ticket_id : Str }),
		Unlink({ session_id : Str }),
	]

	## What a request answers: a listing, one ticket, or that the provider
	## took it.
	Response : [Listed(Listing), Ticket(Ticket), Accepted]

	## Open and started tickets, of every source and assignee.
	open : Filter
	open = { sources: [], kinds: [Open, Started], assignee: Anyone, label: "", text: "" }

	## Whether a ticket of `listing` passes `filter`.
	matches : Filter, Listing, Summary -> Bool
	matches = |filter, listing, ticket| {
		me = listing.sources.find_first(|source| source.id == ticket.source).map_ok(|source| source.me.map_ok(|person| person.id) ?? "") ?? ""
		assigned = ticket.assignees.map(|person| person.id)
		text = filter.text.trim().with_ascii_lowercased()
		(filter.sources.is_empty() or filter.sources.contains(ticket.source))
			and (filter.kinds.is_empty() or filter.kinds.contains(ticket.status.kind))
			and match filter.assignee {
				Anyone => Bool.True
				Me => me != "" and assigned.contains(me)
				Nobody => assigned.is_empty()
				Person(id) => assigned.contains(id)
			}
			and (filter.label == "" or ticket.labels.contains(filter.label))
			and (text == "" or "${ticket.key} ${ticket.title}".with_ascii_lowercased().contains(text))
	}

	## The tickets of `listing` that pass `filter`, with all its sources.
	filtered : Listing, Filter -> Listing
	filtered = |listing, filter| { ..listing, tickets: listing.tickets.keep_if(|ticket| Tickets.matches(filter, listing, ticket)) }

	## The ticket a request is about, "" for none.
	ticket_of : Request -> Str
	ticket_of = |request|
		match request {
			GetTicket({ ticket_id }) | Comment({ ticket_id, .. }) | SetStatus({ ticket_id, .. }) | SetAssignees({ ticket_id, .. }) | Link({ ticket_id, .. }) => ticket_id
			_ => ""
		}

	## A ticket as a status or assignees request changes it, of the statuses
	## and people its source has.
	changed : Listing, Summary, Request -> Try(Summary, [NoSuchStatus(Str), NoSuchPerson(Str)])
	changed = |listing, ticket, request| {
		source = listing.sources.find_first(|known| known.id == ticket.source)
		match request {
			SetStatus({ status_id, .. }) =>
				match source.map_ok(|known| known.statuses).ok_or([]).find_first(|status| status.id == status_id) {
					Ok(status) => Ok({ ..ticket, status })
					Err(_) => Err(NoSuchStatus(status_id))
				}
			SetAssignees({ person_ids, .. }) => {
				people = source.map_ok(|known| known.people).ok_or([])
				match person_ids.find_first(|id| !people.any(|person| person.id == id)) {
					Ok(unknown) => Err(NoSuchPerson(unknown))
					Err(_) => Ok({ ..ticket, assignees: people.keep_if(|person| person_ids.contains(person.id)) })
				}
			}
			_ => Ok(ticket)
		}
	}

	## A ticket as a request changes it: its status or assignees, or a
	## comment by its source's `me` added as `comment_id` at `now`.
	applied : Listing, Ticket, Request, { comment_id : Str, now : Str } -> Try(Ticket, [NoSuchStatus(Str), NoSuchPerson(Str), EmptyComment])
	applied = |listing, ticket, request, { comment_id, now }|
		match request {
			Comment({ body, .. }) if body.trim() == "" => Err(EmptyComment)
			Comment({ body, .. }) => {
				me = listing.sources.find_first(|source| source.id == ticket.summary.source).map_ok(|source| source.me ?? Tickets.you) ?? Tickets.you
				Ok({ ..ticket, comments: ticket.comments.append({ id: comment_id, author: me, body: body.trim(), created: now }), summary: { ..ticket.summary, updated: now } })
			}
			_ => Tickets.changed(listing, ticket.summary, request).map_ok(|summary| { ..ticket, summary })
		}

	## Who comments when a source doesn't say who the user is.
	you : Person
	you = { id: "", name: "You" }

	## Why a request couldn't change a ticket.
	refusal : [NotFound(Str), NoSuchStatus(Str), NoSuchPerson(Str), EmptyComment] -> Str
	refusal = |problem|
		match problem {
			NotFound(id) => "no ticket ${id}"
			NoSuchStatus(id) => "no status ${id} for this ticket"
			NoSuchPerson(id) => "no one ${id} can be assigned this ticket"
			EmptyComment => "a comment needs some text"
		}

	## The ticket a branch names: the one its source suggests the branch
	## for, or else the first whose key is in it, such as `lin-12-fix-login`
	## for LIN-12, or `3-tickets`, `issue-3` and `gh-3` for #3.
	inferred : Str, List(Summary) -> Try(Summary, [NotFound])
	inferred = |branch, tickets| {
		parts = words(branch.split_last("/").map_ok(|split| split.after) ?? branch)
		names = |ticket|
			if ticket.key.starts_with("#") {
				number = ticket.key.drop_prefix("#")
				parts.first() == Ok(number) or ["issue", "issues", "gh"].any(|word| has_run(parts, [word, number]))
			} else {
				has_run(parts, words(ticket.key))
			}
		if (branch == "") Err(NotFound) else tickets.find_first(|ticket| ticket.branch == Ok(branch)).on_err(|_| tickets.find_first(names))
	}

	## Each session's link: the one set by hand, or else the ticket its branch
	## names; none when unlinked by hand or its branch names none.
	links : List({ id : Str, branch : Try(Str, [Missing]) }), List(Linked), List(Summary) -> List(Link)
	links = |sessions, by_hand, tickets|
		sessions.keep_oks(
			|session|
				match by_hand.find_first(|linked| linked.session_id == session.id) {
					Ok({ ticket_id: "", .. }) => Err(Unlinked)
					Ok({ ticket_id, .. }) => Ok({ session_id: session.id, ticket_id, inferred: Bool.False })
					Err(_) => Tickets.inferred(session.branch ?? "", tickets).map_ok(|ticket| { session_id: session.id, ticket_id: ticket.id, inferred: Bool.True }).map_err(|_| Unnamed)
				},
		)

	## The links set by hand as a Link or Unlink request leaves them.
	relinked : List(Linked), Request -> List(Linked)
	relinked = |by_hand, request|
		match request {
			Link({ session_id, ticket_id }) => by_hand.drop_if(|linked| linked.session_id == session_id).append({ session_id, ticket_id })
			Unlink({ session_id }) => by_hand.drop_if(|linked| linked.session_id == session_id).append({ session_id, ticket_id: "" })
			_ => by_hand
		}
}

## A text's runs of letters and digits, lowercased.
words : Str -> List(Str)
words = |text| {
	bytes = text.with_ascii_lowercased().to_utf8().map(|byte| if ((byte >= 'a' and byte <= 'z') or (byte >= '0' and byte <= '9')) byte else ' ')
	(Str.from_utf8(bytes) ?? "").split_on(" ").drop_if(|word| word == "")
}

## Whether `run` is in `parts`, in order and together.
has_run : List(Str), List(Str) -> Bool
has_run = |parts, run| !run.is_empty() and parts.map_with_index(|_, index| index).any(|start| parts.sublist({ start, len: run.len() }) == run)

open_status : Tickets.Status
open_status = { id: "open", name: "Open", kind: Open }

summary : Str, Str -> Tickets.Summary
summary = |id, key| { id, provider: "mock", source: "repo", key, title: "Fix the login", url: "https://example.com/${id}", status: open_status, assignees: [], labels: ["bug"], waiting_on: [], branch: Err(Missing), updated: "" }

listing : Tickets.Listing
listing = {
	sources: [{ id: "repo", provider: "mock", name: "liton", url: "", me: Ok({ id: "ada", name: "Ada" }), people: [{ id: "ada", name: "Ada" }, { id: "bo", name: "Bo" }], statuses: [open_status, { id: "closed", name: "Closed", kind: Done }] }],
	tickets: [{ ..summary("t3", "#3"), assignees: [{ id: "ada", name: "Ada" }] }, { ..summary("t4", "LIN-4"), title: "Write docs", labels: [], status: { id: "closed", name: "Closed", kind: Done } }],
}

expect {
	keys = |filter| Tickets.filtered(listing, filter).tickets.map(|ticket| ticket.key)
	keys(Tickets.open) == ["#3"] and keys({ ..Tickets.open, kinds: [] }) == ["#3", "LIN-4"] and keys({ ..Tickets.open, kinds: [], assignee: Nobody }) == ["LIN-4"] and keys({ ..Tickets.open, assignee: Me }) == ["#3"] and keys({ ..Tickets.open, kinds: [], text: "DOCS" }) == ["LIN-4"] and keys({ ..Tickets.open, label: "feature" }) == [] and keys({ ..Tickets.open, sources: ["other"] }) == []
}

expect {
	ticket = { summary: summary("t3", "#3"), body: "", comments: [] }
	commented = Tickets.applied(listing, ticket, Comment({ ticket_id: "t3", body: " Looks done. " }), { comment_id: "c1", now: "2026-01-01T09:00:00.000Z" })
	commented.map_ok(|shown| shown.comments.map(|comment| (comment.author.name, comment.body))) == Ok([("Ada", "Looks done.")])
		and Tickets.applied(listing, ticket, SetStatus({ ticket_id: "t3", status_id: "closed" }), { comment_id: "", now: "" }).map_ok(|shown| shown.summary.status.kind) == Ok(Done)
		and Tickets.applied(listing, ticket, SetStatus({ ticket_id: "t3", status_id: "gone" }), { comment_id: "", now: "" }).is_err()
		and Tickets.applied(listing, ticket, SetAssignees({ ticket_id: "t3", person_ids: ["bo"] }), { comment_id: "", now: "" }).map_ok(|shown| shown.summary.assignees.map(|person| person.name)) == Ok(["Bo"])
		and Tickets.applied(listing, ticket, SetAssignees({ ticket_id: "t3", person_ids: ["eve"] }), { comment_id: "", now: "" }) == Err(NoSuchPerson("eve"))
		and Tickets.applied(listing, ticket, Comment({ ticket_id: "t3", body: " " }), { comment_id: "", now: "" }) == Err(EmptyComment)
}

# A branch names a ticket by the branch its source suggests, or by its key.
expect {
	tickets = [summary("t3", "#3"), summary("t12", "LIN-12"), { ..summary("t9", "#9"), branch: Ok("ada/login") }]
	named = |branch| Tickets.inferred(branch, tickets).map_ok(|ticket| ticket.id)
	named("3-track-tickets") == Ok("t3") and named("ada/issue-3") == Ok("t3") and named("ada/lin-12-fix") == Ok("t12") and named("ada/login") == Ok("t9") and named("13-other") == Err(NotFound) and named("lin-123") == Err(NotFound) and named("main") == Err(NotFound) and named("") == Err(NotFound)
}

# A link set by hand wins over the branch's, and unlinked by hand there is none.
expect {
	tickets = [summary("t3", "#3"), summary("t4", "#4")]
	sessions = [{ id: "a", branch: Ok("3-x") }, { id: "b", branch: Ok("3-y") }, { id: "c", branch: Ok("main") }, { id: "d", branch: Err(Missing) }]
	by_hand = Tickets.relinked(Tickets.relinked([], Link({ session_id: "b", ticket_id: "t4" })), Unlink({ session_id: "a" }))
	Tickets.links(sessions, [], tickets) == [{ session_id: "a", ticket_id: "t3", inferred: Bool.True }, { session_id: "b", ticket_id: "t3", inferred: Bool.True }]
		and Tickets.links(sessions, by_hand, tickets) == [{ session_id: "b", ticket_id: "t4", inferred: Bool.False }]
		and Tickets.links(sessions, Tickets.relinked(by_hand, Link({ session_id: "a", ticket_id: "t3" })), tickets).len() == 2
}

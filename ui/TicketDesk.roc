## What Tickets panes show of tickets.v1 (docs/protocol.md, Tickets): the
## `list` topic's sources and tickets, the tickets opened with their
## comments, and each session's link, as polls last answered them, with the
## requests on their way applied, so a change shows at once.
import cap.Tickets

TicketDesk := [].{

	## A request sent as `serial`, shown until the daemon refuses it, or
	## until the poll numbered `accepted` answers, the first sent after the
	## daemon accepted it (0 while it waits).
	Asked : { serial : U64, request : Tickets.Request, accepted : U64 }

	## A pane's filter, and the ticket it shows, "" for its list.
	View : { pane : Str, filter : Tickets.Filter, ticket : Str }

	State : { listing : Tickets.Listing, opened : List(Tickets.Ticket), links : List(Tickets.Link), asked : List(Asked), views : List(View) }

	initial : State
	initial = { listing: { sources: [], tickets: [] }, opened: [], links: [], asked: [], views: [] }

	## A pane's view: its open and started tickets, until it changes them.
	view : State, Str -> View
	view = |desk, pane| desk.views.find_first(|shown| shown.pane == pane) ?? { pane, filter: Tickets.open, ticket: "" }

	with_view : State, Str, (View -> View) -> State
	with_view = |desk, pane, change| { ..desk, views: desk.views.drop_if(|shown| shown.pane == pane).append(change(TicketDesk.view(desk, pane))) }

	## The sources and tickets with the status and assignee changes on their
	## way applied.
	listing_shown : State -> Tickets.Listing
	listing_shown = |desk| {
		changed = |ticket| desk.asked.fold(ticket, |shown, asked| if (Tickets.ticket_of(asked.request) == shown.id) Tickets.changed(desk.listing, shown, asked.request) ?? shown else shown)
		{ ..desk.listing, tickets: desk.listing.tickets.map(changed) }
	}

	## The tickets of a pane's list: those its filter passes, the latest
	## changed first.
	listed : State, View -> List(Tickets.Summary)
	listed = |desk, { filter, .. }| {
		listing = TicketDesk.listing_shown(desk)
		listing.tickets.keep_if(|ticket| Tickets.matches(filter, listing, ticket)).sort_with(|a, b| bytes_order(b.updated.to_utf8(), a.updated.to_utf8()))
	}

	## A ticket as listed, with its body and comments once its topic
	## answers, and the comments on their way after its own, each numbered
	## `pending-<serial>`.
	ticket_shown : State, Str -> Try(Tickets.Ticket, [NotFound])
	ticket_shown = |desk, ticket_id| {
		listing = TicketDesk.listing_shown(desk)
		opened = desk.opened.find_first(|shown| shown.summary.id == ticket_id)
		summary = listing.tickets.find_first(|shown| shown.id == ticket_id).on_err(|_| opened.map_ok(|shown| shown.summary))?
		known = { summary, body: opened.map_ok(|shown| shown.body) ?? "", comments: opened.map_ok(|shown| shown.comments) ?? [] }
		Ok(desk.asked.fold(known, |shown, asked| if (TicketDesk.comments(asked.request) and Tickets.ticket_of(asked.request) == ticket_id) Tickets.applied(listing, shown, asked.request, { comment_id: "pending-${asked.serial.to_str()}", now: "" }) ?? shown else shown))
	}

	## Whether a ticket's topic has answered with its body and comments.
	loaded : State, Str -> Bool
	loaded = |desk, ticket_id| desk.opened.any(|shown| shown.summary.id == ticket_id)

	## What a pane shows of a ticket no one has.
	missing : Tickets.Ticket
	missing = { summary: { id: "", provider: "", source: "", key: "", title: "", url: "", status: { id: "", name: "", kind: Open }, assignees: [], labels: [], waiting_on: [], branch: Err(Missing), updated: "" }, body: "", comments: [] }

	## The name of a ticket's source.
	source_name : State, Str -> Str
	source_name = |desk, source_id| desk.listing.sources.find_first(|source| source.id == source_id).map_ok(|source| source.name) ?? source_id

	comments : Tickets.Request -> Bool
	comments = |request|
		match request {
			Comment(_) => Bool.True
			_ => Bool.False
		}

	## Each session's link, with the links and unlinks on their way applied.
	links_shown : State -> List(Tickets.Link)
	links_shown = |desk|
		desk.asked.fold(
			desk.links,
			|links, asked|
				match asked.request {
					Link({ session_id, ticket_id }) => links.drop_if(|link| link.session_id == session_id).append({ session_id, ticket_id, inferred: Bool.False })
					Unlink({ session_id }) => links.drop_if(|link| link.session_id == session_id)
					_ => links
				},
		)

	## Whether a request about the ticket is on its way.
	pending : State, Str -> Bool
	pending = |desk, ticket_id| desk.asked.any(|asked| Tickets.ticket_of(asked.request) == ticket_id or TicketDesk.unlinks(desk, asked.request, ticket_id))

	unlinks : State, Tickets.Request, Str -> Bool
	unlinks = |desk, request, ticket_id|
		match request {
			Unlink({ session_id }) => desk.links.any(|link| link.session_id == session_id and link.ticket_id == ticket_id)
			_ => Bool.False
		}

	## Takes the daemon's answer to the request sent as `serial`: accepted,
	## it waits for the poll numbered so; refused, it is undone.
	answered : State, U64, [Accepted(U64), Refused] -> State
	answered = |desk, serial, answer|
		match answer {
			Accepted(poll) => { ..desk, asked: desk.asked.map(|asked| if (asked.serial == serial) { ..asked, accepted: poll } else asked) }
			Refused => { ..desk, asked: desk.asked.drop_if(|asked| asked.serial == serial) }
		}

	## Drops the requests the poll numbered `serial` answered for.
	settled : State, U64 -> State
	settled = |desk, serial| { ..desk, asked: desk.asked.drop_if(|asked| asked.accepted > 0 and asked.accepted <= serial) }

	received : State, [Listing(Tickets.Listing), Opened(Tickets.Ticket), Links(List(Tickets.Link))] -> State
	received = |desk, event|
		match event {
			Listing(listing) => { ..desk, listing }
			Opened(shown) => { ..desk, opened: desk.opened.drop_if(|known| known.summary.id == shown.summary.id).append(shown) }
			Links(links) => { ..desk, links }
		}

	## The kinds of status a list's Status filter offers, by name.
	kinds : List({ name : Str, kinds : List(Tickets.Kind) })
	kinds = [
		{ name: "Open or started", kinds: [Open, Started] },
		{ name: "Open", kinds: [Open] },
		{ name: "Started", kinds: [Started] },
		{ name: "Done", kinds: [Done] },
		{ name: "Canceled", kinds: [Canceled] },
		{ name: "Any status", kinds: [] },
	]

	kinds_name : List(Tickets.Kind) -> Str
	kinds_name = |picked| TicketDesk.kinds.find_first(|named| named.kinds == picked).map_ok(|named| named.name) ?? "Any status"

	kinds_named : Str -> List(Tickets.Kind)
	kinds_named = |name| TicketDesk.kinds.find_first(|named| named.name == name).map_ok(|named| named.kinds) ?? []

	assignee_name : [Anyone, Me, Nobody, Person(Str)] -> Str
	assignee_name = |assignee|
		match assignee {
			Me => "Me"
			Nobody => "Nobody"
			_ => "Anyone"
		}

	assignee_named : Str -> [Anyone, Me, Nobody, Person(Str)]
	assignee_named = |name| if (name == "Me") Me else if (name == "Nobody") Nobody else Anyone
}

## Byte strings in order, as a dictionary orders words.
bytes_order : List(U8), List(U8) -> [Before, After, Same]
bytes_order = |left, right|
	match (left.first(), right.first()) {
		(Ok(first), Ok(second)) if first == second => bytes_order(left.drop_first(1), right.drop_first(1))
		(Ok(first), Ok(second)) => if (first < second) Before else After
		(Err(_), Ok(_)) => Before
		(Ok(_), Err(_)) => After
		_ => Same
	}

status : Str, Tickets.Kind -> Tickets.Status
status = |id, kind| { id, name: id, kind }

summary : Str, Str, Str -> Tickets.Summary
summary = |id, title, updated| { id, provider: "mock", source: "repo", key: "#${id.drop_prefix("t")}", title, url: "", status: status("open", Open), assignees: [], labels: [], waiting_on: [], branch: Err(Missing), updated }

desk : State
desk = {
	..TicketDesk.initial,
	listing: {
		sources: [{ id: "repo", provider: "mock", name: "repo", url: "", me: Ok({ id: "ada", name: "Ada" }), people: [{ id: "ada", name: "Ada" }, { id: "bo", name: "Bo" }], statuses: [status("open", Open), status("closed", Done)] }],
		tickets: [summary("t1", "Old", "2026-01-01T08:00:00.000Z"), summary("t2", "New", "2026-01-02T08:00:00.000Z")],
	},
}

# A status change shows at once, and leaves the list its filter keeps, until refused.
expect {
	asked = { ..desk, asked: [{ serial: 1, request: SetStatus({ ticket_id: "t2", status_id: "closed" }), accepted: 0 }] }
	view = TicketDesk.view(asked, "pane-1")
	TicketDesk.listed(desk, view).map(|shown| shown.key) == ["#2", "#1"]
		and TicketDesk.listed(asked, view).map(|shown| shown.key) == ["#1"]
		and TicketDesk.pending(asked, "t2")
		and TicketDesk.listed(TicketDesk.answered(asked, 1, Refused), view).len() == 2
		and TicketDesk.settled(TicketDesk.answered(asked, 1, Accepted(3)), 3).asked == []
}

# A comment on its way shows after the ticket's, and a link moves a session's.
expect {
	opened = TicketDesk.received(desk, Opened({ summary: summary("t1", "Old", ""), body: "", comments: [] }))
	asked = { ..opened, links: [{ session_id: "s", ticket_id: "t2", inferred: Bool.True }], asked: [{ serial: 4, request: Comment({ ticket_id: "t1", body: "On it" }), accepted: 0 }, { serial: 5, request: Link({ session_id: "s", ticket_id: "t1" }), accepted: 0 }] }
	TicketDesk.ticket_shown(asked, "t1").map_ok(|shown| shown.comments.map(|comment| (comment.id, comment.author.name, comment.body))) == Ok([("pending-4", "Ada", "On it")])
		and TicketDesk.links_shown(asked) == [{ session_id: "s", ticket_id: "t1", inferred: Bool.False }]
}

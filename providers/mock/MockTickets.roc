## The mock provider's tickets: scripted issues of two sources, one shaped
## as GitHub's (open or closed) and one as Linear's (a team's workflow), so
## tickets.v1 works without a real tracker. Pure: the daemon keeps the
## tickets as calls change them.
import cap.Tickets

MockTickets := [].{

	## The user, as both sources know them.
	me : Tickets.Person
	me = { id: "ada", name: "Ada" }

	## The two sources: `mock/liton`, shaped as a GitHub repository's issues,
	## and `LIT`, as a Linear team's tickets.
	sources : List(Tickets.Source)
	sources = [
		{
			id: "mock/liton",
			provider: "mock",
			name: "mock/liton",
			url: "https://example.com/mock/liton/issues",
			me: Ok(MockTickets.me),
			people: [MockTickets.me, bo],
			statuses: [{ id: "open", name: "Open", kind: Open }, { id: "closed", name: "Closed", kind: Done }, { id: "not_planned", name: "Not planned", kind: Canceled }],
			repo: Err(Missing),
		},
		{
			id: "LIT",
			provider: "mock",
			name: "Liton team",
			url: "https://example.com/linear/LIT",
			me: Ok(MockTickets.me),
			people: [MockTickets.me, bo, cy],
			statuses: [{ id: "backlog", name: "Backlog", kind: Open }, { id: "todo", name: "Todo", kind: Open }, { id: "in_progress", name: "In Progress", kind: Started }, { id: "done", name: "Done", kind: Done }, { id: "canceled", name: "Canceled", kind: Canceled }],
			repo: Err(Missing),
		},
	]

	## The tickets a fresh daemon starts with. LIT-12 suggests the branch
	## the fix-auth session works on, so the session links to it; #9 waits
	## on the user's answer.
	seeds : List(Tickets.Ticket)
	seeds = [
		ticket(
			{ id: "LIT-12", source: "LIT", key: "LIT-12", title: "Logging in sends you back to /login", status: "in_progress", assignees: [MockTickets.me], labels: ["bug", "auth"], waiting_on: [], branch: Ok("fix-auth"), updated: "2026-01-01T08:30:00.000Z" },
			"After logging in, the app redirects to `/login` instead of the page you came from.\n\n- Expected: back where you were.\n- Actual: `/login` again.",
			[{ id: "LIT-12-c1", author: cy, body: "Seen on every browser. The redirect target looks hard-coded.", created: "2026-01-01T08:00:00.000Z" }],
		),
		ticket(
			{ id: "LIT-15", source: "LIT", key: "LIT-15", title: "Show the first agent sooner", status: "todo", assignees: [bo], labels: ["performance"], waiting_on: [], branch: Err(Missing), updated: "2025-12-30T12:00:00.000Z" },
			"The first poll waits for the manifest. Send them together.",
			[],
		),
		ticket(
			{ id: "mock/liton#7", source: "mock/liton", key: "#7", title: "CI fails about one run in five", status: "open", assignees: [MockTickets.me], labels: ["bug", "ci"], waiting_on: [], branch: Err(Missing), updated: "2025-12-31T10:00:00.000Z" },
			"`test.timeline_order` fails now and then:\n\n```\nexpected 3, got 2\n```",
			[],
		),
		ticket(
			{ id: "mock/liton#9", source: "mock/liton", key: "#9", title: "Document the review flow", status: "open", assignees: [], labels: ["docs"], waiting_on: [MockTickets.me.id], branch: Err(Missing), updated: "2026-01-01T07:00:00.000Z" },
			"How a review's comments reach the agent, and how it answers them.",
			[{ id: "mock/liton#9-c1", author: bo, body: "@ada should this cover review rounds too?", created: "2026-01-01T07:00:00.000Z" }],
		),
		ticket(
			{ id: "mock/liton#4", source: "mock/liton", key: "#4", title: "Archive sessions from their menu", status: "closed", assignees: [bo], labels: ["enhancement"], waiting_on: [], branch: Err(Missing), updated: "2025-12-20T09:00:00.000Z" },
			"A session's ⋮ menu archives it.",
			[],
		),
	]

	## The tickets as the daemon keeps their changes: each seeded one as it
	## was changed last, if it was.
	with_changes : List(Tickets.Ticket) -> List(Tickets.Ticket)
	with_changes = |stored| MockTickets.seeds.map(|seeded| stored.find_first(|stored_ticket| stored_ticket.summary.id == seeded.summary.id) ?? seeded)

	## The sources and the summaries of `tickets`.
	listing : List(Tickets.Ticket) -> Tickets.Listing
	listing = |tickets| { sources: MockTickets.sources, tickets: tickets.map(|shown| shown.summary) }

	## A ticket as a Comment, SetStatus, SetAssignees or EditTicket changes it, a comment
	## numbered after the ticket's, at `now`.
	changed : List(Tickets.Ticket), Tickets.Request, Str -> Try(Tickets.Ticket, [NotFound(Str), NoSuchStatus(Str), NoSuchPerson(Str), EmptyComment, EmptyTitle])
	changed = |tickets, request, now| {
		ticket_id = Tickets.ticket_of(request)
		match tickets.find_first(|shown| shown.summary.id == ticket_id) {
			Err(_) => Err(NotFound(ticket_id))
			Ok(shown) => {
				applied = Tickets.applied(MockTickets.listing(tickets), shown, request, { comment_id: "${ticket_id}-c${(shown.comments.len() + 1).to_str()}", now })
				applied.map_ok(|done| { ..done, summary: { ..done.summary, updated: now } })
			}
		}
	}
}

bo : Tickets.Person
bo = { id: "bo", name: "Bo" }

cy : Tickets.Person
cy = { id: "cy", name: "Cy" }

## A seeded ticket of a source, its status named by id.
ticket : { id : Str, source : Str, key : Str, title : Str, status : Str, assignees : List(Tickets.Person), labels : List(Str), waiting_on : List(Str), branch : Try(Str, [Missing]), updated : Str }, Str, List(Tickets.Comment) -> Tickets.Ticket
ticket = |seed, body, comments| {
	source = MockTickets.sources.find_first(|known| known.id == seed.source)
	status = source.map_ok(|known| known.statuses).ok_or([]).find_first(|known| known.id == seed.status) ?? { id: seed.status, name: seed.status, kind: Open }
	url = source.map_ok(|known| "${known.url}/${seed.key.drop_prefix("#")}") ?? ""
	{ summary: { id: seed.id, provider: "mock", source: seed.source, key: seed.key, title: seed.title, url, status, assignees: seed.assignees, labels: seed.labels, waiting_on: seed.waiting_on, branch: seed.branch, updated: seed.updated }, body, comments }
}

# Each seed's status and people are its source's, and fix-auth's branch names LIT-12.
expect MockTickets.seeds.all(|seeded| MockTickets.sources.any(|source| source.id == seeded.summary.source and source.statuses.contains(seeded.summary.status) and seeded.summary.assignees.all(|person| source.people.contains(person))))
expect Tickets.inferred("fix-auth", MockTickets.listing(MockTickets.seeds).tickets).map_ok(|shown| shown.id) == Ok("LIT-12")

expect {
	now = "2026-01-02T00:00:00.000Z"
	commented = MockTickets.changed(MockTickets.seeds, Comment({ ticket_id: "mock/liton#9", body: "Yes, rounds too." }), now)
	closed = MockTickets.changed(MockTickets.seeds, SetStatus({ ticket_id: "mock/liton#7", status_id: "closed" }), now)
	kept = MockTickets.with_changes(closed.map_ok(|shown| [shown]) ?? [])
	commented.map_ok(|shown| shown.comments.map(|comment| (comment.id, comment.author.name))) == Ok([("mock/liton#9-c1", "Bo"), ("mock/liton#9-c2", "Ada")])
		and kept.keep_if(|shown| shown.summary.status.kind == Done).map(|shown| (shown.summary.key, shown.summary.updated)) == [("#7", now), ("#4", "2025-12-20T09:00:00.000Z")]
		and MockTickets.changed(MockTickets.seeds, SetStatus({ ticket_id: "mock/liton#7", status_id: "done" }), now) == Err(NoSuchStatus("done"))
		and MockTickets.changed(MockTickets.seeds, SetStatus({ ticket_id: "nope", status_id: "open" }), now) == Err(NotFound("nope"))
}

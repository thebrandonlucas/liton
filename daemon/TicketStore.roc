import cap.Tickets

## The tickets the daemon keeps in its own tables, as `tickets.v1` shows
## them, provider `tickets`: projects, each a source whose tickets are
## named by its prefix and a number, as `LIT-12`, and move between one set
## of statuses.
TicketStore := [].{

	## The provider the daemon's tickets are named by.
	provider : Str
	provider = "tickets"

	## A project as its row keeps it.
	Project : { id : Str, name : Str, prefix : Str }

	## A ticket as its row keeps it: `seq` names it across projects,
	## `number` within its own; `assignees` are people's ids.
	Kept : { seq : I64, project : Project, number : I64, title : Str, body : Str, status : Str, labels : List(Str), assignees : List(Str), updated : Str }

	## The statuses every project's tickets move between, a new one Todo.
	statuses : List(Tickets.Status)
	statuses = [
		{ id: "backlog", name: "Backlog", kind: Open },
		{ id: "todo", name: "Todo", kind: Open },
		{ id: "in_progress", name: "In progress", kind: Started },
		{ id: "in_review", name: "In review", kind: Started },
		{ id: "done", name: "Done", kind: Done },
		{ id: "canceled", name: "Canceled", kind: Canceled },
	]

	## The status a new ticket starts in.
	new_status : Str
	new_status = "todo"

	## The source a project is.
	source_id : Project -> Str
	source_id = |project| "${TicketStore.provider}/${project.id}"

	## The project id a source names, if it is one of the daemon's.
	project_of : Str -> Try(Str, [NotOurs])
	project_of = |source| if (source.starts_with("${TicketStore.provider}/")) Ok(source.drop_prefix("${TicketStore.provider}/")) else Err(NotOurs)

	## The id of the ticket `seq`.
	id_of : I64 -> Str
	id_of = |seq| "${TicketStore.provider}/${seq.to_str()}"

	## The `seq` a ticket id names, if it is one of the daemon's.
	seq_of : Str -> Try(I64, [NotOurs])
	seq_of = |ticket_id| if (ticket_id.starts_with("${TicketStore.provider}/")) I64.from_str(ticket_id.drop_prefix("${TicketStore.provider}/")).map_err(|_| NotOurs) else Err(NotOurs)

	## The key of the ticket numbered `number` of `project`, as `LIT-12`.
	key : Project, I64 -> Str
	key = |project, number| "${project.prefix}-${number.to_str()}"

	## The prefix a project named `name` gets unless it names one: the first
	## three letters of a one-word name, else its words' initials, up to
	## four, as `LIT` for liton and `KB` for Kai box.
	prefix_of : Str -> Str
	prefix_of = |name| {
		spaced = name.to_utf8().map(|byte| if (byte >= 'a' and byte <= 'z') byte - 32 else if ((byte >= 'A' and byte <= 'Z') or (byte >= '0' and byte <= '9')) byte else ' ')
		words = Str.from_utf8_lossy(spaced).split_on(" ").drop_if(Str.is_empty).drop_if(|word| !TicketStore.starts_with_letter(word))
		match words {
			[word] => Str.from_utf8_lossy(word.to_utf8().take_first(3))
			_ => Str.from_utf8_lossy(words.fold([], |initials, word| initials.concat(word.to_utf8().take_first(1))).take_first(4))
		}
	}

	## Whether `text` starts with a capital letter.
	starts_with_letter : Str -> Bool
	starts_with_letter = |text|
		match text.to_utf8().first() {
			Ok(byte) => byte >= 'A' and byte <= 'Z'
			Err(_) => Bool.False
		}

	## The prefix a CreateProject asks for: the one it names, in capitals, or
	## else the one its name makes.
	prefix_asked : { name : Str, prefix : Str } -> Str
	prefix_asked = |{ name, prefix }| if (prefix.trim() == "") TicketStore.prefix_of(name) else Str.from_utf8_lossy(prefix.trim().to_utf8().map(|byte| if (byte >= 'a' and byte <= 'z') byte - 32 else byte))

	## Why a CreateTicket or CreateProject can't be made among `projects`, if
	## it can't. A prefix is 1 to 6 capitals and digits, a capital first, and
	## one project's alone.
	refusal : List(Project), Tickets.Request -> Try({}, Str)
	refusal = |projects, request|
		match request {
			CreateTicket({ title, .. }) if title.trim() == "" => Err(Tickets.refusal(EmptyTitle))
			CreateTicket({ source, .. }) =>
				match TicketStore.project_of(source) {
					Ok(project_id) if projects.any(|project| project.id == project_id) => Ok({})
					_ => Err("there is no project ${source}")
				}
			CreateProject({ name, .. }) if name.trim() == "" => Err("a project needs a name")
			CreateProject(asked) => {
				prefix = TicketStore.prefix_asked(asked)
				bytes = prefix.to_utf8()
				if bytes.is_empty() or bytes.len() > 6 or !TicketStore.starts_with_letter(prefix) or !bytes.all(|byte| (byte >= 'A' and byte <= 'Z') or (byte >= '0' and byte <= '9')) {
					Err("a prefix is 1 to 6 letters and digits, a letter first, as LIT")
				} else {
					match projects.find_first(|project| project.prefix == prefix) {
						Ok(taken) => Err("the prefix ${prefix} is ${taken.name}'s")
						Err(_) => Ok({})
					}
				}
			}
			_ => Ok({})
		}

	## A project as a source, of the `people` its tickets can be assigned to,
	## and `me`, the person asking.
	as_source : Project, List(Tickets.Person), Try(Tickets.Person, [Missing]) -> Tickets.Source
	as_source = |project, people, me| { id: TicketStore.source_id(project), provider: TicketStore.provider, name: project.name, url: "", me, people, statuses: TicketStore.statuses }

	## A kept ticket, its assignees named from `people`, with its `comments`.
	ticket : Kept, List(Tickets.Person), List(Tickets.Comment) -> Tickets.Ticket
	ticket = |kept, people, comments| {
		status = TicketStore.statuses.find_first(|known| known.id == kept.status) ?? { id: kept.status, name: kept.status, kind: Open }
		assignees = kept.assignees.map(|id| people.find_first(|person| person.id == id) ?? { id, name: id })
		summary = { id: TicketStore.id_of(kept.seq), provider: TicketStore.provider, source: TicketStore.source_id(kept.project), key: TicketStore.key(kept.project, kept.number), title: kept.title, url: "", status, assignees, labels: kept.labels, waiting_on: [], branch: Err(Missing), updated: kept.updated }
		{ summary, body: kept.body, comments }
	}
}

expect TicketStore.prefix_of("liton") == "LIT" and TicketStore.prefix_of("Kai box") == "KB" and TicketStore.prefix_of("my-cool web app") == "MCWA" and TicketStore.prefix_of("42") == ""
expect {
	projects = [{ id: "p1", name: "liton", prefix: "LIT" }]
	(TicketStore.refusal(projects, CreateProject({ name: "Lit", prefix: "" })), TicketStore.refusal(projects, CreateProject({ name: "kai", prefix: "" })), TicketStore.refusal(projects, CreateProject({ name: "x", prefix: "9X" })).is_err(), TicketStore.refusal(projects, CreateTicket({ source: "tickets/p1", title: " ", body: "", labels: [] })).is_err(), TicketStore.refusal(projects, CreateTicket({ source: "tickets/p2", title: "Go", body: "", labels: [] })).is_err())
		== (Err("the prefix LIT is liton's"), Ok({}), Bool.True, Bool.True, Bool.True)
}

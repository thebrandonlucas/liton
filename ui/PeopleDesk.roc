## What Settings' People shows of people.v1 (docs/protocol.md, People): the
## people and invites as polls last answered them, with the requests on
## their way applied so a change shows at once, the invite being written,
## and the link of the last invite made, shown once.
import cap.People

PeopleDesk := [].{

	## A request sent as `serial`, shown until the daemon refuses it, or
	## until the poll numbered `accepted` answers, the first sent after the
	## daemon accepted it (0 while it waits).
	Asked : { serial : U64, request : People.Request, accepted : U64 }

	## The invite being written: whom it is for, their role and their rooms,
	## and why the daemon refused the last one.
	Form : { name : Str, role : Str, rooms : List(Str), failed : Str }

	## The listing as polls answered it, the requests on their way, the
	## invite being written, the link that redeems the last one made, and the
	## page's address, before its `#`, which links name; and the person
	## asked to confirm their removal ("" for none).
	State : { listed : People.Listing, asked : List(Asked), form : Form, link : Str, page : Str, removing : Str }

	initial : State
	initial = { listed: { people: [], invites: [], roles: [] }, asked: [], form: PeopleDesk.blank, link: "", page: "", removing: "" }

	blank : Form
	blank = { name: "", role: "", rooms: [], failed: "" }

	## The people and invites as shown: those listed with the requests on
	## their way applied, an invite being made after the others.
	shown : State -> People.Listing
	shown = |desk|
		desk.asked.fold(
			desk.listed,
			|so_far, { request, serial, .. }|
				match request {
					Invite({ name, role, rooms }) => { ..so_far, invites: so_far.invites.append({ id: "asking:${serial.to_str()}", name, role, rooms, expires: "" }) }
					Remove({ person }) => { ..so_far, people: so_far.people.drop_if(|listed| listed.id == person) }
					Cancel({ id }) => { ..so_far, invites: so_far.invites.drop_if(|invite| invite.id == id) }
					CreateRoom(_) | AddMember(_) => so_far
				},
		)

	## The invite the form makes, or why it can't be sent.
	request_of : Form -> Try(People.Request, Str)
	request_of = |form|
		if form.name.trim() == "" {
			Err("Name whom the invite is for.")
		} else if form.role == "" {
			Err("Pick the role the invite gives.")
		} else {
			Ok(Invite({ name: form.name.trim(), role: form.role, rooms: form.rooms }))
		}

	## `desk` with a request on its way as `serial`.
	asking : State, U64, People.Request -> State
	asking = |desk, serial, request| { ..desk, asked: desk.asked.append({ serial, request, accepted: 0 }), removing: "" }

	## `desk` with the daemon's answer to the request `serial`: accepted, it
	## holds until the poll numbered `poll` answers; refused, it is undone,
	## an invite's form showing why.
	answered : State, U64, [Accepted(U64), Refused(Str)] -> State
	answered = |desk, serial, answer| {
		invited = desk.asked.any(|asked| asked.serial == serial and PeopleDesk.invites(asked.request))
		match answer {
			Accepted(poll) => { ..desk, asked: desk.asked.map(|asked| if (asked.serial == serial) { ..asked, accepted: poll } else asked) }
			Refused(why) => { ..desk, asked: desk.asked.drop_if(|asked| asked.serial == serial), form: if (invited) { ..desk.form, failed: why } else desk.form }
		}
	}

	## Whether `request` makes an invite.
	invites : People.Request -> Bool
	invites = |request|
		match request {
			Invite(_) => Bool.True
			_ => Bool.False
		}

	## Drops the requests the poll numbered `serial` answered for.
	settled : State, U64 -> State
	settled = |desk, serial| { ..desk, asked: desk.asked.drop_if(|asked| asked.accepted > 0 and asked.accepted <= serial) }

	## The form with the room `room_id` picked or not.
	picked : Form, Str, Bool -> Form
	picked = |form, room_id, wanted| { ..form, rooms: if (wanted) form.rooms.drop_if(|room| room == room_id).append(room_id) else form.rooms.drop_if(|room| room == room_id) }
}

expect {
	listed = { people: [{ id: "ab", name: "Dana", role: "staff", agent: Bool.False, owner: Bool.False, devices: 1 }], invites: [{ id: "i1", name: "Eli", role: "staff", rooms: [], expires: "x" }], roles: ["staff"] }
	desk = PeopleDesk.asking(PeopleDesk.asking({ ..PeopleDesk.initial, listed }, 1, Remove({ person: "ab" })), 2, Invite({ name: "Fay", role: "staff", rooms: ["dispatch"] }))
	shown = PeopleDesk.shown(desk)
	shown.people == []
		and shown.invites.map(|invite| (invite.name, invite.expires)) == [("Eli", "x"), ("Fay", "")]
		and PeopleDesk.answered(desk, 2, Refused("no room")).form.failed == "no room"
		and PeopleDesk.answered(desk, 1, Refused("no")).form.failed == ""
		and PeopleDesk.settled(PeopleDesk.answered(desk, 1, Accepted(4)), 4).asked.len() == 1
}

expect PeopleDesk.request_of({ ..PeopleDesk.blank, name: " Dana ", role: "staff" }) == Ok(Invite({ name: "Dana", role: "staff", rooms: [] })) and PeopleDesk.request_of(PeopleDesk.blank).is_err() and PeopleDesk.picked(PeopleDesk.picked(PeopleDesk.blank, "a", Bool.True), "a", Bool.False).rooms == []

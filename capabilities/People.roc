## `people.v1`: the people and agents of the daemon's box, each holding a
## role, and the invites that bring more. An invite is a link, used once
## within 7 days, that pairs the device opening it as a new person, with
## the invite's role and rooms. The daemon offers it itself, to operators
## and to the roles allowed it, its admins, who invite into any role but
## `operator`.
import Rooms

People := [].{

	## A person and the role they hold: `owner` the box's owner, an
	## operator always; `agent` an agent rather than a human; `devices` how
	## many devices they are signed in on.
	Person : { id : Str, name : Str, role : Str, agent : Bool, owner : Bool, devices : U32 }

	## An invite not used yet: for whom, its role, its rooms and when it
	## expires, as 2026-01-01T09:00:00.000Z.
	Invite : { id : Str, name : Str, role : Str, rooms : List(Str), expires : Str }

	## What the topic `people` holds, and the roles whoever asks may invite
	## into.
	Listing : { people : List(Person), invites : List(Invite), roles : List(Str) }

	## `Invite` answers `Invited` with the invite's secret, which no answer
	## holds again: `/ui/index.html#invite=<secret>` redeems it. `Remove`
	## takes a person's role, rooms and devices away, keeping their name for
	## their messages, and `Cancel` an invite not used, each answering
	## `Accepted` or `Rejected` with why. `CreateRoom` makes a room of the
	## box, for its invites to name, answering `RoomCreated` with its id, its
	## name's letters and digits, lowercased, joined by hyphens. `AddMember`
	## makes a person a member of a room, and its admin if `admin`, which an
	## operator alone asks.
	Request : [Invite({ name : Str, role : Str, rooms : List(Str) }), Remove({ person : Str }), Cancel({ id : Str }), CreateRoom({ name : Str, about : Str, kind : Rooms.Kind, private : Bool }), AddMember({ room : Str, person : Str, admin : Bool })]

	Response : [Invited({ id : Str, secret : Str }), RoomCreated({ room_id : Str }), Accepted, Rejected(Str)]
}

expect {
	asked : Try(List(People.Request), _)
	asked = Json.parse("[{\"Invite\":{\"name\":\"Dana\",\"role\":\"staff\",\"rooms\":[\"dispatch\"]}},{\"Remove\":{\"person\":\"ab\"}},{\"Cancel\":{\"id\":\"i1\"}},{\"CreateRoom\":{\"name\":\"Front desk\",\"about\":\"\",\"kind\":\"Forum\",\"private\":true}},{\"AddMember\":{\"room\":\"dispatch\",\"person\":\"ab\",\"admin\":false}}]")
	asked == Ok([Invite({ name: "Dana", role: "staff", rooms: ["dispatch"] }), Remove({ person: "ab" }), Cancel({ id: "i1" }), CreateRoom({ name: "Front desk", about: "", kind: Forum, private: Bool.True }), AddMember({ room: "dispatch", person: "ab", admin: Bool.False })])
}

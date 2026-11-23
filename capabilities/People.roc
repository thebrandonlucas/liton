## `people.v1`: the people and agents whose keys hold a role at the daemon,
## and the invites that bring more. An invite is a link, used once within 7
## days, that pairs the browser opening it and gives its key the invite's
## role and rooms. The daemon offers it itself, to operators and to the
## roles allowed it, its admins, who invite into any role but `operator`.
import Rooms

People := [].{

	## A key holding a role, named by its latest profile, else by its invite.
	Person : { pubkey : Str, name : Str, role : Str }

	## An invite not used yet: for whom, its role, its rooms and when it
	## expires, as 2026-01-01T09:00:00.000Z.
	Invite : { id : Str, name : Str, role : Str, rooms : List(Str), expires : Str }

	## What the topic `people` holds, and the roles whoever asks may invite
	## into.
	Listing : { people : List(Person), invites : List(Invite), roles : List(Str) }

	## `Invite` answers `Invited` with the invite's secret, which no answer
	## holds again: `/ui/index.html#invite=<secret>` redeems it. `Remove`
	## takes a key's role, its rooms and its devices away, and `Cancel` an
	## invite not used, each answering `Accepted` or `Rejected` with why.
	## `CreateRoom` makes a room of the relay, for the box's invites to name,
	## answering `RoomCreated` with its id, its name's letters and digits,
	## lowercased, joined by hyphens.
	Request : [Invite({ name : Str, role : Str, rooms : List(Str) }), Remove({ pubkey : Str }), Cancel({ id : Str }), CreateRoom({ name : Str, about : Str, kind : Rooms.Kind, private : Bool })]

	Response : [Invited({ id : Str, secret : Str }), RoomCreated({ room_id : Str }), Accepted, Rejected(Str)]
}

expect {
	asked : Try(List(People.Request), _)
	asked = Json.parse("[{\"Invite\":{\"name\":\"Dana\",\"role\":\"staff\",\"rooms\":[\"dispatch\"]}},{\"Remove\":{\"pubkey\":\"ab\"}},{\"Cancel\":{\"id\":\"i1\"}},{\"CreateRoom\":{\"name\":\"Front desk\",\"about\":\"\",\"kind\":\"Forum\",\"private\":true}}]")
	asked == Ok([Invite({ name: "Dana", role: "staff", rooms: ["dispatch"] }), Remove({ pubkey: "ab" }), Cancel({ id: "i1" }), CreateRoom({ name: "Front desk", about: "", kind: Forum, private: Bool.True })])
}

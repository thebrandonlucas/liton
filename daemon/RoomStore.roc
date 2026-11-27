import cap.Chat
import cap.Rooms

## The rooms the daemon keeps in its own tables, as `rooms.v1` shows them,
## provider `rooms`: who may do what in a room, and its rows as rooms,
## members and messages. A room's id is its name's (`id_of_name`).
RoomStore := [].{

	## The provider the daemon's rooms are named by.
	provider : Str
	provider = "rooms"

	## A room as its row keeps it.
	Kept : { id : Str, name : Str, about : Str, kind : Str, private : Bool, open : Bool, archived : Bool }

	## The person asking of a room: whether they are an operator of the box,
	## and a member and an admin of the room.
	Asker : { operator : Bool, member : Bool, admin : Bool }

	## The id of a room named `name`: its letters and digits, lowercased,
	## each run of anything else a hyphen, as `Front desk` is `front-desk`.
	id_of_name : Str -> Str
	id_of_name = |name| {
		spaced = name.with_ascii_lowercased().to_utf8().map(|byte| if ((byte >= 'a' and byte <= 'z') or (byte >= '0' and byte <= '9')) byte else ' ')
		Str.join_with(Str.from_utf8_lossy(spaced).split_on(" ").drop_if(|word| word == ""), "-")
	}

	## How a room's row keeps its kind.
	kind_text : Rooms.Kind -> Str
	kind_text = |kind|
		match kind {
			Channel => "Channel"
			Forum => "Forum"
			Direct => "Direct"
			Announce => "Announce"
		}

	## The kind a room's row keeps.
	kind_of : Str -> Rooms.Kind
	kind_of = |text|
		match text {
			"Forum" => Forum
			"Direct" => Direct
			"Announce" => Announce
			_ => Channel
		}

	## The room `kept` as the person `me` sees it, `joined` if a member, last
	## posted in at `updated`.
	room : Kept, { joined : Bool, updated : Try(Str, [Missing]), me : Str } -> Rooms.Room
	room = |kept, { joined, updated, me }| {
		..Rooms.room({ id: kept.id, provider: RoomStore.provider, name: kept.name, kind: RoomStore.kind_of(kept.kind) }),
		topic: if (kept.about == "") Err(Missing) else Ok(kept.about),
		private: kept.private,
		joined,
		updated,
		me: Ok(me),
	}

	## A member of a room, as their person's row and the membership's say.
	member : { id : Str, name : Str, agent : Bool, owner : Bool, admin : Bool } -> Rooms.Member
	member = |{ id, name, agent, owner, admin }| {
		id,
		provider: RoomStore.provider,
		name,
		picture: Err(Missing),
		kind: if (agent) Agent({ owner: Err(Missing) }) else Person,
		role: if (owner) Owner else if (admin) Admin else Member,
		presence: Unknown,
	}

	## A message as its row keeps it, posted at `created_at` milliseconds,
	## a reply with its thread's `root` and its `parent`.
	message : { id : Str, room_id : Str, author : Str, text : Str, root : Str, parent : Str, created_at : I64 }, List(Str) -> Rooms.Message
	message = |row, mentions|
		Rooms.message({ id: row.id, room_id: row.room_id, author: row.author, text: row.text, time: Chat.timestamp(row.created_at), place: if (row.root == "") TopLevel else Reply({ root: row.root, parent: row.parent }), mentions })

	## Why `asked` of the room `found` is refused to `asker`, if it is. A
	## private room is there only for its members and the box's operators;
	## a member posts and reacts, and in an announcement room only its admins
	## post; a room is joined freely when `open`, else by its admins and the
	## box's operators; anyone leaves.
	refusal : Try(Kept, [NoRoom]), Str, Asker, Rooms.Request -> Try({}, Str)
	refusal = |found, room_id, asker, asked| {
		not_member = "you aren't a member of this room: ask one of its admins to add you"
		match found {
			Ok(kept) if !kept.archived and (!kept.private or asker.member or asker.operator) =>
				match asked {
					ListRooms => Ok({})
					Send(_) if !asker.member => Err(not_member)
					Send(_) if kept.kind == "Announce" and !asker.admin => Err("only its admins post here")
					React(_) | Unreact(_) if !asker.member => Err(not_member)
					Join(_) if !(kept.open or asker.member or asker.operator or asker.admin) => Err("the room is closed and you weren't invited: ask one of its admins to add you")
					_ => Ok({})
				}
			_ => Err("there is no room ${room_id}")
		}
	}

	## The thread an entry of `event` belongs to: "" for the room's top
	## level, else its root's id. A reaction is where its message, of root
	## `root`, is; a thread's summary is at the top level, beside its root.
	thread_of : Rooms.Event, Str -> Str
	thread_of = |event, root|
		match event {
			Posted({ place: Reply(reply), .. }) => reply.root
			Reacted(_) | Edited(_) | Deleted(_) => root
			_ => ""
		}
}

expect RoomStore.id_of_name(" Front  desk! 2") == "front-desk-2" and RoomStore.id_of_name("¡!") == ""
expect [Channel, Forum, Direct, Announce].map(|kind| RoomStore.kind_of(RoomStore.kind_text(kind))) == [Channel, Forum, Direct, Announce]
expect {
	room = Ok({ id: "news", name: "News", about: "", kind: "Announce", private: Bool.False, open: Bool.False, archived: Bool.False })
	asker = { operator: Bool.False, member: Bool.True, admin: Bool.False }
	sent = Send({ room_id: "news", text: "hi", place: TopLevel, mentions: [] })
	refused = |found, who, asked| RoomStore.refusal(found, "news", who, asked)
	refused(room, asker, sent) == Err("only its admins post here")
		and refused(room, { ..asker, admin: Bool.True }, sent) == Ok({})
		and refused(room, { ..asker, member: Bool.False }, React({ room_id: "news", message_id: "m", emoji: "+" })) == Err("you aren't a member of this room: ask one of its admins to add you")
		and refused(room, { ..asker, member: Bool.False }, Join({ room_id: "news" })) == Err("the room is closed and you weren't invited: ask one of its admins to add you")
		and refused(room, { ..asker, member: Bool.False, operator: Bool.True }, Join({ room_id: "news" })) == Ok({})
		and refused(room.map_ok(|kept| { ..kept, open: Bool.True }), { ..asker, member: Bool.False }, Join({ room_id: "news" })) == Ok({})
		and refused(room.map_ok(|kept| { ..kept, private: Bool.True }), { ..asker, member: Bool.False }, Join({ room_id: "news" })) == Err("there is no room news")
		and refused(room.map_ok(|kept| { ..kept, archived: Bool.True }), asker, sent) == Err("there is no room news")
		and refused(Err(NoRoom), asker, Leave({ room_id: "news" })) == Err("there is no room news")
}
expect {
	reply = RoomStore.message({ id: "r1", room_id: "general", author: "bo", text: "yes", root: "m1", parent: "m1", created_at: 1_700_000_000_000 }, ["ada"])
	(reply.place, reply.time, RoomStore.thread_of(Posted(reply), "m1"), RoomStore.thread_of(Reacted({ id: "r1", emoji: "+", by: "ada", added: Bool.True }), "m1"), RoomStore.thread_of(Threaded(Rooms.thread([reply], "m1")), ""))
		== (Reply({ root: "m1", parent: "m1" }), "2023-11-14T22:13:20.000Z", "m1", "m1", "")
}
expect {
	shown = RoomStore.member({ id: "p1", name: "Scout", agent: Bool.True, owner: Bool.False, admin: Bool.True })
	(shown.kind, shown.role, RoomStore.member({ id: "p0", name: "Ada", agent: Bool.False, owner: Bool.True, admin: Bool.True }).role) == (Agent({ owner: Err(Missing) }), Admin, Owner)
}

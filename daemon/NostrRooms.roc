import Nostr

## The relay's rooms (NIP-29 groups): what the moderation events of a room,
## in the order they arrived, make of it, and which events the relay takes
## into it. A room is named by its events' `h` tag.
NostrRooms := [].{

	## A room as its moderation events left it. `kind` is its first `t` tag
	## as Buzz's are: `stream`, `forum`, `dm` or `announce`.
	Room : { id : Str, name : Str, about : Str, kind : Str, open : Bool, private : Bool, deleted : Bool, admins : List(Str), members : List(Str) }

	## The key the relay's own events are made with, such as a member an
	## invite adds. Until the relay can sign, they are unsigned and this
	## stands in for its key.
	relay_pubkey : Str
	relay_pubkey = Str.repeat("0", 64)

	## The kinds that change a room: put and remove a user, edit its
	## metadata, delete an event, create and delete it, and ask to join and
	## to leave it.
	moderation_kinds : List(U32)
	moderation_kinds = [9000, 9001, 9002, 9005, 9007, 9008, 9021, 9022]

	## The id of a room named `name`: its letters and digits, lowercased,
	## each run of anything else a hyphen, as `Front desk` is `front-desk`.
	id_of_name : Str -> Str
	id_of_name = |name| {
		spaced = name.with_ascii_lowercased().to_utf8().map(|byte| if ((byte >= 'a' and byte <= 'z') or (byte >= '0' and byte <= '9')) byte else ' ')
		Str.join_with(Str.from_utf8_lossy(spaced).split_on(" ").drop_if(|word| word == ""), "-")
	}

	## The room `events`, its moderation events in the order they arrived,
	## make, if one was created.
	of : List(Nostr.Event) -> Try(Room, [NoRoom])
	of = |events| events.fold(Err(NoRoom), NostrRooms.applied)

	## `found` after `event`, one the relay took. A room the relay creates
	## itself has no admins or members until it adds them.
	applied : Try(Room, [NoRoom]), Nostr.Event -> Try(Room, [NoRoom])
	applied = |found, event| {
		tagged = |name| event.tags.keep_if(|tag| tag.first() == Ok(name)).map(|tag| tag.get(1) ?? "")
		users = tagged("p")
		edited = |room| {
			value = |name, kept| tagged(name).first() ?? kept
			flag = |on, off, kept| if (event.tags.any(|tag| tag == [on])) Bool.True else if (event.tags.any(|tag| tag == [off])) Bool.False else kept
			{ ..room, name: value("name", room.name), about: value("about", room.about), kind: value("t", room.kind), open: flag("open", "closed", room.open), private: flag("private", "public", room.private) }
		}
		creator = if (event.pubkey == NostrRooms.relay_pubkey) [] else [event.pubkey]
		match (found, event.kind) {
			(Err(NoRoom), 9007) => Ok(edited({ id: Nostr.room(event), name: Nostr.room(event), about: "", kind: "stream", open: Bool.False, private: Bool.False, deleted: Bool.False, admins: creator, members: creator }))
			(Ok(room), 9000) => {
				admins = event.tags.keep_if(|tag| tag.first() == Ok("p") and tag.drop_first(2).contains("admin")).map(|tag| tag.get(1) ?? "")
				Ok({ ..room, members: room.members.concat(users.drop_if(|user| room.members.contains(user))), admins: room.admins.concat(admins.drop_if(|user| room.admins.contains(user))) })
			}
			(Ok(room), 9001) => Ok({ ..room, members: room.members.drop_if(|user| users.contains(user)), admins: room.admins.drop_if(|user| users.contains(user)) })
			(Ok(room), 9002) => Ok(edited(room))
			(Ok(room), 9008) => Ok({ ..room, deleted: Bool.True })
			(Ok(room), 9021) if !room.members.contains(event.pubkey) => Ok({ ..room, members: room.members.append(event.pubkey) })
			(Ok(room), 9022) => Ok({ ..room, members: room.members.drop_if(|user| user == event.pubkey), admins: room.admins.drop_if(|user| user == event.pubkey) })
			_ => found
		}
	}

	## Why the relay refuses `event` in the room `found`, as the events
	## before it left it, if it does, as NIP-01's `OK` gives a reason. An
	## admin of a room moderates it, a member speaks in it, and in an
	## `announce` room only its admins do. A room is joined freely only when
	## `open`. Outside a room, only a profile (kind 0) is taken.
	refusal : Try(Room, [NoRoom]), Nostr.Event -> Try({}, Str)
	refusal = |found, event| {
		admin = |room| room.admins.contains(event.pubkey) or event.pubkey == NostrRooms.relay_pubkey
		match (found, event.kind) {
			_ if Nostr.room(event) == "" => if (event.kind == 0) Ok({}) else Err("restricted: an event of kind ${event.kind.to_str()} is taken only in a room, named by its h tag")
			(Ok(_), 9007) => Err("duplicate: the room ${Nostr.room(event)} exists")
			(Err(NoRoom), 9007) => Ok({})
			(Err(NoRoom), _) => Err("restricted: there is no room ${Nostr.room(event)}")
			(Ok(room), _) if room.deleted => Err("restricted: the room ${room.id} was deleted")
			(Ok(room), kind) if [9000, 9001, 9002, 9005, 9008].contains(kind) and !admin(room) => Err("restricted: only the room's admins moderate it")
			(Ok(room), 9021) => if (room.open or admin(room)) Ok({}) else Err("restricted: the room is closed: its admins add its members")
			(Ok(_), 9022) => Ok({})
			(Ok(room), _) if !room.members.contains(event.pubkey) and !admin(room) => Err("restricted: only the room's members speak in it")
			(Ok(room), _) if room.kind == "announce" and !admin(room) => Err("restricted: only the room's admins speak in an announce room")
			_ => Ok({})
		}
	}
}

expect {
	event = |pubkey, kind, tags| { id: "", pubkey, created_at: 0, kind, tags: [["h", "general"]].concat(tags), content: "", sig: "" }
	created = NostrRooms.of([event("ada", 9007, [["name", "General"], ["open"]]), event("ada", 9000, [["p", "bo"], ["p", "cy", "admin"]]), event("bo", 9022, [])])
	created.map_ok(|room| (room.name, room.open, room.admins, room.members)) == Ok(("General", Bool.True, ["ada", "cy"], ["ada", "cy"]))
}
expect {
	event = |pubkey, kind, tags| { id: "", pubkey, created_at: 0, kind, tags: [["h", "general"]].concat(tags), content: "", sig: "" }
	room = NostrRooms.of([event("ada", 9007, [["t", "announce"]]), event("ada", 9000, [["p", "bo"]])])
	refused = |pubkey, kind| NostrRooms.refusal(room, event(pubkey, kind, [])).is_err()
	(refused("bo", 9), refused("ada", 9), refused("bo", 9000), refused("eve", 9021), refused("eve", 7), NostrRooms.refusal(Err(NoRoom), event("ada", 9, [])).is_err())
		== (Bool.True, Bool.False, Bool.True, Bool.True, Bool.True, Bool.True)
}
expect NostrRooms.refusal(Err(NoRoom), { id: "", pubkey: "a", created_at: 0, kind: 0, tags: [], content: "{}", sig: "" }) == Ok({})
expect {
	created = NostrRooms.of([{ id: "", pubkey: NostrRooms.relay_pubkey, created_at: 0, kind: 9007, tags: [["h", "front-desk"], ["name", "Front desk"], ["private"]], content: "", sig: "" }])
	created.map_ok(|room| (room.name, room.private, room.admins, room.members)) == Ok(("Front desk", Bool.True, [], [])) and NostrRooms.id_of_name(" Front  desk! 2") == "front-desk-2" and NostrRooms.id_of_name("¡!") == ""
}

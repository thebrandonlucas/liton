## `rooms.v1`: rooms where people and agents talk, as any NIP-29 relay or
## other source of rooms keeps them. A room is a channel, a forum (its
## top-level messages are posts, each with a thread of replies), a direct
## conversation or announcements. Ids are opaque: a relay's may be a group's
## UUID, an event id and a public key.
import "tests/rooms.json" as golden_json : Str

Rooms := [].{
	Kind : [Channel, Forum, Direct, Announce]

	## `joined` is whether you are a member; `me` your member id there, when
	## the provider knows it, which reactions name; `links` the repositories
	## or projects it discusses, as clone URLs.
	Room : {
		id : Str,
		provider : Str,
		name : Str,
		kind : Kind,
		topic : Try(Str, [Missing]),
		private : Bool,
		archived : Bool,
		joined : Bool,
		unread : [Counted({ messages : U32, mentions : U32 }), Unknown],
		updated : Try(Str, [Missing]),
		links : List(Str),
		me : Try(Str, [Missing]),
	}

	## An agent's `owner` is told only when its provider verified it.
	Member : {
		id : Str,
		provider : Str,
		name : Str,
		picture : Try(Str, [Missing]),
		kind : [Person, Agent({ owner : Try(Str, [Missing]) })],
		role : [Owner, Admin, Member, Guest],
		presence : [Online, Away, Offline, Unknown],
	}

	## Where a message is: in the room, or a reply in the thread of the
	## top-level message `root`, to `parent` (the root or another reply).
	Place : [TopLevel, Reply({ root : Str, parent : Str })]

	Reaction : { emoji : Str, by : List(Str) }

	## `author` and `mentions` are members' ids; `time` such as
	## 2026-01-01T09:00:00.000Z.
	Message : {
		id : Str,
		room_id : Str,
		author : Str,
		text : Str,
		time : Str,
		place : Place,
		mentions : List(Str),
		reactions : List(Reaction),
		edited : Bool,
		deleted : Bool,
	}

	## A thread's summary, as a room's messages topic shows it beside its root.
	Thread : { root : Str, replies : U32, last_reply : Try(Str, [Missing]), participants : List(Str) }

	Event : [
		Posted(Message),
		Edited({ id : Str, text : Str }),
		Deleted({ id : Str }),
		Reacted({ id : Str, emoji : Str, by : Str, added : Bool }),
		Threaded(Thread),
		Typing({ member : Str, place : Place }),
	]

	## Sequences are the provider's, in the order events arrived, and only
	## increase; a client orders messages by `time`.
	Entry : { sequence : U64, event : Event }

	## A thread starts with the first `Send` replying in it. `Send` answers
	## `Sent` with the message's id, and the others `Accepted`, once the
	## provider took them.
	Request : [
		ListRooms,
		Send({ room_id : Str, text : Str, place : Place, mentions : List(Str) }),
		React({ room_id : Str, message_id : Str, emoji : Str }),
		Unreact({ room_id : Str, message_id : Str, emoji : Str }),
		Join({ room_id : Str }),
		Leave({ room_id : Str }),
	]

	Response : [Rooms(List(Room)), Sent({ message_id : Str }), Accepted, Rejected(Str)]

	## A room its provider tells nothing more of.
	room : { id : Str, provider : Str, name : Str, kind : Kind } -> Room
	room = |{ id, provider, name, kind }| { id, provider, name, kind, topic: Err(Missing), private: Bool.False, archived: Bool.False, joined: Bool.True, unread: Unknown, updated: Err(Missing), links: [], me: Err(Missing) }

	## A message as it is posted, unedited and with no reactions.
	message : { id : Str, room_id : Str, author : Str, text : Str, time : Str, place : Place, mentions : List(Str) } -> Message
	message = |{ id, room_id, author, text, time, place, mentions }| { id, room_id, author, text, time, place, mentions, reactions: [], edited: Bool.False, deleted: Bool.False }

	## The messages a log posts, as its edits, deletions and reactions leave
	## them, in the order they were posted.
	messages : List(Entry) -> List(Message)
	messages = |log|
		log.fold(
			[],
			|so_far, entry|
				match entry.event {
					Posted(posted) => so_far.drop_if(|known| known.id == posted.id).append(posted)
					Edited({ id, text }) => so_far.map(|known| if (known.id == id) { ..known, text, edited: Bool.True } else known)
					Deleted({ id }) => so_far.map(|known| if (known.id == id) { ..known, text: "", deleted: Bool.True } else known)
					Reacted({ id, emoji, by, added }) => so_far.map(|known| if (known.id == id) { ..known, reactions: Rooms.reacted(known.reactions, { emoji, by, added }) } else known)
					_ => so_far
				},
		)

	## Reactions with one added or taken back, an emoji no one is left
	## reacting with gone.
	reacted : List(Reaction), { emoji : Str, by : Str, added : Bool } -> List(Reaction)
	reacted = |reactions, { emoji, by, added }| {
		others = |reaction| reaction.by.drop_if(|member| member == by)
		with_emoji = if (added and !reactions.any(|reaction| reaction.emoji == emoji)) reactions.append({ emoji, by: [] }) else reactions
		with_emoji
			.map(|reaction| if (reaction.emoji != emoji) reaction else { emoji, by: if (added) others(reaction).append(by) else others(reaction) })
			.drop_if(|reaction| reaction.by.is_empty())
	}

	## The latest summary of each thread a log tells.
	threads : List(Entry) -> List(Thread)
	threads = |log|
		log.fold(
			[],
			|so_far, entry|
				match entry.event {
					Threaded(summary) => so_far.drop_if(|known| known.root == summary.root).append(summary)
					_ => so_far
				},
		)

	## The summary of the thread of `root` from the messages posted.
	thread : List(Message), Str -> Thread
	thread = |posted, root| {
		replies = posted.keep_if(|shown| shown.place != TopLevel and Rooms.root_of(shown) == root)
		{
			root,
			replies: replies.len().to_u32_wrap(),
			last_reply: replies.last().map_ok(|reply| reply.time).map_err(|_| Missing),
			participants: replies.fold([], |authors, reply| if (authors.contains(reply.author)) authors else authors.append(reply.author)),
		}
	}

	## The top-level message a message is, or replies in the thread of.
	root_of : Message -> Str
	root_of = |shown|
		match shown.place {
			TopLevel => shown.id
			Reply({ root, .. }) => root
		}

	## The members typing in `place` as the log ends: those whose last word
	## there is that they type, not a message.
	typing : List(Entry), Place -> List(Str)
	typing = |log, place|
		log.fold(
			[],
			|so_far, entry|
				match entry.event {
					Typing(typed) if typed.place == place => if (so_far.contains(typed.member)) so_far else so_far.append(typed.member)
					Posted(posted) => so_far.drop_if(|member| member == posted.author)
					_ => so_far
				},
		)

	## The thread a log's entry belongs to: "" for the room's top level,
	## else its root. A reaction, edit or deletion belongs where its message
	## does, among `posted`.
	place_of : List(Message), Event -> Str
	place_of = |posted, event| {
		of_message = |id| posted.find_first(|known| known.id == id).map_ok(|known| if (known.place == TopLevel) "" else Rooms.root_of(known)) ?? ""
		match event {
			Posted(shown) => if (shown.place == TopLevel) "" else Rooms.root_of(shown)
			Edited({ id, .. }) | Deleted({ id }) => of_message(id)
			Reacted({ id, .. }) => of_message(id)
			Threaded(_) => ""
			Typing({ place: TopLevel, .. }) => ""
			Typing({ place: Reply({ root, .. }), .. }) => root
		}
	}
}

posted : Str, Rooms.Place -> Rooms.Event
posted = |id, place| Posted(Rooms.message({ id, room_id: "general", author: "ada", text: id, time: "2026-01-01T09:00:00.000Z", place, mentions: [] }))

expect {
	reply = Reply({ root: "m1", parent: "m1" })
	log = [posted("m1", TopLevel), posted("m2", reply), Reacted({ id: "m1", emoji: "+", by: "ada", added: Bool.True }), Reacted({ id: "m1", emoji: "+", by: "bo", added: Bool.True }), Reacted({ id: "m1", emoji: "+", by: "ada", added: Bool.False }), Edited({ id: "m2", text: "fixed" })].map_with_index(|event, index| { sequence: index.to_u64() + 1, event })
	shown = Rooms.messages(log)
	shown.map(|message| (message.id, message.text, message.reactions)) == [("m1", "m1", [{ emoji: "+", by: ["bo"] }]), ("m2", "fixed", [])]
		and Rooms.thread(shown, "m1") == { root: "m1", replies: 1, last_reply: Ok("2026-01-01T09:00:00.000Z"), participants: ["ada"] }
		and Rooms.place_of(shown, Reacted({ id: "m2", emoji: "+", by: "x", added: Bool.True })) == "m1"
		and Rooms.place_of(shown, Reacted({ id: "m1", emoji: "+", by: "x", added: Bool.True })) == ""
}

expect Rooms.reacted([], { emoji: "+", by: "ada", added: Bool.False }) == [] and Rooms.reacted([{ emoji: "+", by: ["ada"] }], { emoji: "+", by: "ada", added: Bool.True }) == [{ emoji: "+", by: ["ada"] }]

expect {
	log = [Typing({ member: "agent", place: TopLevel }), Typing({ member: "bo", place: TopLevel }), posted("m1", TopLevel)].map_with_index(|event, index| { sequence: index.to_u64() + 1, event })
	Rooms.typing(log, TopLevel) == ["agent", "bo"] and Rooms.typing(log, Reply({ root: "m1", parent: "m1" })) == []
}

## The golden fixture tests/rooms.json holds: the wire changes only on purpose.
golden : { rooms : List(Rooms.Room), members : List(Rooms.Member), entries : List(Rooms.Entry), requests : List(Rooms.Request), responses : List(Rooms.Response) }
golden = {
	rooms: [
		{ ..Rooms.room({ id: "general", provider: "mock", name: "general", kind: Channel }), topic: Ok("The team"), unread: Counted({ messages: 3, mentions: 1 }), updated: Ok("2026-01-01T09:00:00.000Z"), links: ["https://example.com/liton.git"], me: Ok("you") },
		{ ..Rooms.room({ id: "ideas", provider: "mock", name: "ideas", kind: Forum }), private: Bool.True, joined: Bool.False },
	],
	members: [
		{ id: "you", provider: "mock", name: "You", picture: Err(Missing), kind: Person, role: Owner, presence: Online },
		{ id: "scout", provider: "mock", name: "Scout", picture: Ok("https://example.com/scout.png"), kind: Agent({ owner: Ok("you") }), role: Member, presence: Unknown },
		{ id: "bot", provider: "mock", name: "Bot", picture: Err(Missing), kind: Agent({ owner: Err(Missing) }), role: Guest, presence: Away },
	],
	entries: [
		{ sequence: 1, event: Posted({ ..Rooms.message({ id: "m1", room_id: "general", author: "you", text: "@Scout can you look at the build?", time: "2026-01-01T09:00:00.000Z", place: TopLevel, mentions: ["scout"] }), reactions: [{ emoji: "eyes", by: ["scout"] }] }) },
		{ sequence: 2, event: Typing({ member: "scout", place: Reply({ root: "m1", parent: "m1" }) }) },
		{ sequence: 3, event: Posted(Rooms.message({ id: "m2", room_id: "general", author: "scout", text: "Found it: Auth.roc:41", time: "2026-01-01T09:00:05.000Z", place: Reply({ root: "m1", parent: "m1" }), mentions: [] })) },
		{ sequence: 4, event: Threaded({ root: "m1", replies: 1, last_reply: Ok("2026-01-01T09:00:05.000Z"), participants: ["scout"] }) },
		{ sequence: 5, event: Reacted({ id: "m2", emoji: "+", by: "you", added: Bool.True }) },
		{ sequence: 6, event: Edited({ id: "m2", text: "Found it: Auth.roc:42" }) },
		{ sequence: 7, event: Deleted({ id: "m2" }) },
		{ sequence: 8, event: Threaded({ root: "m3", replies: 0, last_reply: Err(Missing), participants: [] }) },
	],
	requests: [
		ListRooms,
		Send({ room_id: "general", text: "@Scout thanks", place: Reply({ root: "m1", parent: "m2" }), mentions: ["scout"] }),
		Send({ room_id: "general", text: "Morning", place: TopLevel, mentions: [] }),
		React({ room_id: "general", message_id: "m1", emoji: "+" }),
		Unreact({ room_id: "general", message_id: "m1", emoji: "+" }),
		Join({ room_id: "ideas" }),
		Leave({ room_id: "ideas" }),
	],
	responses: [Rooms([]), Sent({ message_id: "m9" }), Accepted, Rejected("no room lounge")],
}

expect Json.to_str(golden) == golden_json.trim()

expect {
	decoded : Try({ rooms : List(Rooms.Room), members : List(Rooms.Member), entries : List(Rooms.Entry), requests : List(Rooms.Request), responses : List(Rooms.Response) }, _)
	decoded = Json.parse(golden_json)
	decoded == Ok(golden)
}

## The mock provider's rooms.v1: three scripted rooms, one a forum, where
## you talk with people and two agents, who type and then answer in a
## thread when a message mentions them. Pure: it says what happens and when,
## and the daemon stores and serves it.
import cap.Chat
import cap.Rooms

MockRooms := [].{

	## An event and how long after the call that caused it it happens.
	Scheduled : { delay_ms : U64, event : Rooms.Event }

	## Your member id in every mock room.
	me : Str
	me = "you"

	## The rooms as the daemon starts with them, all joined but releases.
	rooms : List(Rooms.Room)
	rooms = [
		{ ..Rooms.room({ id: "general", provider: "mock", name: "general", kind: Channel }), topic: Ok("Everything liton"), links: ["https://github.com/thebrandonlucas/liton.git"], me: Ok(MockRooms.me) },
		{ ..Rooms.room({ id: "ideas", provider: "mock", name: "ideas", kind: Forum }), topic: Ok("A post per idea, discussed in its thread"), me: Ok(MockRooms.me) },
		{ ..Rooms.room({ id: "releases", provider: "mock", name: "releases", kind: Announce }), joined: Bool.False, me: Ok(MockRooms.me) },
	]

	## Everyone in the mock rooms: you, Ada, and the agents Scout, yours, and
	## Patch, Ada's.
	members : List(Rooms.Member)
	members = [
		{ id: MockRooms.me, provider: "mock", name: "You", picture: Err(Missing), kind: Person, role: Owner, presence: Online },
		{ id: "ada", provider: "mock", name: "Ada", picture: Err(Missing), kind: Person, role: Admin, presence: Away },
		{ id: "scout", provider: "mock", name: "Scout", picture: Err(Missing), kind: Agent({ owner: Ok(MockRooms.me) }), role: Member, presence: Online },
		{ id: "patch", provider: "mock", name: "Patch", picture: Err(Missing), kind: Agent({ owner: Ok("ada") }), role: Member, presence: Online },
	]

	## A room's members: everyone, but releases has only Ada.
	members_of : Str -> List(Rooms.Member)
	members_of = |room_id| if (room_id == "releases") MockRooms.members.keep_if(|member| member.id == "ada") else MockRooms.members

	## What a room holds when the daemon starts: in general, a question to
	## Scout with its answer in a thread and a reaction; in ideas, a post
	## with a reply; in releases, an announcement.
	seed : Str -> List(Rooms.Event)
	seed = |room_id| {
		at = |minute| "2026-01-01T09:0${minute.to_str()}:00.000Z"
		said = |id, author, text, minute, place, mentions| Posted(Rooms.message({ id, room_id, author, text, time: at(minute), place, mentions }))
		match room_id {
			"general" => {
				thread = Reply({ root: "general-1", parent: "general-1" })
				[
					said("general-1", "ada", "@Scout why does logging in send me back to /login?", 0, TopLevel, ["scout"]),
					said("general-2", "scout", "The redirect target is hard-coded in `src/Auth.roc`. I can fix it in a worktree.", 1, thread, ["ada"]),
					Threaded({ root: "general-1", replies: 1, last_reply: Ok(at(1)), participants: ["scout"] }),
					Reacted({ id: "general-2", emoji: "+", by: "ada", added: Bool.True }),
					said("general-3", MockRooms.me, "Morning! The CI fix lands today.", 2, TopLevel, []),
				]
			}
			"ideas" => [
				said("ideas-1", "ada", "**Voice notes in rooms.** Dictate a message as you can in a chat.", 0, TopLevel, []),
				said("ideas-2", "patch", "The voice.v1 dictation already gives text; a room's composer could take it as the chat's does.", 3, Reply({ root: "ideas-1", parent: "ideas-1" }), []),
				Threaded({ root: "ideas-1", replies: 1, last_reply: Ok(at(3)), participants: ["patch"] }),
			]
			"releases" => [said("releases-1", "ada", "liton 0.1 is out.", 0, TopLevel, [])]
			_ => []
		}
	}

	## What follows sending `text` to `place` in a room whose messages are
	## `posted`, at `at` (ms since the epoch), its Posted the entry numbered
	## `next`: the message, the thread's new summary if it replies, and for
	## each agent it mentions, by id or as `@Name`, the agent typing and then
	## answering in the message's thread. Or why not.
	on_send : { room : Rooms.Room, posted : List(Rooms.Message), text : Str, place : Rooms.Place, mentions : List(Str), next : U64, at : I64 } -> Try({ message_id : Str, scheduled : List(Scheduled) }, Str)
	on_send = |{ room, posted, text, place, mentions, next, at }| {
		root = match place {
			TopLevel => Ok("")
			Reply(replied) if posted.any(|known| known.id == replied.root and known.place == TopLevel) and posted.any(|known| known.id == replied.parent) => Ok(replied.root)
			Reply(_) => Err("no message to reply to")
		}
		match root {
			_ if !room.joined => Err("join #${room.name} first")
			_ if text.trim().is_empty() => Err("a message needs text")
			_ if room.kind == Announce => Err("only Ada announces in #${room.name}")
			Err(why) => Err(why)
			Ok(root_id) => {
				id : U64 -> Str
				id = |sequence| "${room.id}-${sequence.to_str()}"
				time : U64 -> Str
				time = |delay_ms| Chat.timestamp(at + delay_ms.to_i64_wrap())
				sent = Rooms.message({ id: id(next), room_id: room.id, author: MockRooms.me, text, time: time(0), place, mentions })
				thread_root = if (root_id.is_empty()) sent.id else root_id
				summary = |so_far| Threaded(Rooms.thread(so_far, thread_root))
				mentioned = MockRooms.members.keep_if(
					|member|
						match member.kind {
							Agent(_) => mentions.contains(member.id) or text.with_ascii_lowercased().contains("@${member.name.with_ascii_lowercased()}")
							Person => Bool.False
						},
				)
				own = [{ delay_ms: 0, event: Posted(sent) }].concat(if (root_id.is_empty()) [] else [{ delay_ms: 0, event: summary(posted.append(sent)) }])
				answered = mentioned.map_with_index(|agent, index| (agent, index)).fold(
					{ scheduled: own, so_far: posted.append(sent) },
					|walked, (agent, index)| {
						delay_ms = 1_500 + index * 1_500
						reply = Rooms.message({ id: id(next + walked.scheduled.len() + 1), room_id: room.id, author: agent.id, text: "On it: \"${text}\"", time: time(delay_ms), place: Reply({ root: thread_root, parent: sent.id }), mentions: [MockRooms.me] })
						so_far = walked.so_far.append(reply)
						typing = { delay_ms: 300 + index * 1_500, event: Typing({ member: agent.id, place: reply.place }) }
						{ scheduled: walked.scheduled.concat([typing, { delay_ms, event: Posted(reply) }, { delay_ms, event: summary(so_far) }]), so_far }
					},
				)
				Ok({ message_id: sent.id, scheduled: answered.scheduled })
			}
		}
	}

	## What follows reacting (or taking a reaction back) with `emoji` to a
	## message among `posted`: the reaction, unless it changes nothing. Or why
	## not.
	on_react : Rooms.Room, List(Rooms.Message), { message_id : Str, emoji : Str, added : Bool } -> Try(List(Scheduled), Str)
	on_react = |room, posted, { message_id, emoji, added }|
		match posted.find_first(|known| known.id == message_id) {
			_ if !room.joined => Err("join #${room.name} first")
			Err(_) => Err("no message ${message_id} in #${room.name}")
			Ok(message) => {
				had = message.reactions.any(|reaction| reaction.emoji == emoji and reaction.by.contains(MockRooms.me))
				Ok(if (had == added) [] else [{ delay_ms: 0, event: Reacted({ id: message_id, emoji, by: MockRooms.me, added }) }])
			}
		}
}

general : Rooms.Room
general = MockRooms.rooms.first() ?? Rooms.room({ id: "", provider: "", name: "", kind: Channel })

posted_in : Str -> List(Rooms.Message)
posted_in = |room_id| Rooms.messages(MockRooms.seed(room_id).map_with_index(|event, index| { sequence: index.to_u64() + 1, event }))

# Each mock room has its members and a script; each thread's summary is what its replies make.
expect MockRooms.rooms.all(|room| !MockRooms.members_of(room.id).is_empty() and !MockRooms.seed(room.id).is_empty())
expect MockRooms.rooms.any(|room| room.kind == Forum)
expect {
	posted = posted_in("general")
	Rooms.threads(MockRooms.seed("general").map_with_index(|event, index| { sequence: index.to_u64() + 1, event })) == [Rooms.thread(posted, "general-1")]
}

# Mentioning Scout, a message gets its typing and then its answer in the message's thread.
expect {
	sent = MockRooms.on_send({ room: general, posted: posted_in("general"), text: "@scout run the tests", place: TopLevel, mentions: [], next: 6, at: 0 })
	match sent {
		Ok({ message_id, scheduled }) =>
			message_id == "general-6"
				and scheduled.map(
					|item| match item.event {
						Posted(message) => "${message.id} by ${message.author}"
						Typing({ member, .. }) => "${member} types"
						Threaded({ root, replies, .. }) => "${root} has ${replies.to_str()}"
						_ => "other"
					},
				)
					== ["general-6 by you", "scout types", "general-8 by scout", "general-6 has 1"]
		Err(_) => Bool.False
	}
}

expect {
	refused = |room, place| MockRooms.on_send({ room, posted: posted_in(room.id), text: "Hi", place, mentions: [], next: 9, at: 0 }).map_ok(|sent| sent.message_id)
	refused({ ..general, joined: Bool.False }, TopLevel) == Err("join #general first")
		and refused(general, Reply({ root: "general-2", parent: "general-2" })) == Err("no message to reply to")
		and refused(general, Reply({ root: "general-1", parent: "general-2" })) == Ok("general-9")
}

expect {
	posted = posted_in("general")
	MockRooms.on_react(general, posted, { message_id: "general-2", emoji: "+", added: Bool.True }).map_ok(|scheduled| scheduled.len()) == Ok(1)
		and MockRooms.on_react(general, posted, { message_id: "general-2", emoji: "+", added: Bool.False }) == Ok([])
		and MockRooms.on_react(general, posted, { message_id: "nope", emoji: "+", added: Bool.True }).is_err()
}

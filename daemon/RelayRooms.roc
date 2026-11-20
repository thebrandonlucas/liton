import cap.Chat
import cap.Rooms
import Nostr
import NostrRooms

## The relay's rooms as `rooms.v1` shows them, provider `relay`: a NIP-29
## group as a room, its members by their profiles, and its events as a
## room's entries, messages (kind 9) with their NIP-10 threads, reactions
## (7), edits (40003, as Buzz's) and deletions (5 by their authors, 9005 by
## an admin). A deletion (5) marked `["k", "7"]` whose `e` names a message
## takes back its author's reaction with the emoji its content holds, as a
## client knows the message and the emoji, not the reaction's id.
RelayRooms := [].{

	## The provider the relay's rooms are named by.
	provider : Str
	provider = "relay"

	## The room `kept` as `me`, a pubkey or "" for no one, sees it, last
	## posted in at `updated`.
	room : NostrRooms.Room, Try(Str, [Missing]), Str -> Rooms.Room
	room = |kept, updated, me| {
		kind =
			match kept.kind {
				"forum" => Forum
				"dm" => Direct
				"announce" => Announce
				_ => Channel
			}
		{
			..Rooms.room({ id: kept.id, provider: RelayRooms.provider, name: kept.name, kind }),
			topic: if (kept.about == "") Err(Missing) else Ok(kept.about),
			private: kept.private,
			joined: kept.members.contains(me),
			updated,
			me: if (me == "") Err(Missing) else Ok(me),
		}
	}

	## The members of `kept`, named as their latest profiles (kind 0,
	## NIP-24's `bot` an agent) among `profiles` say, else by their key.
	members : NostrRooms.Room, List(Nostr.Event) -> List(Rooms.Member)
	members = |kept, profiles|
		kept.members.map(
			|pubkey| {
				content = profiles.keep_if(|profile| profile.pubkey == pubkey).last().map_ok(|profile| profile.content) ?? ""
				said : Try({ name : Try(Str, [Missing]), display_name : Try(Str, [Missing]), picture : Try(Str, [Missing]), bot : Try(Bool, [Missing]) }, _)
				said = Json.parse(content)
				named = |profile| match profile.display_name {
					Ok(shown) if shown != "" => shown
					_ => profile.name ?? ""
				}
				name = said.map_ok(named) ?? ""
				{
					id: pubkey,
					provider: RelayRooms.provider,
					name: if (name == "") Str.from_utf8_lossy(pubkey.to_utf8().take_first(8)) else name,
					picture: said.map_ok(|profile| profile.picture).map_err(|_| Missing) ?? Err(Missing),
					kind: if (said.map_ok(|profile| profile.bot == Ok(Bool.True)) ?? Bool.False) Agent({ owner: Err(Missing) }) else Person,
					role: if (kept.admins.contains(pubkey)) Admin else Member,
					presence: Unknown,
				}
			},
		)

	## A room's entries from its events, each with its place in the order
	## they arrived: an event at place `seq` gives entries `seq * 8` on, a
	## reply its thread's summary after it.
	entries : List({ seq : U64, event : Nostr.Event }) -> List(Rooms.Entry)
	entries = |arrived| {
		start = { posted: [], reactions: [], entries: [] }
		done = arrived.fold(start, |so_far, { seq, event }| RelayRooms.step(so_far, seq, event))
		done.entries
	}

	## What `event`, at place `seq`, adds to the room's entries so far.
	step : { posted : List(Rooms.Message), reactions : List({ id : Str, target : Str, emoji : Str, by : Str }), entries : List(Rooms.Entry) }, U64, Nostr.Event -> { posted : List(Rooms.Message), reactions : List({ id : Str, target : Str, emoji : Str, by : Str }), entries : List(Rooms.Entry) }
	step = |so_far, seq, event| {
		tagged = |name| event.tags.keep_if(|tag| tag.first() == Ok(name))
		named = |name| tagged(name).map(|tag| tag.get(1) ?? "")
		added = |events| {
			new_entries = events.map_with_index(|shown, index| { sequence: seq * 8 + index, event: shown })
			{ ..so_far, entries: so_far.entries.concat(new_entries) }
		}
		marked = |marker| tagged("e").find_first(|tag| tag.get(3) == Ok(marker)).map_ok(|tag| tag.get(1) ?? "")
		match event.kind {
			9 => {
				place =
					match (marked("root"), marked("reply")) {
						(Ok(root), Ok(parent)) => Reply({ root, parent })
						(Ok(root), Err(_)) => Reply({ root, parent: root })
						_ => TopLevel
					}
				message = Rooms.message({ id: event.id, room_id: Nostr.room(event), author: event.pubkey, text: event.content, time: Chat.timestamp(event.created_at.to_i64_wrap() * 1000), place, mentions: named("p") })
				posted = so_far.posted.append(message)
				match place {
					TopLevel => { ..added([Posted(message)]), posted }
					Reply({ root, .. }) => { ..added([Posted(message), Threaded(Rooms.thread(posted, root))]), posted }
				}
			}
			7 =>
				match named("e").last() {
					Ok(target) => {
						reaction = { id: event.id, target, emoji: event.content, by: event.pubkey }
						{ ..added([Reacted({ id: target, emoji: event.content, by: event.pubkey, added: Bool.True })]), reactions: so_far.reactions.append(reaction) }
					}
					Err(_) => so_far
				}
			40003 =>
				match named("e").first() {
					Ok(target) if so_far.posted.any(|known| known.id == target and known.author == event.pubkey) => added([Edited({ id: target, text: event.content })])
					_ => so_far
				}
			5 if event.tags.any(|tag| tag == ["k", "7"]) and event.content != "" =>
				match named("e").first() {
					Ok(target) if so_far.reactions.any(|reaction| reaction.target == target and reaction.emoji == event.content and reaction.by == event.pubkey) => {
						after = added([Reacted({ id: target, emoji: event.content, by: event.pubkey, added: Bool.False })])
						{ ..after, reactions: so_far.reactions.drop_if(|reaction| reaction.target == target and reaction.emoji == event.content and reaction.by == event.pubkey) }
					}
					_ => so_far
				}
			5 | 9005 => {
				by_author = event.kind == 5
				undone = named("e").keep_oks(
					|target|
						match so_far.reactions.find_first(|reaction| reaction.id == target and (!by_author or reaction.by == event.pubkey)) {
							Ok(reaction) => Ok(Reacted({ id: reaction.target, emoji: reaction.emoji, by: reaction.by, added: Bool.False }))
							Err(_) if so_far.posted.any(|known| known.id == target and (!by_author or known.author == event.pubkey)) => Ok(Deleted({ id: target }))
							Err(_) => Err(Unknown)
						},
				)
				{ ..added(undone), reactions: so_far.reactions.drop_if(|reaction| named("e").contains(reaction.id)) }
			}
			_ => so_far
		}
	}
}

expect {
	event = |id, pubkey, kind, content, tags| { id, pubkey, created_at: 1_700_000_000, kind, tags: [["h", "general"]].concat(tags), content, sig: "" }
	arrived = [
		event("m1", "ada", 9, "hi @bo", [["p", "bo"]]),
		event("r1", "bo", 9, "hello", [["e", "m1", "", "root"], ["e", "m1", "", "reply"]]),
		event("x1", "bo", 7, "+", [["e", "m1"]]),
		event("x2", "bo", 5, "", [["e", "x1"]]),
		event("e1", "ada", 40003, "hi again", [["e", "m1"]]),
		event("e2", "bo", 40003, "not mine", [["e", "m1"]]),
		event("d1", "ada", 9005, "", [["e", "r1"]]),
	].map_with_index(|shown, index| { seq: index + 1, event: shown })
	shown = RelayRooms.entries(arrived)
	messages = Rooms.messages(shown)
	(
		messages.map(|message| (message.id, message.text, message.deleted)),
		messages.first().map_ok(|first| (first.time, first.mentions, first.reactions)),
		Rooms.threads(shown).map(|thread| (thread.root, thread.replies)),
		shown.map(|entry| entry.sequence),
	)
		== (
			[("m1", "hi again", Bool.False), ("r1", "", Bool.True)],
			Ok(("2023-11-14T22:13:20.000Z", ["bo"], [])),
			[("m1", 1)],
			[8, 16, 17, 24, 32, 40, 56],
		)
}
expect {
	kept = { id: "general", name: "General", about: "", kind: "announce", open: Bool.False, private: Bool.False, deleted: Bool.False, admins: ["ada"], members: ["ada", "bo"] }
	profiles = [{ id: "p1", pubkey: "bo", created_at: 0, kind: 0, tags: [], content: "{\"name\":\"bo\",\"display_name\":\"Bo\",\"bot\":true}", sig: "" }]
	members = RelayRooms.members(kept, profiles)
	shown = RelayRooms.room(kept, Err(Missing), "bo")
	(members.map(|member| (member.name, member.kind, member.role)), shown.kind, shown.joined, shown.me)
		== ([("ada", Person, Admin), ("Bo", Agent({ owner: Err(Missing) }), Member)], Announce, Bool.True, Ok("bo"))
}
expect {
	event = |id, pubkey, kind, content, tags| { id, pubkey, created_at: 0, kind, tags: [["h", "general"]].concat(tags), content, sig: "" }
	arrived = [event("m1", "ada", 9, "hi", []), event("x1", "bo", 7, "+", [["e", "m1"]]), event("x2", "ada", 5, "+", [["e", "m1"], ["k", "7"]]), event("x3", "bo", 5, "+", [["e", "m1"], ["k", "7"]])]
	shown = RelayRooms.entries(arrived.map_with_index(|given, index| { seq: index + 1, event: given }))
	(Rooms.messages(shown).map(|message| message.reactions), shown.len()) == ([[]], 3)
}

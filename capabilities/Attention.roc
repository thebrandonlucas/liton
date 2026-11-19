## `attention.v1`: an inbox of agents' sessions, one item per session, what
## needs you first and then the latest. The daemon derives it from chat.v1.
## Settling or snoozing an item sets it aside until its `signature` changes,
## as it does when something new happens, or, for a snooze, until the time
## runs out. An item is unread once it changes after the user saw it.
import Chat

Attention := [].{

	## How urgent an item is, in this order.
	State : [NeedsYou, Failed, Working, Done, Idle]

	## A request as chat.v1 has it, with its body and choices, if any.
	Permission : Chat.Permission

	## `summary` is the agent's last message, or why it failed, when the daemon
	## has the timeline. A NeedsYou item's `permissions` are the requests no answer
	## follows yet. `updated` is when its session last changed, as a time such
	## as 2026-01-01T09:00:00.000Z: as its provider tells, else when the daemon
	## saw it change. `unread`: it changed since the user saw it (`Seen`) and
	## its agent isn't working.
	Item : {
		session_id : Str,
		provider : Str,
		title : Str,
		agent : Str,
		state : State,
		summary : Str,
		permissions : List(Permission),
		signature : Str,
		updated : Str,
		unread : Bool,
		set_aside : [No, Settled, Snoozed],
	}

	## `Seen` marks each session seen as its item was `updated`; marked seen
	## through "", it is unread again.
	Request : [
		ListItems,
		Settle({ session_id : Str, signature : Str }),
		Snooze({ session_id : Str, signature : Str, minutes : U32 }),
		Unsettle({ session_id : Str }),
		Seen(List(Mark)),
	]

	## That a session was seen as its item was `updated` at `through`.
	Mark : { session_id : Str, through : Str }

	## What a request answers: the items for `ListItems`, else whether the
	## daemon took it.
	Response : [Items(List(Item)), Accepted, Rejected(Str)]

	## A settle or snooze as the daemon stores it: an item with `signature` is
	## set aside until `snoozed_until` (in ms since the epoch), or for good when
	## it is 0, a settle.
	Aside : { session_id : Str, signature : Str, snoozed_until : I64 }

	## The states, most urgent first, the order the inbox groups items in.
	ranks : List(State)
	ranks = [NeedsYou, Failed, Working, Done, Idle]

	## A session's item, from its status and the timeline the daemon has of it.
	item : Chat.Session, List(Chat.Entry) -> Item
	item = |session, timeline| {
		state =
			match session.status {
				AwaitingPermission => NeedsYou
				Failed(_) => Failed
				Running => Working
				Finished => Done
				Idle => Idle
			}
		pending = Chat.pending_permissions(timeline)
		permissions = timeline.keep_oks(
			|entry|
				match entry.event {
					PermissionRequested(asked) if pending.contains(asked.request_id) => Ok(asked)
					_ => Err(Answered)
				},
		)
		said = timeline.keep_oks(
			|entry|
				match entry.event {
					AgentMessage({ text }) => Ok(text)
					_ => Err(NotSaid)
				},
		)
		failure = match session.status {
			Failed(reason) => reason
			_ => ""
		}
		last = timeline.last().map_ok(|entry| entry.sequence.to_str()) ?? "0"
		{
			session_id: session.id,
			provider: session.provider,
			title: session.title,
			agent: session.agent,
			state,
			summary: said.last() ?? failure,
			permissions: if (state == NeedsYou) permissions else [],
			signature: Str.join_with([Str.inspect(state), last].concat(pending), " "),
			updated: session.updated ?? "",
			unread: Bool.False,
			set_aside: No,
		}
	}

	## Whether a stored settle or snooze still sets its item aside at `now`:
	## its item is the same as when it was set aside, and a snooze has time left.
	holds : Aside, List(Item), I64 -> Bool
	holds = |aside, items, now|
		items.any(|shown| shown.session_id == aside.session_id and shown.signature == aside.signature) and (aside.snoozed_until == 0 or aside.snoozed_until > now)

	## The items, what needs you first and then the latest, each set aside by a
	## stored settle or snooze that holds, and unread unless `marks` saw it as
	## it is (or its agent is working). Items as recent rank by state.
	ranked : List(Item), List(Aside), List(Mark), I64 -> List(Item)
	ranked = |items, asides, marks, now| {
		marked = |shown| {
			set_aside =
				match asides.find_first(|aside| aside.session_id == shown.session_id and Attention.holds(aside, items, now)) {
					Ok(aside) => if (aside.snoozed_until == 0) Settled else Snoozed
					Err(NotFound) => No
				}
			{ ..shown, set_aside, unread: shown.state != Working and marks.find_first(|mark| mark.session_id == shown.session_id).map_ok(|mark| mark.through) != Ok(shown.updated) }
		}
		rank = |shown| Attention.ranks.find_first_index(|state| state == shown.state) ?? 0
		order = |left, right| if (left > right) Before else if (left < right) After else Same
		newest = |left, right| [order(if (left.state == NeedsYou) 1 else 0, if (right.state == NeedsYou) 1 else 0), order(Attention.recency(left.updated), Attention.recency(right.updated)), order(rank(right), rank(left))].find_first(|ordered| ordered != Same) ?? Same
		items.sort_with(newest).map(marked)
	}

	## A time such as `updated` as a number that orders times: its first 17
	## digits, to the millisecond, 0 for none.
	recency : Str -> U64
	recency = |time| {
		digits = time.to_utf8().keep_if(|byte| byte >= '0' and byte <= '9').take_first(17)
		digits.concat(List.repeat('0', 17 - digits.len())).fold(0, |number, digit| number * 10 + (digit - '0').to_u64())
	}
}

session : Chat.Status -> Chat.Session
session = |status| Chat.session({ id: "s1", provider: "mock", agent: "claude", title: "Fix tests", status })

asked : Chat.Entry
asked = { sequence: 3, event: PermissionRequested(Chat.permission({ request_id: "p1", tool: "bash", description: "rm -rf build" })) }

# What needs you first, then the latest; as recent, by state.
expect {
	at = |shown, updated| { ..shown, updated: Ok(updated) }
	items = [Attention.item(session(Idle), []), Attention.item({ ..session(Running), id: "s2" }, []), Attention.item({ ..session(AwaitingPermission), id: "s3" }, [asked]), Attention.item({ ..session(Failed("context limit")), id: "s4" }, [])]
	timed = [Attention.item(at(session(Finished), "2026-01-02T00:00:00.000Z"), []), Attention.item(at({ ..session(Failed("")), id: "s2" }, "2026-01-03T00:00:00Z"), []), Attention.item(at({ ..session(AwaitingPermission), id: "s3" }, "2026-01-01T00:00:00.000Z"), [])]
	Attention.ranked(items, [], [], 0).map(|shown| (shown.session_id, shown.state, shown.summary)) == [("s3", NeedsYou, ""), ("s4", Failed, "context limit"), ("s2", Working, ""), ("s1", Idle, "")]
		and Attention.ranked(timed, [], [], 0).map(|shown| shown.session_id) == ["s3", "s2", "s1"]
}

# Unread until seen as it is, and again once it changes; never while working.
expect {
	done = { ..Attention.item(session(Finished), []), updated: "2026-01-01T00:00:00.000Z" }
	unread = |shown, marks| Attention.ranked([shown], [], marks, 0).map(|ranked| ranked.unread)
	seen = [{ session_id: "s1", through: done.updated }]
	unread(done, []) == [Bool.True] and unread(done, seen) == [Bool.False] and unread({ ..done, updated: "2026-01-01T00:00:01.000Z" }, seen) == [Bool.True] and unread({ ..done, state: Working, updated: "2026-01-02T00:00:00.000Z" }, seen) == [Bool.False]
}

expect {
	said = { sequence: 2, event: AgentMessage({ text: "Fixed it." }) }
	shown = Attention.item(session(AwaitingPermission), [said, asked])
	shown.summary == "Fixed it." and shown.permissions == [Chat.permission({ request_id: "p1", tool: "bash", description: "rm -rf build" })]
}

# Settled, an item stays aside until something new happens to it.
expect {
	waiting = Attention.item(session(AwaitingPermission), [asked])
	answered = Attention.item(session(Running), [asked, { sequence: 4, event: PermissionAnswered({ request_id: "p1", allowed: Bool.True, choice: Err(Missing) }) }])
	settled = [{ session_id: "s1", signature: waiting.signature, snoozed_until: 0 }]
	Attention.ranked([waiting], settled, [], 5).map(|shown| shown.set_aside) == [Settled] and Attention.ranked([answered], settled, [], 5).map(|shown| shown.set_aside) == [No]
}

# Snoozed, an item comes back when the snooze runs out.
expect {
	done = Attention.item(session(Finished), [])
	snoozed = [{ session_id: "s1", signature: done.signature, snoozed_until: 1000 }]
	Attention.ranked([done], snoozed, [], 999).map(|shown| shown.set_aside) == [Snoozed] and Attention.ranked([done], snoozed, [], 1000).map(|shown| shown.set_aside) == [No]
}

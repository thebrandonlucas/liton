## `attention.v1`: what needs you, one item per session, ranked. The daemon
## derives it from chat.v1. Settling or snoozing an item sets it aside until
## its `signature` changes, as it does when something new happens, or, for a
## snooze, until the time runs out.
import Chat

Attention := [].{

	## Ranked in this order.
	State : [NeedsYou, Failed, Working, Done, Idle]

	Permission : { request_id : Str, tool : Str, description : Str }

	## `summary` is the agent's last message, or why it failed, when the daemon
	## has the timeline. A NeedsYou item's `permissions` are the requests no answer
	## follows yet.
	Item : {
		session_id : Str,
		provider : Str,
		title : Str,
		agent : Str,
		state : State,
		summary : Str,
		permissions : List(Permission),
		signature : Str,
		set_aside : [No, Settled, Snoozed],
	}

	Request : [
		ListItems,
		Settle({ session_id : Str, signature : Str }),
		Snooze({ session_id : Str, signature : Str, minutes : U32 }),
		Unsettle({ session_id : Str }),
	]

	Response : [Items(List(Item)), Accepted, Rejected(Str)]

	## A settle or snooze as the daemon stores it: an item with `signature` is
	## set aside until `snoozed_until` (in ms since the epoch), or for good when
	## it is 0, a settle.
	Aside : { session_id : Str, signature : Str, snoozed_until : I64 }

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
			set_aside: No,
		}
	}

	## Whether a stored settle or snooze still sets its item aside at `now`:
	## its item is the same as when it was set aside, and a snooze has time left.
	holds : Aside, List(Item), I64 -> Bool
	holds = |aside, items, now|
		items.any(|shown| shown.session_id == aside.session_id and shown.signature == aside.signature) and (aside.snoozed_until == 0 or aside.snoozed_until > now)

	## The items ranked, each set aside by a stored settle or snooze that holds.
	ranked : List(Item), List(Aside), I64 -> List(Item)
	ranked = |items, asides, now| {
		set_aside = |shown|
			match asides.find_first(|aside| aside.session_id == shown.session_id and Attention.holds(aside, items, now)) {
				Ok(aside) => { ..shown, set_aside: if (aside.snoozed_until == 0) Settled else Snoozed }
				Err(NotFound) => shown
			}
		Attention.ranks.join_map(|state| items.keep_if(|shown| shown.state == state)).map(set_aside)
	}
}

session : Chat.Status -> Chat.Session
session = |status| { id: "s1", provider: "mock", agent: "claude", title: "Fix tests", status }

asked : Chat.Entry
asked = { sequence: 3, event: PermissionRequested({ request_id: "p1", tool: "bash", description: "rm -rf build" }) }

expect {
	items = [Attention.item(session(Idle), []), Attention.item({ ..session(Running), id: "s2" }, []), Attention.item({ ..session(AwaitingPermission), id: "s3" }, [asked]), Attention.item({ ..session(Failed("context limit")), id: "s4" }, [])]
	Attention.ranked(items, [], 0).map(|shown| (shown.session_id, shown.state, shown.summary)) == [("s3", NeedsYou, ""), ("s4", Failed, "context limit"), ("s2", Working, ""), ("s1", Idle, "")]
}

expect {
	said = { sequence: 2, event: AgentMessage({ text: "Fixed it." }) }
	shown = Attention.item(session(AwaitingPermission), [said, asked])
	shown.summary == "Fixed it." and shown.permissions == [{ request_id: "p1", tool: "bash", description: "rm -rf build" }]
}

# Settled, an item stays aside until something new happens to it.
expect {
	waiting = Attention.item(session(AwaitingPermission), [asked])
	answered = Attention.item(session(Running), [asked, { sequence: 4, event: PermissionAnswered({ request_id: "p1", allowed: Bool.True }) }])
	settled = [{ session_id: "s1", signature: waiting.signature, snoozed_until: 0 }]
	Attention.ranked([waiting], settled, 5).map(|shown| shown.set_aside) == [Settled] and Attention.ranked([answered], settled, 5).map(|shown| shown.set_aside) == [No]
}

# Snoozed, an item comes back when the snooze runs out.
expect {
	done = Attention.item(session(Finished), [])
	snoozed = [{ session_id: "s1", signature: done.signature, snoozed_until: 1000 }]
	Attention.ranked([done], snoozed, 999).map(|shown| shown.set_aside) == [Snoozed] and Attention.ranked([done], snoozed, 1000).map(|shown| shown.set_aside) == [No]
}

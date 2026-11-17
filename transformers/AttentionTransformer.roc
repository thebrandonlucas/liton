## attention.v1 as a transformer: an item for each of chat.v1's sessions,
## from its timeline, ranked (see Attention). Its state (`Kept`) is the
## settles and snoozes that still hold, the sessions seen, and when it saw
## each session change whose provider doesn't say.
import cap.Attention
import cap.Capability
import cap.Chat
import cap.Protocol
import Transformer

AttentionTransformer := [].{
	part : Transformer.Part
	part = {
		id: "attention",
		name: "Attention",
		offers: { capability: Capability.attention_v1, patterns: ["items"] },
		uses: [{ capability: "chat.v1", topic: "sessions" }],
		follows: |inputs| sessions(inputs).map(|session| { capability: "chat.v1", topic: "timeline/${session.id}" }),
		derive: |inputs, stored, now| {
			{ kept, items } = attended(inputs, stored, now)
			{ state: Json.to_str(kept), topics: [{ topic: "items", events: [Items(items)] }] }
		},
		call,
	}

	## `observed`: when the daemon first saw a session as its `signature` is,
	## in ms since the epoch, for each whose provider tells no `updated`.
	Kept : { asides : List(Attention.Aside), seen : List(Attention.Mark), observed : List({ session_id : Str, signature : Str, at : I64 }) }
}

sessions : List(Transformer.Input) -> List(Chat.Session)
sessions = |inputs|
	inputs.join_map(
		|input|
			input.events.join_map(
				|event|
					match event {
						Sessions(listed) if input.topic == "sessions" => listed
						_ => []
					},
			),
	)

## The items ranked, and what the transformer keeps of them: the settles and
## snoozes that still hold, and the marks and times of the sessions listed. A
## state stored when it kept only settles and snoozes is those.
attended : List(Transformer.Input), Str, I64 -> { kept : AttentionTransformer.Kept, items : List(Attention.Item) }
attended = |inputs, stored, now| {
	timeline = |session_id|
		inputs.find_first(|input| input.topic == "timeline/${session_id}").map_ok(|input| input.events).ok_or([]).keep_oks(
			|event|
				match event {
					Entry(entry) => Ok(entry)
					_ => Err(NotEntry)
				},
		)
	listed = sessions(inputs).map(|session| Attention.item(session, timeline(session.id)))
	decoded : Try(AttentionTransformer.Kept, _)
	decoded = Json.parse(stored)
	asides_only : Try(List(Attention.Aside), _)
	asides_only = Json.parse(stored)
	prior = decoded ?? { asides: asides_only ?? [], seen: [], observed: [] }
	observed = listed.keep_if(|shown| shown.updated.is_empty()).map(|shown| prior.observed.find_first(|old| old.session_id == shown.session_id and old.signature == shown.signature) ?? { session_id: shown.session_id, signature: shown.signature, at: now })
	items = listed.map(|shown| observed.find_first(|old| old.session_id == shown.session_id).map_ok(|old| { ..shown, updated: Chat.timestamp(old.at) }) ?? shown)
	kept = { asides: prior.asides.keep_if(|aside| Attention.holds(aside, items, now)), seen: prior.seen.keep_if(|mark| items.any(|shown| shown.session_id == mark.session_id)), observed }
	{ kept, items: Attention.ranked(items, kept.asides, kept.seen, now) }
}

## Answers ListItems, sets an item aside or back, and marks sessions seen
## (those it doesn't list, it ignores).
call : List(Transformer.Input), Str, Str, I64 -> { state : Str, answer : Str }
call = |inputs, stored, body, now| {
	{ kept, items } = attended(inputs, stored, now)
	decoded : Try(Protocol.Call(Attention.Request), _)
	decoded = Json.parse(body)
	set_aside = |aside|
		if items.any(|shown| shown.session_id == aside.session_id) {
			({ ..kept, asides: kept.asides.drop_if(|old| old.session_id == aside.session_id).append(aside) }, Ok(Accepted))
		} else {
			(kept, Err({ code: NotFound, message: "no session ${aside.session_id}" }))
		}
	answered : (AttentionTransformer.Kept, Protocol.Answer(Attention.Response))
	answered =
		match decoded.map_ok(|asked| asked.request) {
			Ok(ListItems) => (kept, Ok(Items(items)))
			Ok(Settle({ session_id, signature })) => set_aside({ session_id, signature, snoozed_until: 0 })
			Ok(Snooze({ session_id, signature, minutes })) => set_aside({ session_id, signature, snoozed_until: now + minutes.to_i64() * 60_000 })
			Ok(Unsettle({ session_id })) => ({ ..kept, asides: kept.asides.drop_if(|old| old.session_id == session_id) }, Ok(Accepted))
			Ok(Seen(marks)) => {
				listed = marks.keep_if(|mark| items.any(|shown| shown.session_id == mark.session_id))
				({ ..kept, seen: kept.seen.drop_if(|old| listed.any(|mark| mark.session_id == old.session_id)).concat(listed) }, Ok(Accepted))
			}
			Err(_) => (kept, Err({ code: BadRequest, message: "expected a attention.v1 request" }))
		}
	{ state: Json.to_str(answered.0), answer: Json.to_str(answered.1) }
}

fixture : List(Transformer.Input)
fixture = [
	{ capability: "chat.v1", topic: "sessions", events: [Sessions([Chat.session({ id: "s1", provider: "mock", agent: "claude", title: "Fix", status: AwaitingPermission }), Chat.session({ id: "s2", provider: "mock", agent: "claude", title: "Done", status: Finished })])] },
	{ capability: "chat.v1", topic: "timeline/s1", events: [Entry({ sequence: 1, event: PermissionRequested(Chat.permission({ request_id: "p1", tool: "bash", description: "rm -rf build" })) })] },
]

called : Str, Str -> { state : Str, answer : Str }
called = |stored, request| (AttentionTransformer.part.call)(fixture, stored, "{\"capability\":\"attention.v1\",\"request\":${request}}", 0)

expect (AttentionTransformer.part.follows)(fixture) == [{ capability: "chat.v1", topic: "timeline/s1" }, { capability: "chat.v1", topic: "timeline/s2" }]

# Each session's item, from its timeline, ranked, unread, and changed when
# the daemon saw it change, as the mock's sessions tell no time.
expect {
	derived = (AttentionTransformer.part.derive)(fixture, "", 5000)
	again = (AttentionTransformer.part.derive)(fixture, derived.state, 9000)
	match (derived.topics, again.topics) {
		([{ topic: "items", events: [Items([first, second])] }], [{ topic: "items", events: [Items([_, later])] }]) => first.session_id == "s1" and first.permissions.len() == 1 and second.state == Done and second.unread and later.updated == "1970-01-01T00:00:05.000Z" and derived.state.starts_with("{\"asides\":[],")
		_ => Bool.False
	}
}

# A settle holds until something new happens, and is forgotten after.
expect {
	settled = called("", "{\"Settle\":{\"session_id\":\"s2\",\"signature\":\"Done 0\"}}")
	listed = called(settled.state, "\"ListItems\"")
	stale = (AttentionTransformer.part.derive)(fixture, Json.to_str([{ session_id: "s2", signature: "Done 9", snoozed_until: 0 }]), 0)
	settled.answer == "{\"Ok\":\"Accepted\"}" and listed.answer.contains("\"set_aside\":\"Settled\"") and stale.state.starts_with("{\"asides\":[],")
}

expect {
	snoozed = called("", "{\"Snooze\":{\"session_id\":\"s2\",\"signature\":\"Done 0\",\"minutes\":2}}")
	snoozed.state.starts_with("{\"asides\":[{\"session_id\":\"s2\",\"signature\":\"Done 0\",\"snoozed_until\":120000}],") and called(snoozed.state, "{\"Unsettle\":{\"session_id\":\"s2\"}}").state.starts_with("{\"asides\":[],")
}

# Seen marks an item read until it changes; seen through "", it is unread.
expect {
	seen = called("", "{\"Seen\":[{\"session_id\":\"s2\",\"through\":\"1970-01-01T00:00:00.000Z\"},{\"session_id\":\"nope\",\"through\":\"\"}]}")
	listed = called(seen.state, "\"ListItems\"").answer
	unseen = called(seen.state, "{\"Seen\":[{\"session_id\":\"s2\",\"through\":\"\"}]}")
	seen.answer == "{\"Ok\":\"Accepted\"}" and listed.contains("\"title\":\"Done\",\"unread\":false") and listed.contains("\"title\":\"Fix\",\"unread\":true") and !seen.state.contains("nope") and called(unseen.state, "\"ListItems\"").answer.contains("\"title\":\"Done\",\"unread\":true")
}

expect called("", "{\"Settle\":{\"session_id\":\"nope\",\"signature\":\"x\"}}").answer == "{\"Err\":{\"code\":\"NotFound\",\"message\":\"no session nope\"}}"
expect called("", "\"Bogus\"").answer == "{\"Err\":{\"code\":\"BadRequest\",\"message\":\"expected a attention.v1 request\"}}"

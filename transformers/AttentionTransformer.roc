## attention.v1 as a transformer: an item for each of chat.v1's sessions,
## from its timeline, ranked (see Attention). Its state is the settles and
## snoozes that still hold.
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
			{ asides, items } = attended(inputs, stored, now)
			{ state: Json.to_str(asides), topics: [{ topic: "items", events: [Items(items)] }] }
		},
		call,
	}
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

## The items ranked, and the settles and snoozes that still set one aside.
attended : List(Transformer.Input), Str, I64 -> { asides : List(Attention.Aside), items : List(Attention.Item) }
attended = |inputs, stored, now| {
	timeline = |session_id|
		inputs.find_first(|input| input.topic == "timeline/${session_id}").map_ok(|input| input.events).ok_or([]).keep_oks(
			|event|
				match event {
					Entry(entry) => Ok(entry)
					_ => Err(NotEntry)
				},
		)
	items = sessions(inputs).map(|session| Attention.item(session, timeline(session.id)))
	decoded : Try(List(Attention.Aside), _)
	decoded = Json.parse(stored)
	asides = (decoded ?? []).keep_if(|aside| Attention.holds(aside, items, now))
	{ asides, items: Attention.ranked(items, asides, now) }
}

## Answers ListItems, and sets an item aside or back.
call : List(Transformer.Input), Str, Str, I64 -> { state : Str, answer : Str }
call = |inputs, stored, body, now| {
	{ asides, items } = attended(inputs, stored, now)
	decoded : Try(Protocol.Call(Attention.Request), _)
	decoded = Json.parse(body)
	set_aside = |aside|
		if items.any(|shown| shown.session_id == aside.session_id) {
			(asides.drop_if(|kept| kept.session_id == aside.session_id).append(aside), Ok(Accepted))
		} else {
			(asides, Err({ code: NotFound, message: "no session ${aside.session_id}" }))
		}
	answered : (List(Attention.Aside), Protocol.Answer(Attention.Response))
	answered =
		match decoded.map_ok(|asked| asked.request) {
			Ok(ListItems) => (asides, Ok(Items(items)))
			Ok(Settle({ session_id, signature })) => set_aside({ session_id, signature, snoozed_until: 0 })
			Ok(Snooze({ session_id, signature, minutes })) => set_aside({ session_id, signature, snoozed_until: now + minutes.to_i64() * 60_000 })
			Ok(Unsettle({ session_id })) => (asides.drop_if(|kept| kept.session_id == session_id), Ok(Accepted))
			Err(_) => (asides, Err({ code: BadRequest, message: "expected a attention.v1 request" }))
		}
	{ state: Json.to_str(answered.0), answer: Json.to_str(answered.1) }
}

fixture : List(Transformer.Input)
fixture = [
	{ capability: "chat.v1", topic: "sessions", events: [Sessions([Chat.session({ id: "s1", provider: "mock", agent: "claude", title: "Fix", status: AwaitingPermission }), Chat.session({ id: "s2", provider: "mock", agent: "claude", title: "Done", status: Finished })])] },
	{ capability: "chat.v1", topic: "timeline/s1", events: [Entry({ sequence: 1, event: PermissionRequested({ request_id: "p1", tool: "bash", description: "rm -rf build" }) })] },
]

called : Str, Str -> { state : Str, answer : Str }
called = |stored, request| (AttentionTransformer.part.call)(fixture, stored, "{\"capability\":\"attention.v1\",\"request\":${request}}", 0)

expect (AttentionTransformer.part.follows)(fixture) == [{ capability: "chat.v1", topic: "timeline/s1" }, { capability: "chat.v1", topic: "timeline/s2" }]

# Each session's item, from its timeline, ranked.
expect {
	derived = (AttentionTransformer.part.derive)(fixture, "", 0)
	match derived.topics {
		[{ topic: "items", events: [Items([first, second])] }] => first.session_id == "s1" and first.permissions.len() == 1 and second.state == Done and derived.state == "[]"
		_ => Bool.False
	}
}

# A settle holds until something new happens, and is forgotten after.
expect {
	settled = called("", "{\"Settle\":{\"session_id\":\"s2\",\"signature\":\"Done 0\"}}")
	listed = called(settled.state, "\"ListItems\"")
	stale = (AttentionTransformer.part.derive)(fixture, Json.to_str([{ session_id: "s2", signature: "Done 9", snoozed_until: 0 }]), 0)
	settled.answer == "{\"Ok\":\"Accepted\"}" and listed.answer.contains("\"set_aside\":\"Settled\"") and stale.state == "[]"
}

expect {
	snoozed = called("", "{\"Snooze\":{\"session_id\":\"s2\",\"signature\":\"Done 0\",\"minutes\":2}}")
	snoozed.state == "[{\"session_id\":\"s2\",\"signature\":\"Done 0\",\"snoozed_until\":120000}]" and called(snoozed.state, "{\"Unsettle\":{\"session_id\":\"s2\"}}").state == "[]"
}

expect called("", "{\"Settle\":{\"session_id\":\"nope\",\"signature\":\"x\"}}").answer == "{\"Err\":{\"code\":\"NotFound\",\"message\":\"no session nope\"}}"
expect called("", "\"Bogus\"").answer == "{\"Err\":{\"code\":\"BadRequest\",\"message\":\"expected a attention.v1 request\"}}"

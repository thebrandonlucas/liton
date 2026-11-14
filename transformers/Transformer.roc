## A transformer: a part that uses topics of capabilities and offers a
## capability derived from them, as attention.v1 is from chat.v1. Pure: the
## daemon feeds it the latest events of the topics it uses with the state it
## stored, and serves what it derives like any capability. Another fits the
## same way, such as an @mention router offering a room's chat.v1 from its
## sessions' timelines.
import cap.Capability
import cap.Manifest
import cap.Protocol

Transformer := [].{

	## A topic of a capability, such as chat.v1's `sessions`.
	Topic : { capability : Str, topic : Str }

	## A topic's events as the daemon has them: a snapshot topic's value, or
	## a timeline's entries from the first.
	Input : { capability : Str, topic : Str, events : List(Protocol.Event) }

	## An offered topic's events: a snapshot topic's one, or a timeline's
	## entries from the first.
	Derived : { topic : Str, events : List(Protocol.Event) }

	## `uses`: the topics it follows, which the daemon watches for it as it
	## does for a client's poll. `follows`: the further topics its inputs lead
	## to, such as each session's timeline, read from what the daemon keeps,
	## asking nothing upstream. `derive`: from its inputs, its state (its own
	## JSON, "" at first) and the time in ms since the epoch, its new state
	## and the events of each topic it offers. `call`: from its inputs, state,
	## a call's body and the time, its new state and the JSON of the call's
	## `Protocol.Answer`.
	Part : {
		id : Str,
		name : Str,
		offers : Manifest.Topics,
		uses : List(Topic),
		follows : List(Input) -> List(Topic),
		derive : List(Input), Str, I64 -> { state : Str, topics : List(Derived) },
		call : List(Input), Str, Str, I64 -> { state : Str, answer : Str },
	}

	## How the manifest lists a part: the capabilities of the topics it uses.
	declared : Part -> Manifest.Transformer
	declared = |{ id, name, offers, uses, .. }| {
		used = uses.keep_oks(|topic| Capability.from_str(topic.capability))
		{ id, name, offers: offers.capability, uses: used.fold([], |so_far, capability| if (so_far.contains(capability)) so_far else so_far.append(capability)) }
	}

	## The parts offered, given the capabilities providers offer: in order,
	## each whose topics are of capabilities offered by providers or the parts
	## before it, so a part may use another's output but never its own.
	offered : List(Part), List(Capability.Id) -> List(Part)
	offered = |parts, provided|
		parts.fold(
			{ capabilities: provided, kept: [] },
			|so_far, part|
				if Transformer.declared(part).uses.all(|used| so_far.capabilities.contains(used)) {
					{ capabilities: so_far.capabilities.append(part.offers.capability), kept: so_far.kept.append(part) }
				} else {
					so_far
				},
		).kept

	## The update of an offered topic a client wants, from what its part
	## derived: a timeline's entries after the cursor, or a snapshot.
	update : List(Derived), Protocol.Wanted -> Protocol.Update
	update = |derived, wanted|
		match (derived.find_first(|offered_topic| offered_topic.topic == wanted.topic).map_ok(|offered_topic| offered_topic.events), Protocol.sequence(wanted)) {
			(Err(_), _) => Protocol.failed(wanted, { code: NotFound, message: "${wanted.capability} has no topic ${wanted.topic}" })
			(Ok([Entry(_), ..] as events), Ok(after)) => Protocol.appended(
				wanted,
				events.keep_oks(
					|event| match event {
						Entry(entry) if entry.sequence > after => Ok(entry)
						_ => Err(Seen)
					},
				),
			)
			(Ok([Entry(_), ..]), Err(error)) => Protocol.failed(wanted, error)
			(Ok(events), _) => events.last().map_ok(|event| Protocol.snapshot(wanted, event)) ?? Protocol.appended(wanted, [])
		}
}

counted : Transformer.Part
counted = {
	id: "counted",
	name: "Counted",
	offers: { capability: { name: "counted", version: 1 }, patterns: ["count", "log"] },
	uses: [{ capability: "chat.v1", topic: "sessions" }, { capability: "chat.v1", topic: "importable" }],
	follows: |_| [],
	derive: |inputs, state, _| { state, topics: [{ topic: "count", events: [Sessions([])] }, { topic: "log", events: inputs.map_with_index(|_, index| Entry({ sequence: index.to_u64() + 1, event: StatusChanged(Idle) })) }] },
	call: |_, state, _, _| { state, answer: "" },
}

expect Transformer.declared(counted) == { id: "counted", name: "Counted", offers: { name: "counted", version: 1 }, uses: [Capability.chat_v1] }

# A part is offered once what it uses is, from providers or a part before it.
expect {
	recounted = { ..counted, id: "recounted", uses: [{ capability: "counted.v1", topic: "count" }] }
	ids = |parts| parts.map(|part| part.id)
	ids(Transformer.offered([counted, recounted], [Capability.chat_v1])) == ["counted", "recounted"] and ids(Transformer.offered([recounted, counted], [Capability.chat_v1])) == ["counted"] and ids(Transformer.offered([counted], [])) == []
}

# An offered snapshot is answered by fingerprint, a timeline after its cursor.
expect {
	derived = (counted.derive)([{ capability: "chat.v1", topic: "sessions", events: [] }, { capability: "chat.v1", topic: "importable", events: [] }], "", 0).topics
	count = Transformer.update(derived, { capability: "counted.v1", topic: "count", after: "" })
	log = Transformer.update(derived, { capability: "counted.v1", topic: "log", after: "1" })
	count.events == [Sessions([])] and Transformer.update(derived, { capability: "counted.v1", topic: "count", after: count.cursor }).events == [] and log.cursor == "2" and log.events.len() == 1
}

expect Transformer.update([], { capability: "counted.v1", topic: "nothing", after: "" }).error.map_ok(|error| error.code) == Ok(NotFound)

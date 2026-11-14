## needs-you.v1, a transformer of attention.v1's output, to show transformers
## compose: the items that need you. The daemon offers it only when
## LITON_TRANSFORMERS names it.
import cap.Attention
import cap.Chat
import cap.Protocol
import AttentionTransformer
import Transformer

NeedsYou := [].{
	part : Transformer.Part
	part = {
		id: "needs-you",
		name: "Needs you",
		offers: { capability: { name: "needs-you", version: 1 }, patterns: ["items"] },
		uses: [{ capability: "attention.v1", topic: "items" }],
		follows: |_| [],
		derive: |inputs, state, _| { state, topics: [{ topic: "items", events: [Items(needing(inputs))] }] },
		call: |inputs, state, body, _| {
			decoded : Try(Protocol.Call([ListItems]), _)
			decoded = Json.parse(body)
			answer : Protocol.Answer(Attention.Response)
			answer = match decoded {
				Ok(_) => Ok(Items(needing(inputs)))
				Err(_) => Err({ code: BadRequest, message: "expected a needs-you.v1 request" })
			}
			{ state, answer: Json.to_str(answer) }
		},
	}
}

needing : List(Transformer.Input) -> List(Attention.Item)
needing = |inputs|
	inputs.join_map(|input| input.events).join_map(
		|event|
			match event {
				Items(items) => items.keep_if(|item| item.state == NeedsYou)
				_ => []
			},
	)

# needs-you.v1 composes with attention.v1: its items are attention's that need you.
expect {
	sessions = [Chat.session({ id: "s1", provider: "mock", agent: "claude", title: "Fix", status: AwaitingPermission }), Chat.session({ id: "s2", provider: "mock", agent: "claude", title: "Done", status: Finished })]
	attention = (AttentionTransformer.part.derive)([{ capability: "chat.v1", topic: "sessions", events: [Sessions(sessions)] }], "", 0).topics.map(|derived| { capability: "attention.v1", topic: derived.topic, events: derived.events })
	match (NeedsYou.part.derive)(attention, "", 0).topics {
		[{ topic: "items", events: [Items([item])] }] => item.session_id == "s1" and (NeedsYou.part.call)(attention, "", "{\"capability\":\"needs-you.v1\",\"request\":\"ListItems\"}", 0).answer.contains("\"session_id\":\"s1\"")
		_ => Bool.False
	}
}

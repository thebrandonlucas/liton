## `voice.v1`: dictation, speech to text. A client posts an utterance's audio
## in numbered chunks to the daemon's audio route (docs/protocol.md), each
## acknowledged, then asks for its transcript with `Finish`.
Voice := [].{
	Purpose : [Dictation, Conversation({ session_id : Str })]

	## `Begin` checks the engine is up before the client records. `Finish`
	## transcribes chunks 0 to `last_seq`. `Cancel` drops the chunks held.
	Request : [Begin({ utterance_id : Str, purpose : Purpose }), Finish({ utterance_id : Str, last_seq : U64 }), Cancel({ utterance_id : Str })]

	## `Missing`: the chunks from `from_seq` aren't held; send them and
	## `Finish` again.
	Response : [Accepted, Transcript({ text : Str }), Missing({ from_seq : U64 })]

	## What the audio route answers: the highest seq held with every one
	## before it, left out until chunk 0 is.
	Acked : { acked : Try(U64, [Missing]) }

	Engine : [Ready, Loading, Down(Str)]

	## The `status` topic's value.
	Status : { stt : Engine }

	## The most chunks an utterance has, 5 minutes of 1 s chunks.
	max_chunks : U64
	max_chunks = 300

	## The utterance and seq the audio route's path after
	## `/liton/v1/audio/voice.v1/` names. An utterance id is 1 to 64 letters,
	## digits, `-` and `_`.
	chunk : Str -> Try({ utterance_id : Str, seq : U64 }, Str)
	chunk = |rest|
		match rest.split_on("/") {
			[utterance_id, seq_text] if Voice.is_utterance_id(utterance_id) =>
				match U64.from_str(seq_text) {
					Ok(seq) if seq < Voice.max_chunks => Ok({ utterance_id, seq })
					_ => Err("a chunk's seq is 0 to ${(Voice.max_chunks - 1).to_str()}, not ${seq_text}")
				}
			_ => Err("expected /liton/v1/audio/voice.v1/<utterance_id>/<seq>, an utterance id of 1 to 64 letters, digits, - and _")
		}

	is_utterance_id : Str -> Bool
	is_utterance_id = |text| {
		bytes = text.to_utf8()
		!bytes.is_empty() and bytes.len() <= 64 and bytes.all(|byte| (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or (byte >= '0' and byte <= '9') or byte == '-' or byte == '_')
	}

	## How many chunks from 0 are held, of the seqs held in order.
	contiguous : List(U64) -> U64
	contiguous = |held| held.fold(0, |count, seq| if (seq == count) count + 1 else count)

	acked : List(U64) -> Acked
	acked = |held| {
		count = Voice.contiguous(held)
		{ acked: if (count == 0) Err(Missing) else Ok(count - 1) }
	}
}

expect Voice.chunk("u-1_A/0") == Ok({ utterance_id: "u-1_A", seq: 0 }) and Voice.chunk("u1/299") == Ok({ utterance_id: "u1", seq: 299 })
expect ["u1/300", "u1/-1", "u1/x", "u1", "u1/2/3", "/0", "u.1/0", "${Str.repeat("a", 65)}/0"].all(|rest| Voice.chunk(rest).is_err())
expect Voice.acked([]) == { acked: Err(Missing) } and Voice.acked([1, 2]) == { acked: Err(Missing) }
expect Voice.acked([0, 1, 3]) == { acked: Ok(1) } and Voice.acked([0, 1, 2]) == { acked: Ok(2) }
expect Json.to_str(Voice.acked([0])) == "{\"acked\":0}" and Json.to_str(Voice.acked([])) == "{}"

expect {
	decoded : Try(Voice.Request, _)
	decoded = Json.parse("{\"Begin\":{\"utterance_id\":\"u1\",\"purpose\":\"Dictation\"}}")
	decoded == Ok(Begin({ utterance_id: "u1", purpose: Dictation }))
}

expect {
	status : Voice.Status
	status = { stt: Down("no engine") }
	Json.to_str(status) == "{\"stt\":{\"Down\":\"no engine\"}}"
}

## The `liton` command line's pure part: what its arguments ask for, and the
## JSON it sends the daemon and prints (docs/protocol.md, The CLI).
import cap.Protocol

Cli := [].{

	## What the arguments ask for. A call given no request, or `-`, reads it
	## from stdin.
	Command : [Help, Usage(Str), Manifest, Setup(Str), Call({ capability : Str, request : [Given(Str), Stdin] }), Watch({ topics : List(Protocol.Wanted), interval : U64 })]

	usage : Str
	usage =
		\\Usage:
		\\  liton manifest
		\\  liton call <capability> [<request JSON>|-]
		\\  liton watch <capability> <topic> [--after <cursor>] [<capability> <topic> ...] [--interval <ms>]
		\\  liton setup [<Litonfile.roc or its directory>]
		\\  liton help
		\\
		\\Speaks liton's capability protocol to the daemon at LITON_URL (default
		\\http://127.0.0.1:8095) and prints JSON, one value per line. `call` reads
		\\its request from stdin when given none or `-`, and exits 1 when the
		\\answer is an error. `watch` polls its topics every --interval
		\\milliseconds (default 1000) and prints each new event, wrapped with its
		\\capability and topic when it follows several, until interrupted. `setup`
		\\runs a Litonfile (default ./Litonfile.roc) with roc and writes the setup it
		\\prints to liton.setup.json.

	parse : List(Str) -> Command
	parse = |arguments|
		match arguments {
			["help"] | ["--help"] | ["-h"] => Help
			["manifest"] => Manifest
			["setup"] => Setup("Litonfile.roc")
			["setup", path] => Setup(if (path.ends_with(".roc")) path else "${path.drop_suffix("/")}/Litonfile.roc")
			["call", capability] | ["call", capability, "-"] => Call({ capability, request: Stdin })
			["call", capability, request] => Call({ capability, request: Given(request) })
			["watch", .. as rest] => watched(rest, { topics: [], interval: 1000 })
			[] => Usage("no command given")
			[command, ..] => Usage("unknown command or arguments for ${command}")
		}

	## The body of a call: `request` is the request's JSON as given.
	call_body : Str, Str -> Str
	call_body = |capability, request| "{\"capability\":${Json.to_str(capability)},\"request\":${request}}"

	## The error a call's answer holds, as a one-line message, if it is one.
	failure : Str -> Try(Str, [Answered])
	failure = |answer| {
		decoded : Try(Protocol.Answer({}), _)
		decoded = Json.parse(answer)
		match decoded {
			Ok(Err(error)) => Ok(described(error))
			_ => Err(Answered)
		}
	}

	## What a poll's answer prints, one line per event, wrapped with its
	## capability and topic when several are followed; the topics to poll next,
	## after their new cursors; and why any topic can't be followed.
	polled : List(Protocol.Wanted), Protocol.Polled -> { lines : List(Str), next : List(Protocol.Wanted), failures : List(Str) }
	polled = |wanted, { topics }| {
		wrapped = wanted.len() > 1
		line = |{ capability, topic, .. }, event| if (wrapped) Json.to_str({ capability, topic, event }) else Json.to_str(event)
		{
			lines: topics.join_map(|update| update.events.map(|event| line(update, event))),
			next: topics.map(|{ capability, topic, cursor, .. }| { capability, topic, after: cursor }),
			failures: topics.keep_oks(|update| update.error.map_ok(|error| "${update.capability} ${update.topic}: ${described(error)}")),
		}
	}
}

described : Protocol.Error -> Str
described = |{ code, message }| "${Str.inspect(code)}: ${message}"

watched : List(Str), { topics : List(Protocol.Wanted), interval : U64 } -> Cli.Command
watched = |rest, so_far|
	match rest {
		[] if so_far.topics.is_empty() => Usage("watch needs a capability and a topic")
		[] => Watch(so_far)
		["--interval", milliseconds, .. as after] =>
			match U64.from_str(milliseconds) {
				Ok(interval) if interval > 0 => watched(after, { ..so_far, interval })
				_ => Usage("--interval takes milliseconds, such as 1000")
			}
		["--after", cursor, .. as after] =>
			match so_far.topics.last() {
				Ok(last) => watched(after, { ..so_far, topics: so_far.topics.drop_last(1).append({ ..last, after: cursor }) })
				Err(_) => Usage("--after follows the topic it resumes")
			}
		[option, ..] if option.starts_with("-") => Usage("unknown option ${option}")
		[capability, topic, .. as after] => watched(after, { ..so_far, topics: so_far.topics.append({ capability, topic, after: "" }) })
		_ => Usage("watch takes a capability and a topic in pairs")
	}

expect Cli.parse(["call", "chat.v1"]) == Call({ capability: "chat.v1", request: Stdin }) and Cli.parse(["call", "chat.v1", "-"]) == Call({ capability: "chat.v1", request: Stdin })
expect Cli.parse(["call", "chat.v1", "\"ListSessions\""]) == Call({ capability: "chat.v1", request: Given("\"ListSessions\"") })
expect [[], ["manifest", "x"], ["call"], ["watch"], ["watch", "chat.v1"], ["watch", "--after", "3"], ["watch", "chat.v1", "sessions", "--interval", "0"], ["watch", "chat.v1", "sessions", "--every"]].all(
	|arguments| match Cli.parse(arguments) {
		Usage(_) => Bool.True
		_ => Bool.False
	},
)

expect {
	parsed = Cli.parse(["watch", "chat.v1", "timeline/s1", "--after", "41", "attention.v1", "items", "--interval", "250"])
	parsed == Watch({ topics: [{ capability: "chat.v1", topic: "timeline/s1", after: "41" }, { capability: "attention.v1", topic: "items", after: "" }], interval: 250 })
}

expect Cli.parse(["setup"]) == Setup("Litonfile.roc") and Cli.parse(["setup", "team/"]) == Setup("team/Litonfile.roc") and Cli.parse(["setup", "team/Mine.roc"]) == Setup("team/Mine.roc")

expect Cli.call_body("chat.v1", "\"ListSessions\"") == "{\"capability\":\"chat.v1\",\"request\":\"ListSessions\"}"
expect Cli.failure("{\"Err\":{\"code\":\"NotFound\",\"message\":\"no session s2\"}}") == Ok("NotFound: no session s2")
expect Cli.failure("{\"Ok\":\"Accepted\"}") == Err(Answered) and Cli.failure("{\"Ok\":{\"Sessions\":[]}}") == Err(Answered)

# One topic prints its events alone; several wrap each with its topic.
expect {
	wanted = [{ capability: "chat.v1", topic: "timeline/s1", after: "" }]
	answer = { topics: [Protocol.appended(wanted.first() ?? { capability: "", topic: "", after: "" }, [{ sequence: 1, event: StatusChanged(Running) }])] }
	alone = Cli.polled(wanted, answer)
	alone.lines == ["{\"Entry\":{\"event\":{\"StatusChanged\":\"Running\"},\"sequence\":1}}"] and alone.next == [{ capability: "chat.v1", topic: "timeline/s1", after: "1" }] and alone.failures == []
}

expect {
	wanted = [{ capability: "chat.v1", topic: "timeline/s1", after: "" }, { capability: "chat.v2", topic: "sessions", after: "" }]
	answer = { topics: [Protocol.appended({ capability: "chat.v1", topic: "timeline/s1", after: "" }, [{ sequence: 1, event: StatusChanged(Running) }]), Protocol.failed({ capability: "chat.v2", topic: "sessions", after: "" }, { code: Unsupported, message: "the daemon offers no chat.v2" })] }
	several = Cli.polled(wanted, answer)
	several.lines == ["{\"capability\":\"chat.v1\",\"event\":{\"Entry\":{\"event\":{\"StatusChanged\":\"Running\"},\"sequence\":1}},\"topic\":\"timeline/s1\"}"] and several.failures == ["chat.v2 sessions: Unsupported: the daemon offers no chat.v2"]
}

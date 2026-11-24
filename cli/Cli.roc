## The `liton` command line's pure part: what its arguments ask for, and the
## JSON it sends the daemon and prints (docs/protocol.md, The CLI).
import cap.People
import cap.Protocol
import cap.Rooms

Cli := [].{

	## What the arguments ask for. A call given no request, or `-`, reads it
	## from stdin.
	Command : [Help, Usage(Str), Manifest, Setup(Str), Pair, Login(Str), Invite({ name : Str, role : Str, rooms : List(Str) }), CreateRoom({ name : Str, about : Str, kind : Rooms.Kind, private : Bool }), ListRooms, Call({ capability : Str, request : [Given(Str), Stdin] }), Watch({ topics : List(Protocol.Wanted), interval : U64 })]

	usage : Str
	usage =
		\\Usage:
		\\  liton manifest
		\\  liton call <capability> [<request JSON>|-]
		\\  liton watch <capability> <topic> [--after <cursor>] [<capability> <topic> ...] [--interval <ms>]
		\\  liton setup [<Litonfile.roc or its directory>]
		\\  liton pair
		\\  liton login <pairing code>
		\\  liton invite --role <role> [--rooms <room>,...] <name>
		\\  liton room create [--about <text>] [--type forum|direct|announce] [--private] <name>
		\\  liton room list
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
		\\
		\\`pair`, run on the daemon's machine, prints a pairing code for a new
		\\device of the box's owner, good once for 10 minutes, which it writes in
		\\the daemon's database at LITON_DB (default liton.db): its link makes the
		\\owner's passkey on a fresh box, or after they lost every one, and signs
		\\them in. `login` pairs this command line
		\\with the daemon by such a code, and keeps its token, readable by you
		\\alone, in $XDG_CONFIG_HOME/liton/tokens (default ~/.config). LITON_TOKEN,
		\\if set, is used in place of the token kept.
		\\
		\\`invite` asks the daemon, as an operator or admin, for an invite of the
		\\person or agent called <name> into <role> and its rooms (people.v1), and
		\\prints the link that redeems it, good once for 7 days.
		\\
		\\`room create` asks the daemon, as an operator or admin, to make a room of
		\\the box called <name>, a channel unless --type says otherwise (people.v1),
		\\and prints its id, which invites name. `room list` prints the box's
		\\rooms, one per line: id, name, kind and whether it is private.

	parse : List(Str) -> Command
	parse = |arguments|
		match arguments {
			["help"] | ["--help"] | ["-h"] => Help
			["manifest"] => Manifest
			["pair"] => Pair
			["login", code] => Login(code)
			["invite", .. as rest] => invited(rest, { name: "", role: "", rooms: [] })
			["room", "create", .. as rest] => room_created(rest, { name: "", about: "", kind: Channel, private: Bool.False })
			["room", "list"] => ListRooms
			["setup"] => Setup("Litonfile.roc")
			["setup", path] => Setup(if (path.ends_with(".roc")) path else "${path.drop_suffix("/")}/Litonfile.roc")
			["call", capability] | ["call", capability, "-"] => Call({ capability, request: Stdin })
			["call", capability, request] => Call({ capability, request: Given(request) })
			["watch", .. as rest] => watched(rest, { topics: [], interval: 1000 })
			[] => Usage("no command given")
			[command, ..] => Usage("unknown command or arguments for ${command}")
		}

	## The link to the UI at `daemon` that redeems the invite people.v1's
	## `answer` gives, or why it gives none.
	invite_link : Str, Str -> Try(Str, Str)
	invite_link = |daemon, answer| {
		decoded : Try(Protocol.Answer(People.Response), _)
		decoded = Json.parse(answer)
		match decoded {
			Ok(Ok(Invited({ secret, .. }))) => Ok("${daemon}/ui/index.html#invite=${secret}")
			Ok(Ok(Rejected(why))) => Err(why)
			Ok(Err(error)) => Err(described(error))
			_ => Err("the daemon's answer to an invite isn't one this liton reads")
		}
	}

	## The id of the room people.v1's `answer` to `CreateRoom` says it made,
	## or why it made none.
	created_room : Str -> Try(Str, Str)
	created_room = |answer| {
		decoded : Try(Protocol.Answer(People.Response), _)
		decoded = Json.parse(answer)
		match decoded {
			Ok(Ok(RoomCreated({ room_id }))) => Ok(room_id)
			Ok(Ok(Rejected(why))) => Err(why)
			Ok(Err(error)) => Err(described(error))
			_ => Err("the daemon's answer to a new room isn't one this liton reads")
		}
	}

	## The lines `room list` prints of rooms.v1's `answer` to `ListRooms`: each
	## of the box's rooms' id, name, kind and, if so, `private`, by tabs.
	room_lines : Str -> Try(List(Str), Str)
	room_lines = |answer| {
		decoded : Try(Protocol.Answer(Rooms.Response), _)
		decoded = Json.parse(answer)
		line = |room| Str.join_with([room.id, room.name, Str.inspect(room.kind)].concat(if (room.private) ["private"] else []), "\t")
		match decoded {
			Ok(Ok(Rooms(rooms))) => Ok(rooms.keep_if(|room| room.provider == "rooms").map(line))
			Ok(Err(error)) => Err(described(error))
			_ => Err("the daemon's answer to listing rooms isn't one this liton reads")
		}
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
	polled = |wanted, { topics, .. }| {
		wrapped = wanted.len() > 1
		line = |{ capability, topic, .. }, event| if (wrapped) Json.to_str({ capability, topic, event }) else Json.to_str(event)
		{
			lines: topics.join_map(|update| update.events.map(|event| line(update, event))),
			next: topics.map(|{ capability, topic, cursor, .. }| { capability, topic, after: cursor }),
			failures: topics.keep_oks(|update| update.error.map_ok(|error| "${update.capability} ${update.topic}: ${described(error)}")),
		}
	}

	## A pairing code of 8 `random` bytes, as the daemon's `Auth.code`
	## writes one: `ABCD-EFGH`, of 32 symbols without I, O, 0 or 1.
	pairing_code : List(U8) -> Str
	pairing_code = |random| {
		symbols = random.map(|byte| "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".to_utf8().get((byte % 32).to_u64()) ?? 'A')
		Str.from_utf8_lossy(symbols.take_first(4).append('-').concat(symbols.drop_first(4)))
	}

	## The token `kept`, the lines `<daemon URL> <token>` of the tokens file,
	## holds for `daemon`.
	kept_token : Str, Str -> Try(Str, [NoToken])
	kept_token = |kept, daemon| kept.split_on("\n").find_first(|line| line.starts_with("${daemon} ")).map_ok(|line| line.drop_prefix("${daemon} ").trim()).map_err(|_| NoToken)

	## The tokens file `kept`, with `token` for `daemon` in place of any
	## it held.
	with_token : Str, Str, Str -> Str
	with_token = |kept, daemon, token| Str.join_with(kept.split_on("\n").drop_if(|line| line.starts_with("${daemon} ") or line.trim() == "").append("${daemon} ${token}"), "\n").concat("\n")
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

invited : List(Str), { name : Str, role : Str, rooms : List(Str) } -> Cli.Command
invited = |rest, so_far|
	match rest {
		[] if so_far.role == "" => Usage("invite needs --role")
		[] if so_far.name == "" => Usage("invite needs the name of whom it is for")
		[] => Invite(so_far)
		["--role", role, .. as after] => invited(after, { ..so_far, role })
		["--rooms", rooms, .. as after] => invited(after, { ..so_far, rooms: rooms.split_on(",").map(|room| room.trim()).drop_if(|room| room == "") })
		[option, ..] if option.starts_with("-") => Usage("unknown option ${option}")
		[name, .. as after] if so_far.name == "" => invited(after, { ..so_far, name })
		_ => Usage("invite takes one name")
	}

expect Cli.parse(["invite", "--role", "staff", "--rooms", "dispatch, general", "Dana"]) == Invite({ name: "Dana", role: "staff", rooms: ["dispatch", "general"] }) and Cli.parse(["invite", "Dana"]) == Usage("invite needs --role") and Cli.parse(["invite", "--role", "staff"]) == Usage("invite needs the name of whom it is for")
expect Cli.invite_link("http://box:8095", "{\"Ok\":{\"Invited\":{\"id\":\"i1\",\"secret\":\"s3\"}}}") == Ok("http://box:8095/ui/index.html#invite=s3") and Cli.invite_link("x", "{\"Ok\":{\"Rejected\":\"the setup declares no role chef\"}}") == Err("the setup declares no role chef")

room_created : List(Str), { name : Str, about : Str, kind : Rooms.Kind, private : Bool } -> Cli.Command
room_created = |rest, so_far|
	match rest {
		[] if so_far.name == "" => Usage("room create needs the room's name")
		[] => CreateRoom(so_far)
		["--about", about, .. as after] => room_created(after, { ..so_far, about })
		["--type", "forum", .. as after] => room_created(after, { ..so_far, kind: Forum })
		["--type", "direct", .. as after] => room_created(after, { ..so_far, kind: Direct })
		["--type", "announce", .. as after] => room_created(after, { ..so_far, kind: Announce })
		["--type", ..] => Usage("--type is forum, direct or announce; a room is a channel without it")
		["--private", .. as after] => room_created(after, { ..so_far, private: Bool.True })
		[option, ..] if option.starts_with("-") => Usage("unknown option ${option}")
		[name, .. as after] if so_far.name == "" => room_created(after, { ..so_far, name })
		_ => Usage("room create takes one name; quote one of several words")
	}

expect Cli.parse(["room", "create", "--type", "forum", "--private", "--about", "Orders", "Front desk"]) == CreateRoom({ name: "Front desk", about: "Orders", kind: Forum, private: Bool.True }) and Cli.parse(["room", "create", "Dispatch"]) == CreateRoom({ name: "Dispatch", about: "", kind: Channel, private: Bool.False }) and Cli.parse(["room", "list"]) == ListRooms
expect [["room", "create"], ["room", "create", "--type", "stream", "x"], ["room", "create", "Front", "desk"], ["room"]].all(
	|arguments| match Cli.parse(arguments) {
		Usage(_) => Bool.True
		_ => Bool.False
	},
)
expect Cli.created_room("{\"Ok\":{\"RoomCreated\":{\"room_id\":\"front-desk\"}}}") == Ok("front-desk") and Cli.created_room("{\"Ok\":{\"Rejected\":\"duplicate: the room front-desk exists\"}}") == Err("duplicate: the room front-desk exists")
expect {
	rooms = [{ ..Rooms.room({ id: "front-desk", provider: "rooms", name: "Front desk", kind: Forum }), private: Bool.True }, Rooms.room({ id: "dispatch", provider: "rooms", name: "Dispatch", kind: Channel }), Rooms.room({ id: "m1", provider: "mock", name: "Mock", kind: Channel })]
	answer : Protocol.Answer(Rooms.Response)
	answer = Ok(Rooms(rooms))
	Cli.room_lines(Json.to_str(answer)) == Ok(["front-desk\tFront desk\tForum\tprivate", "dispatch\tDispatch\tChannel"])
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
	answer = { topics: [Protocol.appended(wanted.first() ?? { capability: "", topic: "", after: "" }, [{ sequence: 1, event: StatusChanged(Running) }])], refresh: Err(Missing) }
	alone = Cli.polled(wanted, answer)
	alone.lines == ["{\"Entry\":{\"event\":{\"StatusChanged\":\"Running\"},\"sequence\":1}}"] and alone.next == [{ capability: "chat.v1", topic: "timeline/s1", after: "1" }] and alone.failures == []
}

expect {
	wanted = [{ capability: "chat.v1", topic: "timeline/s1", after: "" }, { capability: "chat.v2", topic: "sessions", after: "" }]
	answer = { topics: [Protocol.appended({ capability: "chat.v1", topic: "timeline/s1", after: "" }, [{ sequence: 1, event: StatusChanged(Running) }]), Protocol.failed({ capability: "chat.v2", topic: "sessions", after: "" }, { code: Unsupported, message: "the daemon offers no chat.v2" })], refresh: Err(Missing) }
	several = Cli.polled(wanted, answer)
	several.lines == ["{\"capability\":\"chat.v1\",\"event\":{\"Entry\":{\"event\":{\"StatusChanged\":\"Running\"},\"sequence\":1}},\"topic\":\"timeline/s1\"}"] and several.failures == ["chat.v2 sessions: Unsupported: the daemon offers no chat.v2"]
}

expect Cli.parse(["pair"]) == Pair and Cli.parse(["login", "ABCD-EFGH"]) == Login("ABCD-EFGH")
expect Cli.pairing_code([0, 1, 2, 3, 31, 32, 255, 8]) == "ABCD-9A9J"
expect Cli.kept_token("http://a:1 x.y\nhttp://b:2 z.w\n", "http://b:2") == Ok("z.w") and Cli.kept_token("http://a:10 x.y\n", "http://a:1") == Err(NoToken)
expect Cli.with_token("http://a:1 x.y\nhttp://b:2 z.w\n", "http://a:1", "n.m") == "http://b:2 z.w\nhttp://a:1 n.m\n"

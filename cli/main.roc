## liton's command line: speaks the capability protocol (docs/protocol.md) to
## the daemon at LITON_URL and prints JSON, one value per line. Cli.roc decides
## what to send and print; this only asks the daemon, reads stdin, prints and
## sleeps, runs a Litonfile with roc to write the setup it prints, writes a
## pairing code in the daemon's database and keeps the token a pairing
## gives, sent with every request as `Authorization: Bearer`. Exits 1
## when a call answers an error, a topic can't be followed or a Litonfile
## gives no setup, and 2 on a usage error or when the daemon or roc can't be
## reached.
app [main!] {
	cap: "../capabilities/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	setup: "../setup/main.roc",
}

import pf.Cmd
import pf.Env
import pf.Http
import pf.OsStr
import pf.File
import pf.Path
import pf.Random
import pf.Sleep
import pf.Sqlite
import pf.Sqlite.Query
import pf.Utc
import pf.Stderr
import pf.Stdin
import pf.Stdout
import http.Method
import http.Request
import cap.People
import cap.Protocol
import setup.Setup
import Cli

main! : List(OsStr) => Try({}, _)
main! = |arguments| {
	daemon = (Env.var_str!("LITON_URL") ?? "http://127.0.0.1:8095").drop_suffix("/")
	tokens = tokens_file!()
	given_token = Env.var_str!("LITON_TOKEN") ?? ""
	token = if (given_token != "") given_token else Cli.kept_token(Str.from_utf8_lossy(Path.read_bytes!(tokens) ?? []), daemon) ?? ""
	asked! = |method, url, body| sent!(method, url, body, token)
	match Cli.parse(arguments.map(OsStr.display)) {
		Help => Stdout.line!(Cli.usage)
		Usage(problem) => failed!(2, "${problem}\n\n${Cli.usage}")
		Manifest => Stdout.line!(asked!(GET, "${daemon}/liton/v1/manifest", "")?)
		Pair => {
			database = Env.var_str!("LITON_DB") ?? "liton.db"
			match pairing_code!(database) {
				Ok(code) => Stdout.line!("${code}\n\nEnter it on the device to pair within 10 minutes, or open\n${daemon}/ui/index.html#pair=${code}")
				Err(problem) => failed!(2, problem)
			}
		}
		Login(code) => {
			answer = sent!(POST, "${daemon}/liton/v1/pair", Json.to_str({ code, name: "liton command line", token: Bool.True }), "")?
			paired : Try({ token : Str }, _)
			paired = Json.parse(answer)
			match paired {
				Ok({ token: given }) => {
					Path.create_all!(Path.parent(tokens) ?? tokens)?
					kept = Str.from_utf8_lossy(Path.read_bytes!(tokens) ?? [])
					# Written new, readable by its owner alone, then moved over the old.
					written = Path.unix("${Path.display(tokens)}.new")
					_ = Path.delete!(written)
					File.with_writer!(written, RequireNew, { create_permissions: OwnerOnly }, |writer| writer.write_utf8!(Cli.with_token(kept, daemon, given)))?
					Path.rename!(written, tokens)?
					Stdout.line!("Paired with ${daemon}.")
				}
				Err(_) => failed!(2, "the daemon's answer to pairing isn't one this liton reads")
			}
		}
		Invite({ name, role, rooms, agent }) => {
			request : People.Request
			request = Invite({ name, role, rooms, agent })
			answer = asked!(POST, "${daemon}/liton/v1/call", Json.to_str({ capability: "people.v1", request }))?
			match Cli.invite_link(daemon, answer) {
				Ok(link) if agent => Stdout.line!("${link}\n\nRedeem it for ${name}'s token, once, within 7 days: node examples/room-agent/agent.mjs join <link> <file>.")
				Ok(link) => Stdout.line!("${link}\n\nOpen it on ${name}'s device to make their passkey, once, within 7 days.")
				Err(why) => failed!(1, why)
			}
		}
		Relink(which) => {
			listing = asked!(POST, "${daemon}/liton/v1/poll", Json.to_str({ topics: [{ capability: "people.v1", topic: "people", after: "" }] }))?
			match Cli.relinked(listing, which) {
				Err(why) => failed!(1, why)
				Ok(people) => {
					for person in people {
						request : People.Request
						request = Relink({ person: person.id })
						answer = asked!(POST, "${daemon}/liton/v1/call", Json.to_str({ capability: "people.v1", request }))?
						match Cli.invite_link(daemon, answer) {
							Ok(link) => Stdout.line!("${person.name}\t${link}")?
							Err(why) => return failed!(1, "${person.name}: ${why}")
						}
					}
					Ok({})
				}
			}
		}
		CreateRoom(room) => {
			request : People.Request
			request = CreateRoom(room)
			answer = asked!(POST, "${daemon}/liton/v1/call", Json.to_str({ capability: "people.v1", request }))?
			match Cli.created_room(answer) {
				Ok(room_id) => Stdout.line!("${room_id}\n\nInvite into it with liton invite --role <role> --rooms ${room_id} <name>.")
				Err(why) => failed!(1, why)
			}
		}
		ListRooms => {
			answer = asked!(POST, "${daemon}/liton/v1/call", Cli.call_body("rooms.v1", "\"ListRooms\""))?
			match Cli.room_lines(answer) {
				Ok(lines) => {
					for line in lines {
						Stdout.line!(line)?
					}
					Ok({})
				}
				Err(why) => failed!(1, why)
			}
		}
		Setup(litonfile) => {
			printed = match Cmd.capture!("roc", [OsStr.from_str(litonfile)]) {
				Ok(text) => text
				Err(BadExitStatus(_)) => return failed!(1, "${litonfile} gave no setup")
				Err(problem) => return failed!(2, "can't run roc on ${litonfile}: ${Str.inspect(problem)}")
			}
			match Setup.from_json(printed.trim()) {
				Ok(setup) => Path.write_utf8!(Path.utf8("liton.setup.json"), "${Setup.to_json(setup)}\n")
				Err(Invalid) => failed!(1, "${litonfile} printed something other than a setup")
			}
		}
		Call({ capability, request }) => {
			given = match request {
				Given(text) => text
				Stdin => Str.from_utf8_lossy(Stdin.read_to_end!()?)
			}
			answer = asked!(POST, "${daemon}/liton/v1/call", Cli.call_body(capability, given))?
			Stdout.line!(answer)?
			match Cli.failure(answer) {
				Ok(message) => failed!(1, message)
				Err(Answered) => Ok({})
			}
		}
		Watch({ topics, interval }) => {
			var $wanted = topics
			while Bool.True {
				polled : Try(Protocol.Polled, _)
				polled = Json.parse(asked!(POST, "${daemon}/liton/v1/poll", Json.to_str({ topics: $wanted }))?)
				printed = match polled {
					Ok(answer) => Cli.polled($wanted, answer)
					Err(_) => return failed!(2, "the daemon's poll answer isn't one this liton reads")
				}
				for line in printed.lines {
					Stdout.line!(line)?
				}
				if !printed.failures.is_empty() {
					return failed!(1, Str.join_with(printed.failures, "\n"))
				}
				$wanted = printed.next
				Sleep.millis!(interval)?
			}
		}
	}
}

## A new pairing code, written in the daemon's database at `database`.
pairing_code! : Str => Try(Str, Str)
pairing_code! = |database| {
	if !(Path.is_file!(Path.unix(database)) ?? Bool.False) {
		return Err("no daemon's database at ${database}: run this on the daemon's machine, with LITON_DB set as the daemon's")
	}
	written = |outcome| outcome.map_err(|problem| "can't write a pairing code in ${database}: ${Str.inspect(problem)}")
	db = written(Sqlite.open!(Path.unix(database), { mode: ReadWrite }))?
	random = Random.seed_u64!().map_err(|problem| "can't get random bytes: ${Str.inspect(problem)}")?
	code = Cli.pairing_code([72057594037927936, 281474976710656, 1099511627776, 4294967296, 16777216, 65536, 256, 1].map(|power| (random // power).to_u8_wrap()))
	expires_at = (Utc.now!().to_millis_since_epoch() + 600_000).to_i64_wrap()
	written(db.execute!(Query.new("CREATE TABLE IF NOT EXISTS pairing_codes (code TEXT PRIMARY KEY, expires_at INTEGER NOT NULL);", [])))?
	written(db.execute!(Query.new("INSERT INTO pairing_codes (code, expires_at) VALUES (?, ?);", [String(code), Integer(expires_at)])))?
	Ok(code)
}

## The tokens file: $XDG_CONFIG_HOME/liton/tokens, by default under ~/.config.
tokens_file! : () => Path.Path
tokens_file! = || {
	config = Env.var_str!("XDG_CONFIG_HOME") ?? "${Env.var_str!("HOME") ?? "."}/.config"
	Path.unix("${config}/liton/tokens")
}

## The body the daemon answers `url` with, trimmed, asked with `token` if
## not "". A daemon that can't be reached or answers other than 200 exits 2.
sent! : Method, Str, Str, Str => Try(Str, _)
sent! = |method, url, body, token| {
	typed = Request.from_method(method).with_uri(url).add_header("Content-Type", "application/json").with_body(body.to_utf8())
	request = if (token == "") typed else typed.add_header("Authorization", "Bearer ${token}")
	match Http.send!(request, {}) {
		Ok(response) if response.status() == 200 => Ok(Str.from_utf8_lossy(response.body()).trim())
		Ok(response) if response.status() == 401 => failed!(2, "${url} answered 401: ${Str.from_utf8_lossy(response.body())}\nPair with `liton login <code>`.")
		Ok(response) => failed!(2, "${url} answered ${response.status().to_str()}: ${Str.from_utf8_lossy(response.body())}")
		Err(Interrupted) => Err(Interrupted)
		Err(HttpErr(Other(detail))) => failed!(2, "can't reach the daemon at ${url}: ${Str.from_utf8_lossy(detail)}")
		Err(problem) => failed!(2, "can't reach the daemon at ${url}: ${Str.inspect(problem)}")
	}
}

failed! : I32, Str => Try(_, _)
failed! = |code, message| {
	Stderr.line!("liton: ${message}")?
	Err(Exit(code))
}

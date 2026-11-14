## liton's command line: speaks the capability protocol (docs/protocol.md) to
## the daemon at LITON_URL and prints JSON, one value per line. Cli.roc decides
## what to send and print; this only asks the daemon, reads stdin, prints and
## sleeps, and runs a Litonfile with roc to write the setup it prints. Exits 1
## when a call answers an error, a topic can't be followed or a Litonfile
## gives no setup, and 2 on a usage error or when the daemon or roc can't be
## reached.
app [main!] {
	cap: "../capabilities/main.roc",
	http: "https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst",
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.0/2yhxoR7cZPSYbyUzPWULFw8AA6QEcdsgFNRmzu7pZbst.tar.zst",
	setup: "../setup/main.roc",
}

import pf.Cmd
import pf.Env
import pf.Http
import pf.OsStr
import pf.Path
import pf.Sleep
import pf.Stderr
import pf.Stdin
import pf.Stdout
import http.Method
import http.Request
import cap.Protocol
import setup.Setup
import Cli

main! : List(OsStr) => Try({}, _)
main! = |arguments| {
	daemon = (Env.var_str!("LITON_URL") ?? "http://127.0.0.1:8095").drop_suffix("/")
	match Cli.parse(arguments.map(OsStr.display)) {
		Help => Stdout.line!(Cli.usage)
		Usage(problem) => failed!(2, "${problem}\n\n${Cli.usage}")
		Manifest => Stdout.line!(asked!(GET, "${daemon}/liton/v1/manifest", "")?)
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

## The body the daemon answers `url` with, trimmed. A daemon that can't be
## reached or answers other than 200 exits 2.
asked! : Method, Str, Str => Try(Str, _)
asked! = |method, url, body| {
	request = Request.from_method(method).with_uri(url).add_header("Content-Type", "application/json").with_body(body.to_utf8())
	match Http.send!(request, {}) {
		Ok(response) if response.status() == 200 => Ok(Str.from_utf8_lossy(response.body()).trim())
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

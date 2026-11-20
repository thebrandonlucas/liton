## `hosts.v1`: the daemons liton's daemon connects to, Paseo's and other
## liton daemons', added, changed, disabled and removed while it runs. The
## daemon offers it itself. A host's password or token is written only: a
## client gives one to add or change a host, and no answer holds it.
Hosts := [].{

	## `Paseo`: a Paseo daemon, its target `host:port`, reached with its
	## password. `Liton`: another liton daemon, its target an http:// or
	## https:// URL, reached with the token it paired this daemon with.
	Kind : [Paseo, Liton]

	## `Connecting` until the daemon first hears from it, then `Online`, or
	## `Offline` when it can't be reached, or `Error` with why when it
	## answers but refuses, such as a wrong password. `Disabled` while it is
	## switched off.
	Status : [Connecting, Online, Offline, Error(Str), Disabled]

	## Where a host comes from: added by a client, or set by the daemon's
	## environment (PASEO_*, LITON_PROVIDERS) or its setup. One set so is set
	## again each start: it can be relabelled, disabled and enabled, but not
	## retargeted, given a new password or removed, which its setting does.
	Origin : [Added, Environment, Setup]

	## A host: its `name`, which names what it offers (`<name>/<id>`; the
	## Paseo host PASEO_* sets is `paseo`, and its ids are bare), its label
	## for people, the version its server tells and when it was last
	## online, as 2026-01-01T09:00:00.000Z, each left out until known.
	Host : { name : Str, kind : Kind, target : Str, label : Str, enabled : Bool, status : Status, version : Try(Str, [Missing]), last_online : Try(Str, [Missing]), origin : Origin }

	## A host to add: its password or token, `password`, is written only.
	New : { name : Str, kind : Kind, target : Str, label : Str, password : Str }

	## A change of a host: each field left out stays as it was.
	Change : { name : Str, target : Try(Str, [Missing]), label : Try(Str, [Missing]), password : Try(Str, [Missing]) }

	## `ListHosts` answers them all. `AddHost` connects to a new one,
	## `UpdateHost` changes one, `RemoveHost` disconnects and forgets one,
	## and `SetEnabled` switches one on or off, each at once, without a
	## restart, and answering `Accepted` or `Rejected` with why.
	Request : [ListHosts, AddHost(New), UpdateHost(Change), RemoveHost({ name : Str }), SetEnabled({ name : Str, enabled : Bool })]

	Response : [Hosts(List(Host)), Accepted, Rejected(Str)]

	## A host's name: 1 to 32 letters, digits, `-` and `_`, so `<name>/`
	## never starts a local id.
	name_problem : Str -> Try({}, Str)
	name_problem = |name| {
		allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_".to_utf8()
		if name == "" or name.count_utf8_bytes() > 32 or !name.to_utf8().all(|byte| allowed.contains(byte)) {
			Err("a host's name is 1 to 32 letters, digits, - and _, not \"${name}\"")
		} else {
			Ok({})
		}
	}

	## Whether `target` is where a host of `kind` can be: for Paseo, a host
	## name, IPv4 or bracketed IPv6 address and a port, `host:port`; for
	## liton, an http:// or https:// URL of a host and maybe a port and path,
	## without a user, query or fragment.
	target_problem : Kind, Str -> Try({}, Str)
	target_problem = |kind, target|
		match kind {
			Paseo => {
				match target.split_last(":") {
					Ok({ before, after }) if address_fits(before) and port_fits(after) => Ok({})
					_ => Err("a Paseo host is host:port, such as 127.0.0.1:6767, not \"${target}\"")
				}
			}
			Liton => if (url_fits(target)) Ok({}) else Err("a liton host is an http:// or https:// URL, such as https://liton.example, not \"${target}\"")
		}

	## Why `new` can't be added beside the hosts `known`, if it can't.
	added_problem : List(Host), New -> Try({}, Str)
	added_problem = |known, new| {
		Hosts.name_problem(new.name)?
		Hosts.target_problem(new.kind, new.target)?
		if known.any(|host| host.name == new.name) {
			Err("there is a host called ${new.name} already")
		} else if new.kind == Paseo and new.password == "" {
			Err("a Paseo host needs its password")
		} else {
			Ok({})
		}
	}

	## Why `change` can't be made to `host`, if it can't: a host set by the
	## environment or setup keeps its target and password.
	changed_problem : Host, Change -> Try({}, Str)
	changed_problem = |host, change| {
		set_elsewhere = host.origin != Added and (change.target.is_ok() or change.password.is_ok())
		if set_elsewhere {
			Err("${host.name} is set by the daemon's ${origin_name(host.origin)}: change its target or password there")
		} else {
			match change.target {
				Ok(target) => Hosts.target_problem(host.kind, target)
				Err(Missing) => Ok({})
			}
		}
	}

	## Why `host` can't be removed, if it can't.
	removed_problem : Host -> Try({}, Str)
	removed_problem = |host|
		if (host.origin == Added) Ok({}) else Err("${host.name} is set by the daemon's ${origin_name(host.origin)}, which adds it again at each start: disable it instead")

	## The id liton gives `id` of the host `name`: a Paseo host PASEO_* set,
	## `paseo`, keeps bare ids, and every other names its under its name.
	named : Str, Str -> Str
	named = |name, id| if (name == "paseo") id else "${name}/${id}"

	## The provider id of the Paseo host `name`: `paseo` for the one PASEO_*
	## sets, else `<name>/paseo`.
	paseo_provider : Str -> Str
	paseo_provider = |name| Hosts.named(name, "paseo")
}

origin_name : Hosts.Origin -> Str
origin_name = |origin|
	match origin {
		Setup => "setup"
		_ => "environment"
	}

## A host name or address: letters, digits, `-` and `.`, or an IPv6 address
## in brackets.
address_fits : Str -> Bool
address_fits = |address| {
	if address.starts_with("[") and address.ends_with("]") {
		inner = address.drop_prefix("[").drop_suffix("]")
		inner != "" and inner.to_utf8().all(|byte| "0123456789abcdefABCDEF:.".to_utf8().contains(byte))
	} else {
		address != "" and address.to_utf8().all(|byte| "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.".to_utf8().contains(byte))
	}
}

## An http:// or https:// URL of a host, maybe a port and a path, without a
## user, query or fragment.
url_fits : Str -> Bool
url_fits = |url| {
	rest =
		if url.starts_with("https://") {
			Ok(url.drop_prefix("https://"))
		} else if url.starts_with("http://") {
			Ok(url.drop_prefix("http://"))
		} else {
			Err(NoScheme)
		}
	match rest {
		Ok(after) if !url.to_utf8().any(|byte| " ?#@\\".to_utf8().contains(byte)) => {
			authority = after.split_on("/").first() ?? ""
			match authority.split_last(":") {
				Ok({ before, after: port }) if !port.to_utf8().contains(']') => address_fits(before) and port_fits(port)
				_ => address_fits(authority)
			}
		}
		_ => Bool.False
	}
}

port_fits : Str -> Bool
port_fits = |port|
	match U16.from_str(port) {
		Ok(number) => number > 0
		Err(_) => Bool.False
	}

expect ["127.0.0.1:6767", "paseo.local:443", "[::1]:6767"].all(|target| Hosts.target_problem(Paseo, target) == Ok({}))
expect ["127.0.0.1", ":6767", "host:0", "host:99999", "a b:1", "http://x:1", "[::1]"].all(|target| Hosts.target_problem(Paseo, target).is_err())
expect ["http://127.0.0.1:8096", "https://liton.example", "https://liton.example/team", "http://[::1]:8095"].all(|target| Hosts.target_problem(Liton, target) == Ok({}))
expect ["127.0.0.1:8096", "ftp://x", "http://", "http://u@x", "http://x?y", "http://x:y", "http://x y"].all(|target| Hosts.target_problem(Liton, target).is_err())
expect ["paseo", "my-box_2"].all(|name| Hosts.name_problem(name) == Ok({})) and ["", "a/b", "a b", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"].all(|name| Hosts.name_problem(name).is_err())
expect Hosts.named("paseo", "a1") == "a1" and Hosts.named("box", "a1") == "box/a1" and Hosts.paseo_provider("box") == "box/paseo" and Hosts.paseo_provider("paseo") == "paseo"

expect {
	paseo = { name: "paseo", kind: Paseo, target: "127.0.0.1:6767", label: "", enabled: Bool.True, status: Online, version: Ok("0.15.3"), last_online: Err(Missing), origin: Environment }
	new = { name: "box", kind: Paseo, target: "box.local:6767", label: "Box", password: "secret" }
	Hosts.added_problem([paseo], new) == Ok({})
		and Hosts.added_problem([paseo], { ..new, name: "paseo" }).is_err()
		and Hosts.added_problem([paseo], { ..new, password: "" }).is_err()
		and Hosts.added_problem([], { ..new, kind: Liton, target: "https://team.example", password: "" }) == Ok({})
		and Hosts.changed_problem(paseo, { name: "paseo", target: Err(Missing), label: Ok("Laptop"), password: Err(Missing) }) == Ok({})
		and Hosts.changed_problem(paseo, { name: "paseo", target: Err(Missing), label: Err(Missing), password: Ok("x") }).is_err()
		and Hosts.changed_problem({ ..paseo, origin: Added }, { name: "paseo", target: Ok("nope"), label: Err(Missing), password: Err(Missing) }).is_err()
		and Hosts.removed_problem(paseo).is_err()
		and Hosts.removed_problem({ ..paseo, origin: Added }) == Ok({})
}

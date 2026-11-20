## What Settings' Hosts shows of hosts.v1 (docs/protocol.md, Hosts): the
## hosts as polls last answered them, with the requests on their way
## applied so a change shows at once, and the dialog adding or changing one.
## A password or token typed is sent once and never shown again.
import cap.Hosts

HostDesk := [].{

	## A request sent as `serial`, shown until the daemon refuses it, or
	## until the poll numbered `accepted` answers, the first sent after the
	## daemon accepted it (0 while it waits).
	Asked : { serial : U64, request : Hosts.Request, accepted : U64 }

	## The dialog: closed, or a host to add (`editing` "") or to change, with
	## what is typed, and why the daemon refused it. A password left empty
	## while changing one keeps the one the daemon has.
	Editor : { open : Bool, editing : Str, kind : Hosts.Kind, name : Str, target : Str, label : Str, password : Str, failed : Str }

	## The hosts as polls answered them, the requests on their way, the
	## host whose ⋮ menu is open ("" for none), the one asked to confirm
	## its removal, and the dialog.
	State : { listed : List(Hosts.Host), asked : List(Asked), menu : Str, removing : Str, editor : Editor }

	initial : State
	initial = { listed: [], asked: [], menu: "", removing: "", editor: HostDesk.closed }

	closed : Editor
	closed = { open: Bool.False, editing: "", kind: Paseo, name: "", target: "", label: "", password: "", failed: "" }

	## The hosts as shown: those listed with the requests on their way
	## applied, one being added after them.
	shown : State -> List(Hosts.Host)
	shown = |desk|
		desk.asked.fold(
			desk.listed,
			|so_far, { request, .. }|
				match request {
					AddHost(new) => so_far.append({ name: new.name, kind: new.kind, target: new.target, label: new.label, enabled: Bool.True, status: Connecting, version: Err(Missing), last_online: Err(Missing), origin: Added })
					UpdateHost(change) => so_far.map(|host| if (host.name == change.name) { ..host, target: change.target ?? host.target, label: change.label ?? host.label } else host)
					SetEnabled({ name, enabled }) => so_far.map(|host| if (host.name == name) { ..host, enabled, status: if (enabled) Connecting else Disabled } else host)
					RemoveHost({ name }) => so_far.drop_if(|host| host.name == name)
					ListHosts => so_far
				},
		)

	## What is on its way for a host: "Adding…", "Saving…", "Enabling…",
	## "Disabling…", or "".
	pending : State, Str -> Str
	pending = |desk, name|
		desk.asked.keep_oks(
			|{ request, .. }|
				match request {
					AddHost(new) if new.name == name => Ok("Adding…")
					UpdateHost(change) if change.name == name => Ok("Saving…")
					SetEnabled(switched) if switched.name == name => Ok(if (switched.enabled) "Enabling…" else "Disabling…")
					_ => Err(NotPending)
				},
		).last() ?? ""

	## `desk` with a request on its way as `serial`.
	asking : State, U64, Hosts.Request -> State
	asking = |desk, serial, request| { ..desk, asked: desk.asked.append({ serial, request, accepted: 0 }), menu: "", removing: "" }

	## `desk` with the daemon's answer to the request `serial`: accepted, it
	## holds until the poll numbered `poll` answers; refused, it is undone.
	answered : State, U64, [Accepted(U64), Refused] -> State
	answered = |desk, serial, answer|
		match answer {
			Accepted(poll) => { ..desk, asked: desk.asked.map(|asked| if (asked.serial == serial) { ..asked, accepted: poll } else asked) }
			Refused => { ..desk, asked: desk.asked.drop_if(|asked| asked.serial == serial) }
		}

	## Drops the requests the poll numbered `serial` answered for.
	settled : State, U64 -> State
	settled = |desk, serial| { ..desk, asked: desk.asked.drop_if(|asked| asked.accepted > 0 and asked.accepted <= serial) }

	## The dialog opened on a host, to change it: its password isn't shown.
	edit : Hosts.Host -> Editor
	edit = |host| { ..HostDesk.closed, open: Bool.True, editing: host.name, kind: host.kind, name: host.name, target: host.target, label: host.label }

	## The request the dialog makes, or why it can't be sent: a new host
	## checked as the daemon checks it, or the fields of one changed.
	request_of : Editor, List(Hosts.Host) -> Try(Hosts.Request, Str)
	request_of = |editor, known| {
		new = { name: editor.name.trim(), kind: editor.kind, target: editor.target.trim(), label: editor.label.trim(), password: editor.password }
		if editor.editing.is_empty() {
			Hosts.added_problem(known, new)?
			Ok(AddHost(new))
		} else {
			match known.find_first(|host| host.name == editor.editing) {
				Err(_) => Err("${editor.editing} is gone.")
				Ok(host) => {
					change = { name: host.name, target: if (new.target == host.target) Err(Missing) else Ok(new.target), label: if (new.label == host.label) Err(Missing) else Ok(new.label), password: if (new.password.is_empty()) Err(Missing) else Ok(new.password) }
					Hosts.changed_problem(host, change)?
					Ok(UpdateHost(change))
				}
			}
		}
	}

	## The host that offers what `provider` names: the one called as the
	## provider's id before its `/`, or `paseo` for the Paseo host PASEO_*
	## sets, whose ids are bare; "" for the daemon's own, such as the mock.
	host_of : List(Hosts.Host), Str -> Str
	host_of = |known, provider| {
		named = if (provider == "paseo") "paseo" else provider.split_first("/").map_ok(|{ before, .. }| before) ?? ""
		if (known.any(|host| host.name == named)) named else ""
	}

	## A host's identity colour, one of ten, by its place among the hosts.
	hue : List(Hosts.Host), Str -> U64
	hue = |known, name| known.find_first_index(|host| host.name == name).map_ok(|index| index % 10) ?? 0

	## A host's status in words, and its dot's class.
	status_text : Hosts.Status -> { word : Str, dot : Str }
	status_text = |status|
		match status {
			Connecting => { word: "Connecting…", dot: "connecting" }
			Online => { word: "Online", dot: "online" }
			Offline => { word: "Offline", dot: "offline" }
			Error(why) => { word: why, dot: "error" }
			Disabled => { word: "Disabled", dot: "disabled" }
		}
}

expect {
	paseo = { name: "paseo", kind: Paseo, target: "127.0.0.1:6767", label: "", enabled: Bool.True, status: Online, version: Ok("0.15.3"), last_online: Err(Missing), origin: Environment }
	desk = HostDesk.asking({ ..HostDesk.initial, listed: [paseo] }, 1, SetEnabled({ name: "paseo", enabled: Bool.False }))
	added = HostDesk.asking(desk, 2, AddHost({ name: "team", kind: Liton, target: "https://liton.example", label: "", password: "t" }))
	HostDesk.shown(desk).map(|host| host.status) == [Disabled]
		and HostDesk.pending(desk, "paseo") == "Disabling…"
		and HostDesk.shown(added).map(|host| host.name) == ["paseo", "team"]
		and HostDesk.settled(HostDesk.answered(desk, 1, Accepted(4)), 4).asked.is_empty()
		and HostDesk.answered(desk, 1, Refused).asked.is_empty()
}

expect {
	paseo = { name: "paseo", kind: Paseo, target: "127.0.0.1:6767", label: "", enabled: Bool.True, status: Online, version: Err(Missing), last_online: Err(Missing), origin: Environment }
	relabelled = HostDesk.request_of({ ..HostDesk.edit(paseo), label: "Laptop" }, [paseo])
	relabelled == Ok(UpdateHost({ name: "paseo", target: Err(Missing), label: Ok("Laptop"), password: Err(Missing) }))
		and HostDesk.request_of({ ..HostDesk.edit(paseo), password: "new" }, [paseo]).is_err()
		and HostDesk.request_of({ ..HostDesk.closed, kind: Liton, name: "team", target: "nope" }, [paseo]).is_err()
		and HostDesk.host_of([paseo], "paseo") == "paseo"
		and HostDesk.host_of([{ ..paseo, name: "team" }], "team/mock") == "team"
		and HostDesk.host_of([paseo], "mock") == ""
		and HostDesk.host_of([paseo], "peer/mock") == ""
}

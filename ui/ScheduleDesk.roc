## What Schedules panes show of schedules.v1 (docs/protocol.md, Schedules):
## the schedules and the runs of the one opened, as polls last answered
## them, with the requests on their way applied so a change shows at once,
## and the editor of a schedule being made or changed.
import cap.Schedules

ScheduleDesk := [].{

	## A request sent as `serial`, shown until the daemon refuses it, or
	## until the poll numbered `accepted` answers, the first sent after the
	## daemon accepted it (0 while it waits).
	Asked : { serial : U64, request : Schedules.Request, accepted : U64 }

	## The editor: closed, or a schedule to make (`schedule_id` "") or to
	## change. Its cadence is a preset's key (`presets`), or `cron` with the
	## expression and time zone typed; its target a heartbeat of the session
	## `session_id`, or a new session of the place, agent and settings
	## picked, "" for their defaults. `failed` says why the daemon refused it.
	Editor : { open : Bool, schedule_id : Str, name : Str, prompt : Str, cadence : Str, expression : Str, timezone : Str, session_id : Str, heartbeat : Bool, place : Str, agent : Str, model : Str, mode : Str, thinking : Str, worktree : Bool, archive_on_finish : Bool, failed : Str }

	## The schedules and each schedule's runs as polls answered them, the
	## schedule opened in place to show its runs and actions, "" for none,
	## the requests on their way, and the editor.
	State : { listed : List(Schedules.Schedule), runs : List({ schedule_id : Str, runs : List(Schedules.Run) }), opened : Str, asked : List(Asked), editor : Editor }

	## Nothing listed, opened or asked yet, the editor closed.
	initial : State
	initial = { listed: [], runs: [], opened: "", asked: [], editor: ScheduleDesk.closed }

	## The editor closed.
	closed : Editor
	closed = { open: Bool.False, schedule_id: "", name: "", prompt: "", cadence: "hour", expression: "0 9 * * *", timezone: "UTC", session_id: "", heartbeat: Bool.False, place: "", agent: "", model: "", mode: "", thinking: "", worktree: Bool.False, archive_on_finish: Bool.True, failed: "" }

	## The cadences the editor offers by name, then `cron`, one typed.
	presets : List({ key : Str, label : Str, cadence : Schedules.Cadence })
	presets = [
		{ key: "5m", label: "Every 5 minutes", cadence: Every(300_000) },
		{ key: "15m", label: "Every 15 minutes", cadence: Every(900_000) },
		{ key: "30m", label: "Every 30 minutes", cadence: Every(1_800_000) },
		{ key: "hour", label: "Every hour", cadence: Every(3_600_000) },
		{ key: "6h", label: "Every 6 hours", cadence: Every(21_600_000) },
		{ key: "day", label: "Every day at 09:00", cadence: Cron({ expression: "0 9 * * *", timezone: Err(Missing) }) },
		{ key: "weekdays", label: "Weekdays at 09:00", cadence: Cron({ expression: "0 9 * * 1-5", timezone: Err(Missing) }) },
	]

	## A cadence in words: a preset's name, every so long, or its cron
	## expression and time zone.
	cadence_text : Schedules.Cadence -> Str
	cadence_text = |cadence| {
		every = |count, unit| if (count == 1) "Every ${unit}" else "Every ${count.to_str()} ${unit}s"
		match cadence {
			Every(ms) if ms % 86_400_000 == 0 => every(ms // 86_400_000, "day")
			Every(ms) if ms % 3_600_000 == 0 => every(ms // 3_600_000, "hour")
			Every(ms) if ms % 60_000 == 0 => every(ms // 60_000, "minute")
			Every(ms) => every(ms // 1_000, "second")
			Cron({ expression, timezone }) =>
				match ScheduleDesk.presets.find_first(|preset| preset.cadence == Cron({ expression, timezone: Err(Missing) })) {
					Ok(preset) => "${preset.label}${timezone.map_ok(|zone| " ${zone}") ?? ""}"
					Err(_) => "Cron ${expression}${timezone.map_ok(|zone| " ${zone}") ?? ""}"
				}
		}
	}

	## The schedules as shown: those listed with the requests on their way
	## applied, a schedule being created after them.
	shown : State -> List(Schedules.Schedule)
	shown = |desk|
		desk.asked.fold(
			desk.listed,
			|so_far, { request, serial, .. }|
				match request {
					Create(made) => so_far.append(Schedules.drafted({ id: ScheduleDesk.creating_id(serial), provider: "" }, made))
					Update({ schedule_id, draft: made }) => so_far.map(|listed| if (listed.id == schedule_id) { ..listed, name: made.name, prompt: made.prompt, cadence: made.cadence, target: made.target, max_runs: made.max_runs, expires: made.expires } else listed)
					Pause({ schedule_id }) => so_far.map(|listed| if (listed.id == schedule_id) { ..listed, status: Paused } else listed)
					Resume({ schedule_id }) => so_far.map(|listed| if (listed.id == schedule_id) { ..listed, status: Active } else listed)
					Delete({ schedule_id }) => so_far.drop_if(|listed| listed.id == schedule_id)
					_ => so_far
				},
		)

	## What names a schedule being created until it is listed.
	creating_id : U64 -> Str
	creating_id = |serial| "creating:${serial.to_str()}"

	## What is on its way for a schedule: "Creating…", "Pausing…",
	## "Resuming…", "Running…", "Saving…", or "".
	pending : State, Str -> Str
	pending = |desk, schedule_id|
		desk.asked.keep_oks(
			|{ request, serial, .. }|
				match request {
					Create(_) if ScheduleDesk.creating_id(serial) == schedule_id => Ok("Creating…")
					Pause({ schedule_id: id }) if id == schedule_id => Ok("Pausing…")
					Resume({ schedule_id: id }) if id == schedule_id => Ok("Resuming…")
					RunOnce({ schedule_id: id }) if id == schedule_id => Ok("Running…")
					Update({ schedule_id: id, .. }) if id == schedule_id => Ok("Saving…")
					_ => Err(NotPending)
				},
		).last() ?? ""

	## The runs of a schedule as the last poll of them answered, the latest
	## first.
	runs_of : State, Str -> List(Schedules.Run)
	runs_of = |desk, schedule_id| desk.runs.find_first(|known| known.schedule_id == schedule_id).map_ok(|known| known.runs) ?? []

	## Whether the runs of a schedule have been polled.
	runs_known : State, Str -> Bool
	runs_known = |desk, schedule_id| desk.runs.any(|known| known.schedule_id == schedule_id)

	## `desk` with a request on its way as `serial`.
	asking : State, U64, Schedules.Request -> State
	asking = |desk, serial, request| { ..desk, asked: desk.asked.append({ serial, request, accepted: 0 }) }

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

	## `desk` with what a topic sent: the schedules, or a schedule's runs.
	received : State, [Listed(List(Schedules.Schedule)), Ran(Str, List(Schedules.Run))] -> State
	received = |desk, event|
		match event {
			Listed(listed) => { ..desk, listed }
			Ran(schedule_id, runs) => { ..desk, runs: desk.runs.drop_if(|known| known.schedule_id == schedule_id).append({ schedule_id, runs }) }
		}

	## The editor opened on a schedule, to change it.
	edit : Schedules.Schedule -> Editor
	edit = |schedule| {
		(cadence, expression, timezone) =
			match ScheduleDesk.presets.find_first(|preset| preset.cadence == schedule.cadence) {
				Ok(preset) => (preset.key, ScheduleDesk.closed.expression, ScheduleDesk.closed.timezone)
				Err(_) =>
					match schedule.cadence {
						Cron(cron) => ("cron", cron.expression, cron.timezone ?? "UTC")
						Every(_) => ("hour", ScheduleDesk.closed.expression, ScheduleDesk.closed.timezone)
					}
			}
		opened = { ..ScheduleDesk.closed, open: Bool.True, schedule_id: schedule.id, name: schedule.name, prompt: schedule.prompt, cadence, expression, timezone }
		match schedule.target {
			Session(session_id) => { ..opened, session_id, heartbeat: Bool.True }
			NewSession(made) =>
				{
					..opened,
					place: match made.place {
						Workspace(id) => id
						Directory(directory) => directory
					},
					agent: made.agent,
					model: made.model ?? "",
					mode: made.mode ?? "",
					thinking: made.thinking ?? "",
					worktree: made.isolation == Worktree,
					archive_on_finish: made.archive_on_finish,
				}
		}
	}

	## The draft the editor holds, its place a workspace if `workspaces`
	## lists it, else a directory; or why it can't be one.
	draft_of : Editor, List(Str) -> Try(Schedules.Draft, Str)
	draft_of = |editor, workspaces| {
		told = |chosen| if (chosen.is_empty()) Err(Missing) else Ok(chosen)
		cadence =
			if editor.cadence == "cron" {
				Cron({ expression: editor.expression.trim(), timezone: if (editor.timezone.trim().is_empty() or editor.timezone.trim() == "UTC") Err(Missing) else Ok(editor.timezone.trim()) })
			} else {
				ScheduleDesk.presets.find_first(|preset| preset.key == editor.cadence).map_ok(|preset| preset.cadence) ?? Every(3_600_000)
			}
		target =
			if editor.heartbeat {
				Session(editor.session_id)
			} else {
				NewSession({ place: if (workspaces.contains(editor.place)) Workspace(editor.place) else Directory(editor.place), agent: editor.agent, model: told(editor.model), mode: told(editor.mode), thinking: told(editor.thinking), isolation: if (editor.worktree) Worktree else Local, archive_on_finish: editor.archive_on_finish })
			}
		if editor.prompt.trim().is_empty() {
			Err("Write the prompt it sends.")
		} else if editor.cadence == "cron" and editor.expression.trim().is_empty() {
			Err("Write a cron expression, such as 0 9 * * *.")
		} else if !editor.heartbeat and (editor.place.is_empty() or editor.agent.is_empty()) {
			Err("Pick where the new agent works, and which.")
		} else {
			Ok({ name: editor.name.trim(), prompt: editor.prompt.trim(), cadence, target, max_runs: Err(Missing), expires: Err(Missing) })
		}
	}
}

expect ScheduleDesk.cadence_text(Every(1_800_000)) == "Every 30 minutes" and ScheduleDesk.cadence_text(Every(3_600_000)) == "Every hour" and ScheduleDesk.cadence_text(Cron({ expression: "0 9 * * *", timezone: Ok("Europe/Berlin") })) == "Every day at 09:00 Europe/Berlin" and ScheduleDesk.cadence_text(Cron({ expression: "0 3 * * *", timezone: Err(Missing) })) == "Cron 0 3 * * *"

# A request shows at once, and holds until the poll after it is accepted.
expect {
	beat = Schedules.drafted({ id: "h1", provider: "mock" }, { name: "Beat", prompt: "Status?", cadence: Every(60_000), target: Session("s1"), max_runs: Err(Missing), expires: Err(Missing) })
	desk = ScheduleDesk.asking({ ..ScheduleDesk.initial, listed: [beat] }, 1, Pause({ schedule_id: "h1" }))
	accepted = ScheduleDesk.answered(desk, 1, Accepted(4))
	ScheduleDesk.shown(desk).map(|shown| shown.status) == [Paused]
		and ScheduleDesk.pending(desk, "h1") == "Pausing…"
		and ScheduleDesk.settled(accepted, 3).asked.len() == 1
		and ScheduleDesk.settled(accepted, 4).asked.is_empty()
		and ScheduleDesk.answered(desk, 1, Refused).asked.is_empty()
		and ScheduleDesk.shown(ScheduleDesk.asking(desk, 2, Delete({ schedule_id: "h1" }))) == []
}

# The editor's draft, and the editor opened on a schedule gives it back.
expect {
	editor = { ..ScheduleDesk.closed, open: Bool.True, name: "Nightly", prompt: "Update deps", cadence: "cron", expression: "0 3 * * *", timezone: "Europe/Berlin", place: "main", agent: "claude", worktree: Bool.True }
	made = ScheduleDesk.draft_of(editor, ["main"])
	again = made.map_ok(|kept| ScheduleDesk.draft_of(ScheduleDesk.edit(Schedules.drafted({ id: "n1", provider: "mock" }, kept)), ["main"]))
	made.map_ok(|kept| kept.target) == Ok(NewSession({ place: Workspace("main"), agent: "claude", model: Err(Missing), mode: Err(Missing), thinking: Err(Missing), isolation: Worktree, archive_on_finish: Bool.True }))
		and again == Ok(made)
		and ScheduleDesk.draft_of({ ..editor, prompt: "" }, []).is_err()
}

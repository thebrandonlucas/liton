import cap.Hosts
import cap.Schedules
import Paseo

## Paseo's schedules as schedules.v1's: its session-level `schedule/*`
## requests and their answers, alike from Paseo 0.9 to 0.15. Paseo has
## schedules from long before the 0.9.2 liton speaks first, and lists no
## feature for them.
PaseoSchedules := [].{

	## A schedule as Paseo stores it, its runs left out of a listing.
	Stored : {
		id : Str,
		name : Try(Str, [Null]),
		prompt : Str,
		cadence : { type : Str, every_ms : Try(U64, [Missing]), expression : Try(Str, [Missing]), timezone : Try(Str, [Missing]) },
		target : { type : Str, agent_id : Try(Str, [Missing]), config : Try(Config, [Missing]) },
		status : Str,
		next_run_at : Try(Str, [Null]),
		last_run_at : Try(Str, [Null]),
		expires_at : Try(Str, [Null]),
		max_runs : Try(U64, [Null]),
		runs : Try(List(StoredRun), [Missing]),
	}

	## A new agent's config, as a schedule's target names it.
	Config : { provider : Str, cwd : Str, mode_id : Try(Str, [Missing]), model : Try(Str, [Missing]), thinking_option_id : Try(Str, [Missing]), archive_on_finish : Try(Bool, [Missing]), isolation : Try(Str, [Missing]) }

	## A run as Paseo stores it.
	StoredRun : { id : Str, scheduled_for : Str, started_at : Str, ended_at : Try(Str, [Null]), status : Str, agent_id : Try(Str, [Null]), output : Try(Str, [Null]), error : Try(Str, [Null]) }

	## A `schedule/<action>` request of one schedule, or of none with "".
	request : Str, Str, Str -> Str
	request = |action, schedule_id, request_id|
		if (schedule_id.is_empty()) Json.to_str({ type: "session", message: { type: "schedule/${action}", requestId: request_id } }) else Json.to_str({ type: "session", message: { type: "schedule/${action}", requestId: request_id, scheduleId: schedule_id } })

	## A `schedule/create` of a draft, to the Paseo host `host`, a new
	## session's in `cwd`, the directory its place names.
	create_request : Str, Schedules.Draft, Str, Str -> Str
	create_request = |host, draft, cwd, request_id| {
		name : Try(Str, [Missing])
		name = if (draft.name.is_empty()) Err(Missing) else Ok(draft.name)
		Json.to_str({ type: "session", message: { type: "schedule/create", requestId: request_id, prompt: draft.prompt, name, cadence: PaseoSchedules.cadence(draft.cadence), target: PaseoSchedules.target(host, draft.target, cwd), maxRuns: draft.max_runs, expiresAt: draft.expires } })
	}

	## A `schedule/update` to a draft: its name, prompt, cadence, a new
	## session's config, and its limits, `null` to clear one.
	update_request : Str, Schedules.Draft, Str, Str -> Str
	update_request = |schedule_id, draft, cwd, request_id| {
		cleared : Try(a, [Missing]) -> Try(a, [Null])
		cleared = |value| value.map_err(|_| Null)
		name : Try(Str, [Null])
		name = if (draft.name.is_empty()) Err(Null) else Ok(draft.name)
		config : Try({ provider : Str, cwd : Str, model : Try(Str, [Null]), modeId : Try(Str, [Null]), thinkingOptionId : Try(Str, [Null]), archiveOnFinish : Bool, isolation : Str }, [Missing])
		config =
			match draft.target {
				NewSession(made) => Ok({ provider: made.agent, cwd, model: cleared(made.model), modeId: cleared(made.mode), thinkingOptionId: cleared(made.thinking), archiveOnFinish: made.archive_on_finish, isolation: PaseoSchedules.isolation(made.isolation) })
				Session(_) => Err(Missing)
			}
		Json.to_str({ type: "session", message: { type: "schedule/update", requestId: request_id, scheduleId: schedule_id, name, prompt: draft.prompt, cadence: PaseoSchedules.cadence(draft.cadence), newAgentConfig: config, maxRuns: cleared(draft.max_runs), expiresAt: cleared(draft.expires) } })
	}

	## A cadence as Paseo writes it.
	cadence : Schedules.Cadence -> { type : Str, everyMs : Try(U64, [Missing]), expression : Try(Str, [Missing]), timezone : Try(Str, [Missing]) }
	cadence = |given|
		match given {
			Every(ms) => { type: "every", everyMs: Ok(ms), expression: Err(Missing), timezone: Err(Missing) }
			Cron({ expression, timezone }) => { type: "cron", everyMs: Err(Missing), expression: Ok(expression), timezone }
		}

	## A target as the Paseo host `host` writes it, a new session's in `cwd`.
	target : Str, Schedules.Target, Str -> { type : Str, agentId : Try(Str, [Missing]), config : Try({ provider : Str, cwd : Str, model : Try(Str, [Missing]), modeId : Try(Str, [Missing]), thinkingOptionId : Try(Str, [Missing]), archiveOnFinish : Bool, isolation : Str }, [Missing]) }
	target = |host, given, cwd|
		match given {
			Session(session_id) => { type: "agent", agentId: Ok(Hosts.their_id(host, session_id)), config: Err(Missing) }
			NewSession(made) => { type: "new-agent", agentId: Err(Missing), config: Ok({ provider: made.agent, cwd, model: made.model, modeId: made.mode, thinkingOptionId: made.thinking, archiveOnFinish: made.archive_on_finish, isolation: PaseoSchedules.isolation(made.isolation) }) }
		}

	## An isolation as Paseo names it.
	isolation : [Local, Worktree] -> Str
	isolation = |given| if (given == Worktree) "worktree" else "local"

	## A schedule the Paseo host `host` stores as schedules.v1's.
	schedule : Str, Stored -> Schedules.Schedule
	schedule = |host, stored| {
		optional = |value| value.map_err(|_| Missing)
		paced =
			match (stored.cadence.type, stored.cadence.every_ms) {
				("every", Ok(ms)) => Every(ms)
				_ => Cron({ expression: stored.cadence.expression ?? "", timezone: stored.cadence.timezone })
			}
		prompted =
			match (stored.target.agent_id, stored.target.config) {
				(Ok(agent_id), _) => Session(Hosts.named(host, agent_id))
				(_, Ok(config)) => NewSession({ place: Directory(config.cwd), agent: config.provider, model: config.model, mode: config.mode_id, thinking: config.thinking_option_id, isolation: if (config.isolation == Ok("worktree")) Worktree else Local, archive_on_finish: config.archive_on_finish ?? Bool.False })
				_ => Session("")
			}
		{
			id: Hosts.named(host, stored.id),
			provider: Hosts.paseo_provider(host),
			name: stored.name ?? "",
			prompt: stored.prompt,
			cadence: paced,
			target: prompted,
			status: if (stored.status == "paused") Paused else if (stored.status == "completed") Completed else Active,
			next_run: optional(stored.next_run_at),
			last_run: optional(stored.last_run_at),
			max_runs: optional(stored.max_runs),
			expires: optional(stored.expires_at),
		}
	}

	## A run the Paseo host `host` stores as schedules.v1's.
	run : Str, StoredRun -> Schedules.Run
	run = |host, stored| {
		optional = |value| value.map_err(|_| Missing)
		{ id: stored.id, scheduled_for: stored.scheduled_for, started: stored.started_at, ended: optional(stored.ended_at), status: if (stored.status == "running") Running else if (stored.status == "succeeded") Succeeded else Failed, session_id: optional(stored.agent_id).map_ok(|agent_id| Hosts.named(host, agent_id)), output: optional(stored.output), error: optional(stored.error) }
	}

	## The schedules of the Paseo host `host` a `schedule/list/response`
	## answering `request_id` lists.
	listed : Str, Str, Str -> Try(List(Schedules.Schedule), [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str)])
	listed = |host, text, request_id| {
		answered : Try({ message : { payload : { schedules : Try(List(Stored), [Missing]), error : Try(Str, [Null]) } } }, _)
		answered = Json.parser_camel()(Paseo.write_answer(text, "schedule/list/response", request_id)?)
		payload = answered?.message.payload
		match payload.error {
			Ok(reason) => Err(Refused(reason))
			Err(Null) => Ok((payload.schedules ?? []).map(|stored| PaseoSchedules.schedule(host, stored)))
		}
	}

	## The schedule of the Paseo host `host` an answer of `action` to
	## `request_id` holds, with its runs, the latest first, when it tells
	## them; or why Paseo refused.
	inspected : Str, Str, Str, Str -> Try({ schedule : Schedules.Schedule, runs : List(Schedules.Run) }, [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str), NoSchedule])
	inspected = |host, text, action, request_id| {
		read : Try({ message : { payload : { schedule : Try(Try(Stored, [Null]), [Missing]), error : Try(Str, [Null]) } } }, _)
		read = Json.parser_camel()(Paseo.write_answer(text, "schedule/${action}/response", request_id)?)
		payload = read?.message.payload
		match (payload.error, payload.schedule) {
			(Ok(reason), _) => Err(Refused(reason))
			(_, Ok(Ok(stored))) => Ok({ schedule: PaseoSchedules.schedule(host, stored), runs: (stored.runs ?? []).fold([], |latest_first, stored_run| latest_first.prepend(PaseoSchedules.run(host, stored_run))) })
			_ => Err(NoSchedule)
		}
	}

	## Whether Paseo took a change asked by `action`: it answers with the
	## schedule, or for `delete` its id, or why not.
	took : Str, Str, Str -> Try({}, [OtherMessage, Refused(Str), InvalidJson(Str), MissingRequiredField(Str)])
	took = |text, action, request_id| {
		read : Try({ message : { payload : { error : Try(Str, [Null]) } } }, _)
		read = Json.parser_camel()(Paseo.write_answer(text, "schedule/${action}/response", request_id)?)
		match read?.message.payload.error {
			Ok(reason) => Err(Refused(reason))
			Err(Null) => Ok({})
		}
	}
}

expect {
	stored = "{\"id\":\"s1\",\"name\":null,\"prompt\":\"Is CI green?\",\"cadence\":{\"type\":\"every\",\"everyMs\":1800000},\"target\":{\"type\":\"agent\",\"agentId\":\"a1\"},\"status\":\"active\",\"createdAt\":\"2026-01-01T00:00:00.000Z\",\"updatedAt\":\"2026-01-01T00:00:00.000Z\",\"nextRunAt\":\"2026-01-01T00:30:00.000Z\",\"lastRunAt\":null,\"pausedAt\":null,\"expiresAt\":null,\"maxRuns\":null}"
	nightly = "{\"id\":\"s2\",\"name\":\"Nightly\",\"prompt\":\"Update\",\"cadence\":{\"type\":\"cron\",\"expression\":\"0 3 * * *\",\"timezone\":\"Europe/Berlin\"},\"target\":{\"type\":\"new-agent\",\"config\":{\"provider\":\"claude\",\"cwd\":\"/work\",\"model\":\"opus\",\"archiveOnFinish\":true,\"isolation\":\"worktree\"}},\"status\":\"paused\",\"createdAt\":\"x\",\"updatedAt\":\"x\",\"nextRunAt\":null,\"lastRunAt\":\"2026-01-01T03:00:00.000Z\",\"pausedAt\":\"x\",\"expiresAt\":null,\"maxRuns\":5,\"runs\":[{\"id\":\"r1\",\"scheduledFor\":\"a\",\"startedAt\":\"b\",\"endedAt\":\"c\",\"status\":\"succeeded\",\"agentId\":\"a9\",\"output\":\"Done\",\"error\":null},{\"id\":\"r2\",\"scheduledFor\":\"d\",\"startedAt\":\"e\",\"endedAt\":null,\"status\":\"running\",\"agentId\":null,\"output\":null,\"error\":null}]}"
	list = "{\"type\":\"session\",\"message\":{\"type\":\"schedule/list/response\",\"payload\":{\"requestId\":\"l1\",\"schedules\":[${stored}],\"error\":null}}}"
	inspected_text = "{\"type\":\"session\",\"message\":{\"type\":\"schedule/inspect/response\",\"payload\":{\"requestId\":\"i1\",\"schedule\":${nightly},\"error\":null}}}"
	heartbeat = { ..Schedules.drafted({ id: "s1", provider: "paseo" }, { name: "", prompt: "Is CI green?", cadence: Every(1_800_000), target: Session("a1"), max_runs: Err(Missing), expires: Err(Missing) }), next_run: Ok("2026-01-01T00:30:00.000Z") }
	shown = PaseoSchedules.inspected("paseo", inspected_text, "inspect", "i1")
	PaseoSchedules.listed("paseo", list, "l1") == Ok([heartbeat])
		and shown.map_ok(|found| found.schedule.target) == Ok(NewSession({ place: Directory("/work"), agent: "claude", model: Ok("opus"), mode: Err(Missing), thinking: Err(Missing), isolation: Worktree, archive_on_finish: Bool.True }))
		and shown.map_ok(|found| (found.schedule.status, found.schedule.cadence, found.schedule.max_runs)) == Ok((Paused, Cron({ expression: "0 3 * * *", timezone: Ok("Europe/Berlin") }), Ok(5)))
		and shown.map_ok(|found| found.runs.map(|listed_run| (listed_run.id, listed_run.status, listed_run.session_id))) == Ok([("r2", Running, Err(Missing)), ("r1", Succeeded, Ok("a9"))])
		# Another Paseo host's are named under its name.
		and PaseoSchedules.listed("box", list, "l1").map_ok(|listed| listed.map(|found| (found.id, found.provider, found.target))) == Ok([("box/s1", "box/paseo", Session("box/a1"))])
		and PaseoSchedules.inspected("box", inspected_text, "inspect", "i1").map_ok(|found| found.runs.map(|listed_run| listed_run.session_id)) == Ok([Err(Missing), Ok("box/a9")])
}

expect {
	draft = { name: "", prompt: "Is CI green?", cadence: Every(60_000), target: Session("a1"), max_runs: Err(Missing), expires: Err(Missing) }
	PaseoSchedules.create_request("box", { ..draft, target: Session("box/a1") }, "", "c1") == PaseoSchedules.create_request("paseo", draft, "", "c1")
		and PaseoSchedules.create_request("paseo", draft, "", "c1") == "{\"message\":{\"cadence\":{\"everyMs\":60000,\"type\":\"every\"},\"prompt\":\"Is CI green?\",\"requestId\":\"c1\",\"target\":{\"agentId\":\"a1\",\"type\":\"agent\"},\"type\":\"schedule/create\"},\"type\":\"session\"}"
}

expect {
	PaseoSchedules.request("pause", "s9", "p1") == "{\"message\":{\"requestId\":\"p1\",\"scheduleId\":\"s9\",\"type\":\"schedule/pause\"},\"type\":\"session\"}"
}

expect {
	refused = "{\"type\":\"session\",\"message\":{\"type\":\"schedule/pause/response\",\"payload\":{\"requestId\":\"p1\",\"schedule\":null,\"error\":\"Schedule not found: s9\"}}}"
	PaseoSchedules.took(refused, "pause", "p1") == Err(Refused("Schedule not found: s9"))
}

expect {
	draft = { name: "", prompt: "Is CI green?", cadence: Every(60_000), target: Session("a1"), max_runs: Err(Missing), expires: Err(Missing) }
	PaseoSchedules.update_request("s1", { ..draft, max_runs: Ok(3) }, "", "u1") == "{\"message\":{\"cadence\":{\"everyMs\":60000,\"type\":\"every\"},\"expiresAt\":null,\"maxRuns\":3,\"name\":null,\"prompt\":\"Is CI green?\",\"requestId\":\"u1\",\"scheduleId\":\"s1\",\"type\":\"schedule/update\"},\"type\":\"session\"}"
}

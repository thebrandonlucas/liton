## `schedules.v1`: prompts that run on a cadence, as Paseo's schedules do,
## each in a session it keeps prompting, a heartbeat, or in a new session
## each time; and the runs each made.

Schedules := [].{

	## How often a schedule runs: every so many milliseconds, or at the
	## times a cron expression names, in a time zone (such as
	## Europe/Berlin), or else UTC.
	Cadence : [Every(U64), Cron({ expression : Str, timezone : Try(Str, [Missing]) })]

	## Where a run prompts: a session that exists, a heartbeat, or a new
	## session each run (`NewSession`).
	Target : [Session(Str), NewSession(NewSession)]

	## A session a run starts: where it works (a workspace, or a directory of
	## the provider), the agent and, if not their defaults, its model, mode and
	## thinking level, whether it works in a worktree of its own, and whether
	## it is archived once its run is done.
	NewSession : { place : [Workspace(Str), Directory(Str)], agent : Str, model : Try(Str, [Missing]), mode : Try(Str, [Missing]), thinking : Try(Str, [Missing]), isolation : [Local, Worktree], archive_on_finish : Bool }

	## `Completed` once it ran `max_runs` times or `expires` passed.
	Status : [Active, Paused, Completed]

	## A schedule: its name ("" for none), the prompt it sends, its cadence
	## and target, its status, when it runs next and ran last, and how many
	## times at most it runs and until when, as times such as
	## 2026-01-01T09:00:00.000Z, each left out when there is none.
	Schedule : { id : Str, provider : Str, name : Str, prompt : Str, cadence : Cadence, target : Target, status : Status, next_run : Try(Str, [Missing]), last_run : Try(Str, [Missing]), max_runs : Try(U64, [Missing]), expires : Try(Str, [Missing]) }

	## A run of a schedule: when it was due, started and ended (left out
	## while it runs), how it went, the session it prompted, and what it
	## answered or why it failed, as far as its provider tells.
	Run : { id : Str, scheduled_for : Str, started : Str, ended : Try(Str, [Missing]), status : [Running, Succeeded, Failed], session_id : Try(Str, [Missing]), output : Try(Str, [Missing]), error : Try(Str, [Missing]) }

	## What a schedule is made of, to create one or to change one with.
	Draft : { name : Str, prompt : Str, cadence : Cadence, target : Target, max_runs : Try(U64, [Missing]), expires : Try(Str, [Missing]) }

	## `ListSchedules` lists them and `Inspect` tells one with its runs, the
	## latest first. `Create` makes one of the provider the call names, or
	## the only one; `Update` changes one to a draft, its target's kind
	## kept. `Pause` stops one running until `Resume`, `RunOnce` runs it now,
	## besides its cadence, and `Delete` forgets it with its runs.
	Request : [
		ListSchedules,
		Inspect({ schedule_id : Str }),
		Create(Draft),
		Update({ schedule_id : Str, draft : Draft }),
		Pause({ schedule_id : Str }),
		Resume({ schedule_id : Str }),
		RunOnce({ schedule_id : Str }),
		Delete({ schedule_id : Str }),
	]

	## What a request answers: the schedules, one with its runs, the id of
	## one created, or whether the provider took a change.
	Response : [Schedules(List(Schedule)), Inspected({ schedule : Schedule, runs : List(Run) }), Created({ schedule_id : Str }), Accepted, Rejected(Str)]

	## The schedule a request names, "" for none.
	schedule_of : Request -> Str
	schedule_of = |request|
		match request {
			ListSchedules | Create(_) => ""
			Inspect({ schedule_id }) | Pause({ schedule_id }) | Resume({ schedule_id }) | RunOnce({ schedule_id }) | Delete({ schedule_id }) => schedule_id
			Update({ schedule_id, .. }) => schedule_id
		}

	## A schedule made of `draft`, before its provider tells more: active,
	## not run yet.
	drafted : { id : Str, provider : Str }, Draft -> Schedule
	drafted = |{ id, provider }, { name, prompt, cadence, target, max_runs, expires }| { id, provider, name, prompt, cadence, target, status: Active, next_run: Err(Missing), last_run: Err(Missing), max_runs, expires }
}

expect Schedules.schedule_of(Pause({ schedule_id: "h1" })) == "h1" and Schedules.schedule_of(ListSchedules) == ""

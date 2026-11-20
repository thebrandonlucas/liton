import cap.Chat
import cap.Schedules

## The mock's schedules (schedules.v1): kept by the daemon, and run by the
## time it gives each function, in milliseconds since the epoch, so a test
## drives their clock. Cron expressions run in UTC, of the minute and hour
## fields alone: each a number, `*` or `*/N`, the others `*`.
MockSchedules := [].{

	## A schedule with its runs, the latest first, and when it is next due,
	## if it is.
	Kept : { schedule : Schedules.Schedule, runs : List(Schedules.Run), next_at : Try(I64, [Missing]) }

	## A schedule made of `draft` at `now`, due when its cadence says, or
	## why the mock can't run it.
	created : Str, Schedules.Draft, I64 -> Try(Kept, Str)
	created = |id, draft, now| {
		if draft.prompt.trim().is_empty() {
			return Err("a schedule needs a prompt")
		}
		next_at = MockSchedules.next_after(draft.cadence, now)?
		Ok(MockSchedules.with_next_run({ schedule: Schedules.drafted({ id, provider: "mock" }, draft), runs: [], next_at: Ok(next_at) }))
	}

	## `kept` changed to `draft`, its runs kept, due again from `now`.
	updated : Kept, Schedules.Draft, I64 -> Try(Kept, Str)
	updated = |kept, draft, now| {
		changed = MockSchedules.created(kept.schedule.id, draft, now)?
		was_paused = kept.schedule.status == Paused
		Ok(MockSchedules.with_next_run({ ..changed, runs: kept.runs, schedule: { ..changed.schedule, status: if (was_paused) Paused else Active, last_run: kept.schedule.last_run }, next_at: if (was_paused) Err(Missing) else changed.next_at }))
	}

	## A schedule paused, due no more until resumed.
	paused : Kept -> Kept
	paused = |kept| if (kept.schedule.status == Active) MockSchedules.with_next_run({ ..kept, schedule: { ..kept.schedule, status: Paused }, next_at: Err(Missing) }) else kept

	## A paused schedule active again, due when its cadence says from `now`.
	resumed : Kept, I64 -> Kept
	resumed = |kept, now|
		if kept.schedule.status == Paused {
			MockSchedules.with_next_run({ ..kept, schedule: { ..kept.schedule, status: Active }, next_at: MockSchedules.next_after(kept.schedule.cadence, now).map_err(|_| Missing) })
		} else {
			kept
		}

	## When a schedule due at `now` runs: when it was due, and the schedule due
	## next by its cadence. `NotDue` before then, or once paused or completed.
	due : Kept, I64 -> Try({ scheduled_for : I64, kept : Kept }, [NotDue])
	due = |kept, now|
		match kept.next_at {
			Ok(at) if at <= now and kept.schedule.status == Active => Ok({ scheduled_for: at, kept: MockSchedules.with_next_run({ ..kept, next_at: MockSchedules.next_after(kept.schedule.cadence, now).map_err(|_| Missing) }) })
			_ => Err(NotDue)
		}

	## `kept` with a run it made at `now`, due for `scheduled_for`, of the
	## session it prompted, or why it couldn't: completed once it ran
	## `max_runs` times or `expires` passed.
	ran : Kept, I64, I64, Try(Str, Str) -> Kept
	ran = |kept, scheduled_for, now, prompted| {
		run = {
			id: "${kept.schedule.id}-run-${(kept.runs.len() + 1).to_str()}",
			scheduled_for: Chat.timestamp(scheduled_for),
			started: Chat.timestamp(now),
			ended: Ok(Chat.timestamp(now)),
			status: if (prompted.is_ok()) Succeeded else Failed,
			session_id: prompted.map_err(|_| Missing),
			output: prompted.map_ok(|session_id| "Prompted ${session_id}.").map_err(|_| Missing),
			error: match prompted {
				Ok(_) => Err(Missing)
				Err(reason) => Ok(reason)
			},
		}
		with_run = { ..kept, runs: kept.runs.prepend(run), schedule: { ..kept.schedule, last_run: Ok(Chat.timestamp(now)) } }
		done = (kept.schedule.max_runs.map_ok(|most| with_run.runs.len() >= most) ?? Bool.False) or (kept.schedule.expires.map_ok(|until| MockSchedules.moment(until) <= MockSchedules.moment(Chat.timestamp(now))) ?? Bool.False)
		MockSchedules.with_next_run(if (done) { ..with_run, schedule: { ..with_run.schedule, status: Completed }, next_at: Err(Missing) } else with_run)
	}

	## A time such as 2026-01-01T09:00:00.000Z as its digits, which order as
	## it does.
	moment : Str -> U64
	moment = |time| time.to_utf8().keep_if(|byte| byte >= '0' and byte <= '9').fold(0, |number, digit| number * 10 + (digit - '0').to_u64())

	## `kept` with its schedule's `next_run` as its `next_at` says.
	with_next_run : Kept -> Kept
	with_next_run = |kept| { ..kept, schedule: { ..kept.schedule, next_run: kept.next_at.map_ok(Chat.timestamp) } }

	## When a cadence is next due after `now`, or why the mock can't run it.
	next_after : Schedules.Cadence, I64 -> Try(I64, Str)
	next_after = |cadence, now|
		match cadence {
			Every(ms) if ms < 1_000 => Err("the mock runs schedules every second at most")
			Every(ms) => Ok(now + ms.to_i64_wrap())
			Cron({ timezone: Ok(zone), .. }) if zone != "UTC" => Err("the mock runs cron expressions in UTC alone")
			Cron({ expression, .. }) => {
				fields = expression.trim().split_on(" ").drop_if(Str.is_empty)
				minute = MockSchedules.field(fields.get(0) ?? "", 60)?
				hour = MockSchedules.field(fields.get(1) ?? "", 24)?
				if fields.len() != 5 or !fields.drop_first(2).all(|rest| rest == "*") {
					return Err("the mock runs cron expressions of minutes and hours alone, such as 0 9 * * *")
				}
				first = (now // 60_000 + 1) * 60_000
				MockSchedules.first_minute(first, 2_880, |at| minute((at // 60_000) % 60) and hour((at // 3_600_000) % 24)).map_err(|_| "the cron expression ${expression} names no time")
			}
		}

	## The first of `count` minutes from `at` that `holds`.
	first_minute : I64, U64, (I64 -> Bool) -> Try(I64, [NoneHolds])
	first_minute = |at, count, holds|
		if count == 0 {
			Err(NoneHolds)
		} else if holds(at) {
			Ok(at)
		} else {
			MockSchedules.first_minute(at + 60_000, count - 1, holds)
		}

	## Whether a cron field, a number, `*` or `*/N`, under `limit`, holds a
	## value.
	field : Str, I64 -> Try((I64 -> Bool), Str)
	field = |text, limit|
		match I64.from_str(text.drop_prefix("*/")) {
			_ if text == "*" => Ok(|_| Bool.True)
			Ok(step) if text.starts_with("*/") and step > 0 => Ok(|value| value % step == 0)
			Ok(number) if !text.starts_with("*/") and number >= 0 and number < limit => Ok(|value| value == number)
			_ => Err("the mock can't read the cron field ${text}")
		}
}

expect {
	draft = { name: "", prompt: "Is CI green?", cadence: Every(60_000), target: Session("fix-auth"), max_runs: Ok(2), expires: Err(Missing) }
	kept = MockSchedules.created("h1", draft, 0) ?? { schedule: Schedules.drafted({ id: "", provider: "" }, draft), runs: [], next_at: Err(Missing) }
	early = MockSchedules.due(kept, 59_999)
	first = MockSchedules.due(kept, 60_000) ?? { scheduled_for: 0, kept }
	once = MockSchedules.ran(first.kept, first.scheduled_for, 60_000, Ok("fix-auth"))
	second = MockSchedules.due(once, 120_000) ?? { scheduled_for: 0, kept }
	twice = MockSchedules.ran(second.kept, second.scheduled_for, 120_000, Err("no session"))
	early == Err(NotDue)
		and kept.schedule.next_run == Ok("1970-01-01T00:01:00.000Z")
		and once.runs.map(|run| run.session_id) == [Ok("fix-auth")]
		and once.schedule.status == Active
		and twice.schedule.status == Completed
		and twice.runs.map(|run| run.status) == [Failed, Succeeded]
		and MockSchedules.due(twice, 999_999) == Err(NotDue)
}

expect {
	draft = { name: "", prompt: "Go", cadence: Every(60_000), target: Session("s"), max_runs: Err(Missing), expires: Err(Missing) }
	kept = MockSchedules.created("h1", draft, 0) ?? { schedule: Schedules.drafted({ id: "", provider: "" }, draft), runs: [], next_at: Err(Missing) }
	held = MockSchedules.paused(kept)
	resumed = MockSchedules.resumed(held, 500_000)
	MockSchedules.due(held, 999_999) == Err(NotDue) and held.schedule.next_run == Err(Missing) and resumed.schedule.next_run == Ok(Chat.timestamp(560_000)) and resumed.schedule.status == Active
}

# Cron in UTC: 09:00 every day, every 15 minutes; others are refused.
expect {
	at_nine = MockSchedules.next_after(Cron({ expression: "0 9 * * *", timezone: Err(Missing) }), 1_767_258_000_123)
	quarter = MockSchedules.next_after(Cron({ expression: "*/15 * * * *", timezone: Ok("UTC") }), 1_767_258_000_123)
	at_nine.map_ok(Chat.timestamp) == Ok("2026-01-02T09:00:00.000Z")
		and quarter.map_ok(Chat.timestamp) == Ok("2026-01-01T09:15:00.000Z")
		and MockSchedules.next_after(Cron({ expression: "0 9 * * 1-5", timezone: Err(Missing) }), 0).is_err()
		and MockSchedules.next_after(Cron({ expression: "0 9 * * *", timezone: Ok("Europe/Berlin") }), 0).is_err()
		and MockSchedules.created("h", { name: "", prompt: " ", cadence: Every(60_000), target: Session("s"), max_runs: Err(Missing), expires: Err(Missing) }, 0).is_err()
}

## What the UI shows of usage.v1 and limits.v1 (docs/protocol.md, Usage
## and Limits): the accounts' reports and the limits' status as polls last
## answered them, with the limits on their way applied, so a slider moved
## shows at once how near each session and account is.
import cap.Limits
import cap.Usage

LimitDesk := [].{

	## A request sent as `serial`, shown until the daemon refuses it, or
	## until the poll numbered `accepted` answers, the first sent after the
	## daemon accepted it (0 while it waits).
	Asked : { serial : U64, request : Limits.Request, accepted : U64 }

	## The reports and status as polls answered them, the limits on their
	## way, and the serial of a Refresh on its way (0 for none).
	State : { reports : List(Usage.Report), status : Limits.Status, asked : List(Asked), refreshing : U64 }

	## A row of the usage shown: an account, or one of its windows with the
	## percent used, and how near the weekly limit an account's week is.
	Row : { key : Str, account : Bool, title : Str, detail : Str, percent : U64, state : Limits.State }

	initial : State
	initial = { reports: [], status: { limits: [], sessions: [], weeks: [], five_hours: [] }, asked: [], refreshing: 0 }

	## The limits set, with those on their way applied.
	limits : State -> List(Limits.Limit)
	limits = |desk|
		desk.asked.fold(
			desk.status.limits,
			|so_far, { request, .. }|
				match request {
					SetLimit(limit) => so_far.drop_if(|old| old.scope == limit.scope).append(limit)
					ClearLimit({ scope }) => so_far.drop_if(|old| old.scope == scope)
				},
		)

	## The percent of a scope's limit as shown, 0 for none.
	percent : State, Limits.Scope -> U64
	percent = |desk, scope| Limits.limit_of(LimitDesk.limits(desk), scope) ?? 0

	## A session's context as shown, its limit its own or the default.
	session : State, Str -> Try(Limits.SessionStatus, [NotFound])
	session = |desk, session_id|
		desk.status.sessions.find_first(|row| row.session_id == session_id).map_ok(
			|row| {
				limit_pct = Limits.session_limit(LimitDesk.limits(desk), session_id)
				{ ..row, limit_pct, state: Limits.state_of(row.used_pct, limit_pct) }
			},
		)

	## The accounts' weeks as shown, under the weekly limit.
	weeks : State -> List(Limits.WeekStatus)
	weeks = |desk| LimitDesk.under(desk, desk.status.weeks, Week)

	## The accounts' 5-hour windows as shown, under the 5-hour limit.
	five_hours : State -> List(Limits.WeekStatus)
	five_hours = |desk| LimitDesk.under(desk, desk.status.five_hours, FiveHour)

	## `windows` under the limit of `scope` as shown.
	under : State, List(Limits.WeekStatus), Limits.Scope -> List(Limits.WeekStatus)
	under = |desk, windows, scope| {
		limit_pct = Limits.limit_of(LimitDesk.limits(desk), scope)
		windows.map(|row| { ..row, limit_pct, state: Limits.state_of(row.used_pct, limit_pct) })
	}

	## The week of a session's account: its provider's whose source is its
	## agent.
	week_of : State, Str, Str -> Try(Limits.WeekStatus, [NotFound])
	week_of = |desk, provider, agent| LimitDesk.weeks(desk).find_first(|row| row.provider == provider and row.source == agent)

	## Whether a change of a scope's limit is on its way.
	pending : State, Limits.Scope -> Bool
	pending = |desk, scope|
		desk.asked.any(
			|{ request, .. }|
				match request {
					SetLimit(limit) => limit.scope == scope
					ClearLimit(cleared) => cleared.scope == scope
				},
		)

	## The request a slider at `text` percent makes of a scope: 0 clears
	## its limit.
	request_of : Limits.Scope, Str -> Try(Limits.Request, [NotANumber])
	request_of = |scope, text|
		match U64.from_str(text.trim()) {
			Ok(0) => Ok(ClearLimit({ scope: scope }))
			Ok(asked) => Ok(SetLimit({ scope, percent: U64.min(asked, 100) }))
			Err(_) => Err(NotANumber)
		}

	## A limit in words: "80%", or "No limit" for none.
	limit_text : U64 -> Str
	limit_text = |limit| if (limit == 0) "No limit" else "${limit.to_str()}%"

	## `desk` with a request on its way as `serial`, in place of one of
	## the same scope that waits still.
	asking : State, U64, Limits.Request -> State
	asking = |desk, serial, request| {
		scope = |asked|
			match asked {
				SetLimit(limit) => limit.scope
				ClearLimit(cleared) => cleared.scope
			}
		{ ..desk, asked: desk.asked.drop_if(|old| old.accepted == 0 and scope(old.request) == scope(request)).append({ serial, request, accepted: 0 }) }
	}

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

	## The accounts and their windows as rows, the week's and the 5-hour
	## window's state under their limits; with
	## `summary`, only each account's 5-hour and weekly windows.
	rows : State, Bool -> List(Row)
	rows = |desk, summary|
		desk.reports.join_map(
			|report| {
				named = Str.join_with([report.source, report.account, report.plan].drop_if(Str.is_empty), " · ")
				key = "${report.provider}/${report.source}/${report.account}"
				status = match report.status {
					Available => ""
					Unavailable(why) => why
				}
				mine = |row| row.provider == report.provider and row.source == report.source and row.account == report.account
				week = LimitDesk.weeks(desk).find_first(mine)
				five_hour = LimitDesk.five_hours(desk).find_first(mine)
				windows = if (summary) report.windows.keep_if(|window| window.id == Usage.five_hour_id or window.id == Usage.weekly_id) else report.windows
				heading = if (summary) [] else [{ key, account: Bool.True, title: named, detail: status, percent: 0, state: Ok }]
				heading.concat(
					windows.map(
						|window| {
							used_pct = window.used_pct.map_ok(|used| used.round_to_u64_try() ?? 0) ?? 0
							state = if (window.id == Usage.weekly_id) week.map_ok(|row| row.state) ?? Ok else if (window.id == Usage.five_hour_id) five_hour.map_ok(|row| row.state) ?? Ok else Ok
							{ key: "${key}/${window.id}", account: Bool.False, title: if (summary) "${report.source} ${window.short}" else window.label, detail: window.resets_at ?? "", percent: U64.min(used_pct, 100), state }
						},
					),
				)
			},
		)

	## The meter beside Settings: for the 5-hour window and the week, the
	## account nearest its limit, how full it is of the limit (of the whole
	## window with none set), so full means the reserve is reached, and how
	## near; none before an account tells its usage.
	meter : State -> List({ short : Str, used_pct : U64, limit_pct : Try(U64, [Missing]), fill : U64, state : Limits.State })
	meter = |desk|
		[("5h", LimitDesk.five_hours(desk)), ("wk", LimitDesk.weeks(desk))].keep_oks(
			|(short, windows)| {
				filled = windows.map(|row| { short, used_pct: row.used_pct, limit_pct: row.limit_pct, fill: U64.min(100, (row.used_pct * 100) // U64.max(1, row.limit_pct ?? 100)), state: row.state })
				fullest = filled.map(|row| row.fill).fold(0, U64.max)
				filled.find_first(|row| row.fill == fullest)
			},
		)
}

desk : LimitDesk.State
desk = {
	..LimitDesk.initial,
	reports: [{ provider: "mock", source: "claude", account: "a", plan: "Max", status: Available, windows: [{ id: "five_hour", label: "5-hour", short: "5h", used_pct: Ok(12.4), resets_at: Err(Missing) }, { id: "weekly", label: "Weekly", short: "wk", used_pct: Ok(95), resets_at: Ok("2026-01-05T09:00:00.000Z") }, { id: "opus", label: "Opus", short: "op", used_pct: Err(Missing), resets_at: Err(Missing) }], balances: [] }],
	status: { limits: [{ scope: Default, percent: 80 }], sessions: [{ session_id: "s1", used_pct: 75, limit_pct: Ok(80), state: Near }], weeks: [{ provider: "mock", source: "claude", account: "a", used_pct: 95, limit_pct: Err(Missing), state: Ok, resets_at: Err(Missing) }], five_hours: [] },
}

# A limit on its way shows at once, and is undone if refused.
expect {
	own = LimitDesk.asking(desk, 1, SetLimit({ scope: Session("s1"), percent: 70 }))
	week = LimitDesk.asking(own, 2, SetLimit({ scope: Week, percent: 90 }))
	LimitDesk.session(desk, "s1").map_ok(|row| row.state) == Ok(Near)
		and LimitDesk.session(own, "s1").map_ok(|row| (row.limit_pct, row.state)) == Ok((Ok(70), Over))
		and LimitDesk.pending(own, Session("s1"))
		and LimitDesk.week_of(week, "mock", "claude").map_ok(|row| row.state) == Ok(Over)
		and LimitDesk.answered(own, 1, Refused) == desk
		and LimitDesk.settled(LimitDesk.answered(own, 1, Accepted(4)), 4).asked.is_empty()
		and LimitDesk.percent(LimitDesk.asking(desk, 3, ClearLimit({ scope: Default })), Default) == 0
}

expect LimitDesk.request_of(Week, "0") == Ok(ClearLimit({ scope: Week })) and LimitDesk.request_of(Default, "85") == Ok(SetLimit({ scope: Default, percent: 85 })) and LimitDesk.request_of(Week, "x").is_err()

expect {
	week = LimitDesk.asking(desk, 2, SetLimit({ scope: Week, percent: 90 }))
	LimitDesk.rows(week, Bool.True).map(|row| (row.title, row.percent, row.state)) == [("claude 5h", 12, Ok), ("claude wk", 95, Over)]
		and LimitDesk.rows(desk, Bool.False).map(|row| row.title) == ["claude · a · Max", "5-hour", "Weekly", "Opus"]
}

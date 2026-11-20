## `limits.v1`: limits, each a percent, on how much of its context window a
## session fills and how much of its account's weekly quota an account
## uses, and how near each session and account is to its own. The daemon
## derives it from chat.v1's sessions and usage.v1's reports, keeps the
## limits, warns as one nears, and refuses new messages and agents past it.
Limits := [].{

	## What a limit holds for: one session's context window, every
	## account's weekly window, or the context window of each session
	## without a limit of its own.
	Scope : [Session(Str), Week, Default]

	## A limit: at most `percent` (1 to 100) of what its scope measures.
	Limit : { scope : Scope, percent : U64 }

	## `Ok` below its limit, or with none; `Near` within a tenth of it;
	## `Over` at it or past it.
	State : [Ok, Near, Over]

	## A session's context window: the percent of it its last turn filled,
	## the limit on it, its own or the default (left out with neither), and
	## how near it is.
	SessionStatus : { session_id : Str, used_pct : U64, limit_pct : Try(U64, [Missing]), state : State }

	## An account's weekly window, its provider, source and account as
	## usage.v1 names them: the percent used, the weekly limit (left out
	## while none is set), how near it is, and when it resets.
	WeekStatus : { provider : Str, source : Str, account : Str, used_pct : U64, limit_pct : Try(U64, [Missing]), state : State, resets_at : Try(Str, [Missing]) }

	## The topic `status`'s one event: the limits set, each session whose
	## provider tells what its last turn used, and each account that tells
	## its weekly window.
	Status : { limits : List(Limit), sessions : List(SessionStatus), weeks : List(WeekStatus) }

	## `SetLimit` sets a scope's limit, in place of the one it had;
	## `ClearLimit` clears it. A limit set is enforced: past it, the daemon
	## refuses new messages to the session, or to any session of the
	## account and new agents of its kind, while a turn running goes on.
	Request : [SetLimit(Limit), ClearLimit({ scope : Scope })]

	Response : [Accepted, Rejected(Str)]

	## How near `used` percent is to the limit `limit`, if one is set.
	state_of : U64, Try(U64, [Missing]) -> State
	state_of = |used, limit|
		match limit {
			Ok(most) if used >= most => Over
			Ok(most) if used * 10 >= most * 9 => Near
			_ => Ok
		}

	## The limit of `scope` among `limits`, if one is set.
	limit_of : List(Limit), Scope -> Try(U64, [Missing])
	limit_of = |limits, scope| limits.find_first(|limit| limit.scope == scope).map_ok(|limit| limit.percent).map_err(|_| Missing)

	## The limit on a session's context window: its own, else the default.
	session_limit : List(Limit), Str -> Try(U64, [Missing])
	session_limit = |limits, session_id|
		match Limits.limit_of(limits, Session(session_id)) {
			Ok(percent) => Ok(percent)
			Err(Missing) => Limits.limit_of(limits, Default)
		}

	## Why a limit can't be set, if it can't.
	problem : Limit -> Try({}, Str)
	problem = |{ percent, .. }| if (percent >= 1 and percent <= 100) Ok({}) else Err("a limit is a percent from 1 to 100, not ${percent.to_str()}")
}

expect [(10, Err(Missing)), (50, Ok(80)), (71, Ok(80))].all(|(used, limit)| Limits.state_of(used, limit) == Ok)
expect Limits.state_of(72, Ok(80)) == Near and Limits.state_of(80, Ok(80)) == Over and Limits.state_of(95, Ok(80)) == Over
expect {
	limits = [{ scope: Default, percent: 80 }, { scope: Session("s1"), percent: 50 }, { scope: Week, percent: 90 }]
	Limits.session_limit(limits, "s1") == Ok(50) and Limits.session_limit(limits, "s2") == Ok(80) and Limits.session_limit([], "s2") == Err(Missing) and Limits.limit_of(limits, Week) == Ok(90)
}
expect Limits.problem({ scope: Week, percent: 0 }).is_err() and Limits.problem({ scope: Week, percent: 101 }).is_err() and Limits.problem({ scope: Week, percent: 100 }) == Ok({})

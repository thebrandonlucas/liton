## `usage.v1`: what the accounts agents run under have used of their plans,
## as their providers' usage reports tell: windows such as the 5-hour and
## the weekly limits, each a percent used and when it resets, and balances
## such as credits. A provider asks its backend only while a poll follows
## `reports`.
Usage := [].{

	## A limit of a plan over a window of time: its id (`weekly` for the
	## week's), its label and a short one where space is tight ("5h",
	## "wk"), the percent of it used and when it resets, as
	## 2026-01-01T09:00:00.000Z, each left out when not told.
	Window : { id : Str, label : Str, short : Str, used_pct : Try(Dec, [Missing]), resets_at : Try(Str, [Missing]) }

	## An amount an account spends, such as credits or dollars (its `unit`:
	## `usd`, `credits`, `requests` or `tokens`): how much is used, left and
	## at most, each left out when not told.
	Balance : { id : Str, label : Str, used : Try(Dec, [Missing]), remaining : Try(Dec, [Missing]), limit : Try(Dec, [Missing]), unit : Str }

	## `Available`, or `Unavailable` with why, such as a login that expired.
	Status : [Available, Unavailable(Str)]

	## An account's report: the `provider` that tells it, the `source` it
	## is of, the kind of agent that runs under it (`claude`, `codex`), the
	## account's label and plan ("" when not told), and its windows and
	## balances.
	Report : { provider : Str, source : Str, account : Str, plan : Str, status : Status, windows : List(Window), balances : List(Balance) }

	## `Refresh` asks the providers for their reports again at once, rather
	## than when they next would; the next poll of `reports` shows them.
	Request : [Refresh]

	Response : [Accepted]

	## The id of the window of a week, as Paseo names it.
	weekly_id : Str
	weekly_id = "weekly"

	## The id of the window of 5 hours, as Paseo names it.
	five_hour_id : Str
	five_hour_id = "five_hour"

	## A report's weekly window, if it has one with a percent used.
	weekly : Report -> Try(Window, [NotFound])
	weekly = |report| Usage.window(report, Usage.weekly_id)

	## A report's window `id`, if it has one with a percent used.
	window : Report, Str -> Try(Window, [NotFound])
	window = |report, id| report.windows.find_first(|kept| kept.id == id and kept.used_pct.is_ok())
}

expect {
	week = { id: "weekly", label: "Weekly", short: "wk", used_pct: Ok(41.5), resets_at: Err(Missing) }
	report = { provider: "mock", source: "claude", account: "", plan: "Max", status: Available, windows: [{ ..week, id: "five_hour", label: "5-hour", short: "5h" }, week], balances: [] }
	Usage.weekly(report) == Ok(week) and Usage.weekly({ ..report, windows: [{ ..week, used_pct: Err(Missing) }] }).is_err()
}

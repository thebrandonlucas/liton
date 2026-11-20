## limits.v1 as a transformer: from chat.v1's sessions and usage.v1's
## reports, how near each session is to its context limit and each account
## to its weekly limit (Limits). Its state is the limits set, which `call`
## changes.
import cap.Capability
import cap.Chat
import cap.Limits
import cap.Protocol
import cap.Usage
import Transformer

LimitsTransformer := [].{

	## The `limits` transformer.
	part : Transformer.Part
	part = {
		id: "limits",
		name: "Limits",
		offers: { capability: Capability.limits_v1, patterns: ["status"] },
		uses: [{ capability: "chat.v1", topic: "sessions" }, { capability: "usage.v1", topic: "reports" }],
		follows: |_| [],
		derive: |inputs, stored, _| { state: stored, topics: [{ topic: "status", events: [Limits(LimitsTransformer.status(kept(stored), sessions(inputs), reports(inputs)))] }] },
		call,
		guards: ["chat.v1"],
		guard: |inputs, stored, body| {
			decoded : Try(Protocol.Call(Chat.Request), _)
			decoded = Json.parse(body)
			listed = sessions(inputs)
			match decoded {
				Ok(asked) => LimitsTransformer.refusal(LimitsTransformer.status(kept(stored), listed, reports(inputs)), listed, asked)
				Err(_) => Ok({})
			}
		},
	}

	## How near each session that tells what its last turn used is to its
	## context limit, and each account that tells its weekly window to the
	## weekly limit.
	status : List(Limits.Limit), List(Chat.Session), List(Usage.Report) -> Limits.Status
	status = |limits, listed, accounts| {
		session_rows = listed.keep_oks(
			|session|
				match session.usage.map_ok(|used| (used.context_used, used.context_max)) {
					Ok((Ok(filled), Ok(most))) if most > 0 => {
						used_pct = (filled * 100 + most // 2) // most
						limit_pct = Limits.session_limit(limits, session.id)
						Ok({ session_id: session.id, used_pct, limit_pct, state: Limits.state_of(used_pct, limit_pct) })
					}
					_ => Err(Untold)
				},
		)
		week_limit = Limits.limit_of(limits, Week)
		week_rows = accounts.keep_oks(
			|report|
				match Usage.weekly(report) {
					Ok(window) => {
						used_pct = window.used_pct.map_ok(|percent| percent.round_to_u64_try() ?? 0) ?? 0
						Ok({ provider: report.provider, source: report.source, account: report.account, used_pct, limit_pct: week_limit, state: Limits.state_of(used_pct, week_limit), resets_at: window.resets_at })
					}
					Err(_) => Err(NoWeek)
				},
		)
		{ limits, sessions: session_rows, weeks: week_rows }
	}

	## Why a chat.v1 request is refused, if it is: a message to a session
	## over its context limit, other than `/compact`, which makes room; a
	## message to a session whose account is over its weekly limit; or a
	## new agent of a kind whose account is. A limit not set refuses
	## nothing.
	refusal : Limits.Status, List(Chat.Session), Protocol.Call(Chat.Request) -> Try({}, Str)
	refusal = |shown, listed, { provider, request, .. }| {
		over_week = |provider_id, agent|
			shown.weeks.find_first(|week| week.state == Over and week.source == agent and Protocol.serves(provider_id, week.provider))
		week_refusal = |week| Err("the ${week.source} account is over its weekly limit (${week.used_pct.to_str()}% of ${(week.limit_pct ?? 0).to_str()}%): raise the limit or wait until it resets")
		match request {
			SendMessage({ session_id, text, .. }) => {
				session = listed.find_first(|candidate| candidate.id == session_id)
				context = shown.sessions.find_first(|row| row.session_id == session_id and row.state == Over)
				match (context, session.map_ok(|found| over_week(Ok(found.provider), found.agent))) {
					(Ok(row), _) if !text.trim().starts_with("/compact") => Err("the session is over its context limit (${row.used_pct.to_str()}% of ${(row.limit_pct ?? 0).to_str()}%): compact or start fresh")
					(_, Ok(Ok(week))) => week_refusal(week)
					_ => Ok({})
				}
			}
			Create({ agent, .. }) =>
				match over_week(provider, agent) {
					Ok(week) => week_refusal(week)
					Err(_) => Ok({})
				}
			_ => Ok({})
		}
	}
}

## The limits stored, none at first.
kept : Str -> List(Limits.Limit)
kept = |stored| {
	decoded : Try(List(Limits.Limit), _)
	decoded = Json.parse(stored)
	decoded ?? []
}

sessions : List(Transformer.Input) -> List(Chat.Session)
sessions = |inputs|
	inputs.join_map(|input| input.events).join_map(
		|event|
			match event {
				Sessions(listed) => listed
				_ => []
			},
	)

reports : List(Transformer.Input) -> List(Usage.Report)
reports = |inputs|
	inputs.join_map(|input| input.events).join_map(
		|event|
			match event {
				Reports(listed) => listed
				_ => []
			},
	)

## Sets or clears a limit, or says why it can't.
call : List(Transformer.Input), Str, Str, I64 -> { state : Str, answer : Str }
call = |_, stored, body, _| {
	limits = kept(stored)
	decoded : Try(Protocol.Call(Limits.Request), _)
	decoded = Json.parse(body)
	answered : (List(Limits.Limit), Protocol.Answer(Limits.Response))
	answered =
		match decoded.map_ok(|asked| asked.request) {
			Ok(SetLimit(limit)) =>
				match Limits.problem(limit) {
					Ok({}) => (limits.drop_if(|old| old.scope == limit.scope).append(limit), Ok(Accepted))
					Err(why) => (limits, Ok(Rejected(why)))
				}
			Ok(ClearLimit({ scope })) => (limits.drop_if(|old| old.scope == scope), Ok(Accepted))
			Err(_) => (limits, Err({ code: BadRequest, message: "expected a limits.v1 request" }))
		}
	{ state: if (answered.0 == limits) stored else Json.to_str(answered.0), answer: Json.to_str(answered.1) }
}

fixture : List(Transformer.Input)
fixture = {
	used = |filled| Ok({ context_used: Ok(filled), context_max: Ok(200_000), input_tokens: Err(Missing), cached_input_tokens: Err(Missing), output_tokens: Err(Missing), cost_usd: Err(Missing) })
	listed = [
		{ ..Chat.session({ id: "s1", provider: "mock", agent: "claude", title: "Fix", status: Idle }), usage: used(170_000) },
		{ ..Chat.session({ id: "s2", provider: "mock", agent: "claude", title: "Tidy", status: Idle }), usage: used(40_000) },
		Chat.session({ id: "s3", provider: "mock", agent: "codex", title: "New", status: Idle }),
	]
	week = { id: "weekly", label: "Weekly", short: "wk", used_pct: Ok(91.6), resets_at: Ok("2026-01-05T09:00:00.000Z") }
	[
		{ capability: "chat.v1", topic: "sessions", events: [Sessions(listed)] },
		{ capability: "usage.v1", topic: "reports", events: [Reports([{ provider: "mock", source: "codex", account: "", plan: "", status: Available, windows: [week], balances: [] }])] },
	]
}

called : Str, Str -> { state : Str, answer : Str }
called = |stored, request| (LimitsTransformer.part.call)(fixture, stored, "{\"capability\":\"limits.v1\",\"request\":${request}}", 0)

status_after : Str -> Limits.Status
status_after = |stored| LimitsTransformer.status(kept(stored), sessions(fixture), reports(fixture))

guarded : Str, Str -> Try({}, Str)
guarded = |stored, request| (LimitsTransformer.part.guard)(fixture, stored, "{\"capability\":\"chat.v1\",\"request\":${request}}")

# Without limits, nothing is refused.
expect guarded("", "{\"SendMessage\":{\"session_id\":\"s1\",\"text\":\"Go on\"}}") == Ok({}) and guarded("", "\"Bogus\"") == Ok({})

# Past its context limit, a message to a session is refused but /compact,
# a running turn's steer too; past the weekly limit, an account's sessions
# and new agents are.
expect {
	set = called("", "{\"SetLimit\":{\"scope\":\"Default\",\"percent\":80}}")
	week = called(set.state, "{\"SetLimit\":{\"scope\":\"Week\",\"percent\":90}}")
	weekly = Err("the codex account is over its weekly limit (92% of 90%): raise the limit or wait until it resets")
	guarded(set.state, "{\"SendMessage\":{\"session_id\":\"s1\",\"text\":\"Go on\"}}") == Err("the session is over its context limit (85% of 80%): compact or start fresh")
		and guarded(set.state, "{\"SendMessage\":{\"session_id\":\"s1\",\"text\":\"Go on\",\"while_running\":\"Steer\"}}").is_err()
		and guarded(set.state, "{\"SendMessage\":{\"session_id\":\"s1\",\"text\":\"/compact\"}}") == Ok({})
		and guarded(set.state, "{\"SendMessage\":{\"session_id\":\"s2\",\"text\":\"Go on\"}}") == Ok({})
		and guarded(week.state, "{\"SendMessage\":{\"session_id\":\"s3\",\"text\":\"/compact\"}}") == weekly
		and guarded(week.state, "{\"Create\":{\"place\":{\"Workspace\":\"main\"},\"agent\":\"codex\",\"prompt\":\"\"}}") == weekly
		and guarded(week.state, "{\"Create\":{\"place\":{\"Workspace\":\"main\"},\"agent\":\"claude\",\"prompt\":\"\"}}") == Ok({})
}

# Without limits, each session and week is Ok.
expect {
	shown = status_after("")
	shown.sessions.map(|row| (row.session_id, row.used_pct, row.state)) == [("s1", 85, Ok), ("s2", 20, Ok)] and shown.weeks.map(|week| (week.source, week.used_pct, week.state)) == [("codex", 92, Ok)]
}

# A default limit holds for each session without its own, and the weekly
# one for each account.
expect {
	set = called("", "{\"SetLimit\":{\"scope\":\"Default\",\"percent\":80}}")
	own = called(set.state, "{\"SetLimit\":{\"scope\":{\"Session\":\"s2\"},\"percent\":21}}")
	week = called(own.state, "{\"SetLimit\":{\"scope\":\"Week\",\"percent\":90}}")
	shown = status_after(own.state)
	set.answer == "{\"Ok\":\"Accepted\"}"
		and shown.sessions.map(|row| (row.session_id, row.limit_pct, row.state)) == [("s1", Ok(80), Over), ("s2", Ok(21), Near)]
		and status_after(week.state).weeks.map(|row| (row.limit_pct, row.state)) == [(Ok(90), Over)]
		and status_after(called(own.state, "{\"ClearLimit\":{\"scope\":\"Default\"}}").state).sessions.map(|row| row.state) == [Ok, Near]
}

expect called("", "{\"SetLimit\":{\"scope\":\"Week\",\"percent\":0}}").answer.contains("Rejected") and called("", "\"Bogus\"").answer.contains("BadRequest")

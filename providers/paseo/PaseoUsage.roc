import cap.Usage
import Paseo

## Paseo's usage reports as usage.v1's: from a Paseo whose `server_info`
## lists `usageSources` (from 0.11), its `usage.list_reports.request`,
## answered by a `usage.list_reports.update` per account and then a
## `usage.list_reports.response`; from an older one that lists
## `providerUsageList`, its `provider.usage.list.request`, answered at once.
## A Paseo that lists neither tells no usage.
PaseoUsage := [].{

	## A window of a plan as Paseo sends it, its numbers and times maybe
	## null.
	Window : { id : Str, label : Str, short_label : Try(Str, [Missing]), used_pct : Try(Paseo.Number, [Missing]), resets_at : Try(Paseo.Loose, [Missing]) }

	## A balance as Paseo sends it.
	Balance : { id : Str, label : Str, used : Try(Paseo.Number, [Missing]), remaining : Try(Paseo.Number, [Missing]), limit : Try(Paseo.Number, [Missing]), unit : Str }

	## Why a report is unavailable, such as an expired login.
	Problem : { kind : Str, detail : Try(Str, [Missing]), refreshed_by : Try(Str, [Missing]) }

	## A report: `available` with its windows and balances, `unavailable`
	## with its problem, or `error` with why.
	Report : { status : Str, plan_label : Try(Paseo.Loose, [Missing]), windows : Try(List(Window), [Missing]), balances : Try(List(Balance), [Missing]), problem : Try(Problem, [Missing]), error : Try(Paseo.Loose, [Missing]) }

	## An account's entry in `usage.list_reports.update`, with the last
	## report that was available, which a failed one keeps showing.
	Entry : { account : { label : Try(Str, [Missing]) }, source_id : Str, report : Report, last_successful : Try({ report : Report }, [Missing]) }

	## An account as `provider.usage.list.response` lists it.
	Listed : { provider_id : Str, status : Str, plan_label : Try(Paseo.Loose, [Missing]), windows : List(Window), balances : Try(List(Balance), [Missing]), error : Try(Paseo.Loose, [Missing]) }

	## The request of the reports, as `request_id`, of a Paseo with
	## `features`, or `NoUsage` from one that tells none.
	request : Paseo.Features, Str -> Try(Str, [NoUsage])
	request = |features, request_id|
		if features.usage_sources {
			Ok(Json.to_str({ type: "session", message: { type: "usage.list_reports.request", requestId: request_id } }))
		} else if features.provider_usage_list {
			Ok(Json.to_str({ type: "session", message: { type: "provider.usage.list.request", requestId: request_id } }))
		} else {
			Err(NoUsage)
		}

	## What a message says of the reports asked as `request_id`, each
	## told by `provider`: one account's (`Reported`), that they all came
	## (`Done`) or that asking failed (`Failed`), or, from an older Paseo,
	## them all (`Listed`); `Other` for another message.
	answer : Str, Str, Str -> [Reported(Usage.Report), Listed(List(Usage.Report)), Done, Failed(Str), Other]
	answer = |provider, text, request_id| {
		envelope : Try({ message : { type : Str, payload : { request_id : Try(Str, [Missing]) } } }, _)
		envelope = Json.parser_camel()(text)
		match envelope {
			Ok({ message: { type, payload } }) if payload.request_id == Ok(request_id) =>
				match type {
					"usage.list_reports.update" => {
						updated : Try({ message : { payload : { report : Entry } } }, _)
						updated = Json.parser_camel()(text)
						updated.map_ok(|{ message }| Reported(reported(provider, message.payload.report))) ?? Other
					}
					"usage.list_reports.response" => {
						ended : Try({ message : { payload : { error : Try(Paseo.Loose, [Missing]) } } }, _)
						ended = Json.parser_camel()(text)
						match ended.map_ok(|{ message }| said(message.payload.error)) {
							Ok("") => Done
							Ok(why) => Failed(why)
							Err(_) => Other
						}
					}
					"provider.usage.list.response" => {
						listed : Try({ message : { payload : { providers : List(Listed) } } }, _)
						listed = Json.parser_camel()(text)
						listed.map_ok(|{ message }| Listed(message.payload.providers.map(|account| legacy(provider, account)))) ?? Other
					}
					"rpc_error" => Failed("Paseo couldn't list its usage")
					_ => Other
				}
			_ => Other
		}
	}
}

## A string Paseo may send as null, "" for none.
said : Try(Paseo.Loose, [Missing]) -> Str
said = |field|
	match field {
		Ok(Text(text)) => text
		_ => ""
	}

amount : Try(Paseo.Number, [Missing]) -> Try(Dec, [Missing])
amount = |field|
	match field {
		Ok(Number(value)) => Ok(value)
		_ => Err(Missing)
	}

window : PaseoUsage.Window -> Usage.Window
window = |sent| {
	resets = said(sent.resets_at)
	{ id: sent.id, label: sent.label, short: sent.short_label ?? sent.label, used_pct: amount(sent.used_pct), resets_at: if (resets.is_empty()) Err(Missing) else Ok(resets) }
}

balance : PaseoUsage.Balance -> Usage.Balance
balance = |sent| { id: sent.id, label: sent.label, used: amount(sent.used), remaining: amount(sent.remaining), limit: amount(sent.limit), unit: sent.unit }

## An account's entry as usage.v1's report: its windows and balances, or
## those it last had while its report now fails, with why.
reported : Str, PaseoUsage.Entry -> Usage.Report
reported = |provider, { account, source_id, report, last_successful }| {
	why =
		match (report.status, report.problem) {
			("available", _) => ""
			(_, Ok({ kind: "expired", refreshed_by, .. })) => "the login expired${refreshed_by.map_ok(|by| ": sign in again with ${by}") ?? ""}"
			(_, Ok({ kind: "rejected", .. })) => "the login was refused"
			(_, Ok({ detail, .. })) => detail ?? "no quota"
			_ => if (said(report.error).is_empty()) "unavailable" else said(report.error)
		}
	shown = if (report.status == "available") report else last_successful.map_ok(|last| last.report) ?? report
	{
		provider,
		source: source_id,
		account: account.label ?? "",
		plan: said(shown.plan_label),
		status: if (why.is_empty()) Available else Unavailable(why),
		windows: (shown.windows ?? []).map(window),
		balances: (shown.balances ?? []).map(balance),
	}
}

## An account as an older Paseo lists it, as usage.v1's report.
legacy : Str, PaseoUsage.Listed -> Usage.Report
legacy = |provider, listed| {
	why = said(listed.error)
	{
		provider,
		source: listed.provider_id,
		account: "",
		plan: said(listed.plan_label),
		status: if (listed.status == "available") Available else Unavailable(if (why.is_empty()) "unavailable" else why),
		windows: listed.windows.map(window),
		balances: (listed.balances ?? []).map(balance),
	}
}

session_message : Str -> Str
session_message = |message| "{\"type\":\"session\",\"message\":${message}}"

features : Paseo.Features
features = { agent_config_apply: Bool.False, agent_history_search: Bool.False, background_agents: Bool.False, usage_sources: Bool.True, provider_usage_list: Bool.True, version: Err(Missing) }

expect PaseoUsage.request(features, "u1") == Ok("{\"message\":{\"requestId\":\"u1\",\"type\":\"usage.list_reports.request\"},\"type\":\"session\"}")
expect PaseoUsage.request({ ..features, usage_sources: Bool.False }, "u1") == Ok("{\"message\":{\"requestId\":\"u1\",\"type\":\"provider.usage.list.request\"},\"type\":\"session\"}")
expect PaseoUsage.request({ ..features, usage_sources: Bool.False, provider_usage_list: Bool.False }, "u1") == Err(NoUsage)

# An account's report, its weekly window's null reset left out.
expect {
	update = session_message("{\"type\":\"usage.list_reports.update\",\"payload\":{\"requestId\":\"u1\",\"report\":{\"id\":\"r1\",\"account\":{\"label\":\"me@example.com\"},\"fetchedAt\":\"2026-01-01T09:00:00.000Z\",\"sourceId\":\"claude\",\"sourceLabel\":\"Claude\",\"report\":{\"status\":\"available\",\"planLabel\":\"Max\",\"windows\":[{\"id\":\"five_hour\",\"label\":\"Session\",\"shortLabel\":\"5h\",\"summary\":true,\"usedPct\":12.5,\"remainingPct\":87.5,\"resetsAt\":\"2026-01-01T14:00:00.000Z\",\"tone\":\"ok\"},{\"id\":\"weekly\",\"label\":\"Weekly\",\"usedPct\":41,\"resetsAt\":null}],\"balances\":[{\"id\":\"extra_usage\",\"label\":\"Extra usage\",\"used\":4.2,\"remaining\":null,\"limit\":50,\"unit\":\"usd\"}]}}}}")
	PaseoUsage.answer("paseo", update, "u1") == Reported({ provider: "paseo", source: "claude", account: "me@example.com", plan: "Max", status: Available, windows: [{ id: "five_hour", label: "Session", short: "5h", used_pct: Ok(12.5), resets_at: Ok("2026-01-01T14:00:00.000Z") }, { id: "weekly", label: "Weekly", short: "Weekly", used_pct: Ok(41), resets_at: Err(Missing) }], balances: [{ id: "extra_usage", label: "Extra usage", used: Ok(4.2), remaining: Err(Missing), limit: Ok(50), unit: "usd" }] })
		and PaseoUsage.answer("paseo", update, "u2") == Other
}

# A login that expired keeps the windows it last had, with why.
expect {
	update = session_message("{\"type\":\"usage.list_reports.update\",\"payload\":{\"requestId\":\"u1\",\"report\":{\"id\":\"r2\",\"account\":{},\"fetchedAt\":\"x\",\"sourceId\":\"codex\",\"sourceLabel\":\"Codex\",\"report\":{\"status\":\"unavailable\",\"problem\":{\"kind\":\"expired\",\"expiresAt\":\"2026-01-01T00:00:00Z\",\"refreshedBy\":\"codex\"}},\"lastSuccessful\":{\"fetchedAt\":\"y\",\"report\":{\"status\":\"available\",\"windows\":[{\"id\":\"weekly\",\"label\":\"Weekly\",\"shortLabel\":\"wk\",\"usedPct\":70}]}}}}}")
	match PaseoUsage.answer("box/paseo", update, "u1") {
		Reported(report) => report.status == Unavailable("the login expired: sign in again with codex") and report.windows.map(|shown| shown.used_pct) == [Ok(70)] and report.provider == "box/paseo"
		_ => Bool.False
	}
}

expect PaseoUsage.answer("paseo", session_message("{\"type\":\"usage.list_reports.response\",\"payload\":{\"requestId\":\"u1\",\"error\":null}}"), "u1") == Done
expect PaseoUsage.answer("paseo", session_message("{\"type\":\"usage.list_reports.response\",\"payload\":{\"requestId\":\"u1\",\"error\":\"Usage is off on this host.\"}}"), "u1") == Failed("Usage is off on this host.")
expect {
	listed = session_message("{\"type\":\"provider.usage.list.response\",\"payload\":{\"requestId\":\"u1\",\"fetchedAt\":\"x\",\"providers\":[{\"providerId\":\"claude\",\"displayName\":\"Claude\",\"status\":\"available\",\"planLabel\":null,\"windows\":[{\"id\":\"weekly\",\"label\":\"Weekly\",\"shortLabel\":\"wk\",\"usedPct\":20}]}]}}")
	match PaseoUsage.answer("paseo", listed, "u1") {
		Listed([report]) => report.source == "claude" and report.plan == "" and report.windows.map(|shown| shown.used_pct) == [Ok(20)]
		_ => Bool.False
	}
}

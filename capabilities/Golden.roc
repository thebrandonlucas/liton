## Golden tests: each fixture encodes to exactly its file in tests/, and the
## file decodes back to the fixture, so the wire format changes only on purpose.
import Chat
import Fixtures
import Hosts
import Limits
import Manifest
import Schedules
import Tickets
import Usage

import "tests/manifest.json" as manifest_json : Str
import "tests/requests.json" as requests_json : Str
import "tests/responses.json" as responses_json : Str
import "tests/timeline.json" as timeline_json : Str
import "tests/tickets.json" as tickets_json : Str
import "tests/schedules.json" as schedules_json : Str
import "tests/hosts.json" as hosts_json : Str
import "tests/usage.json" as usage_json : Str
import "tests/limits.json" as limits_json : Str

Golden := [].{}

expect Json.to_str(Fixtures.manifest) == manifest_json.trim()
expect Json.to_str(Fixtures.requests) == requests_json.trim()
expect Json.to_str(Fixtures.responses) == responses_json.trim()
expect Json.to_str(Fixtures.timeline) == timeline_json.trim()

expect {
	decoded : Try(Manifest.Advertised, _)
	decoded = Json.parse(manifest_json)
	decoded == Ok(Fixtures.manifest)
}

expect {
	decoded : Try(List(Chat.Request), _)
	decoded = Json.parse(requests_json)
	decoded == Ok(Fixtures.requests)
}

expect {
	decoded : Try(List(Chat.Response), _)
	decoded = Json.parse(responses_json)
	decoded == Ok(Fixtures.responses)
}

expect {
	decoded : Try(List(Chat.Entry), _)
	decoded = Json.parse(timeline_json)
	decoded == Ok(Fixtures.timeline)
}

expect {
	tickets = { requests: Fixtures.ticket_requests, responses: Fixtures.ticket_responses }
	decoded : Try({ requests : List(Tickets.Request), responses : List(Tickets.Response) }, _)
	decoded = Json.parse(tickets_json)
	Json.to_str(tickets) == tickets_json.trim() and decoded == Ok(tickets)
}

expect {
	schedules = { requests: Fixtures.schedule_requests, responses: Fixtures.schedule_responses }
	decoded : Try({ requests : List(Schedules.Request), responses : List(Schedules.Response) }, _)
	decoded = Json.parse(schedules_json)
	Json.to_str(schedules) == schedules_json.trim() and decoded == Ok(schedules)
}

expect {
	hosts = { requests: Fixtures.host_requests, responses: Fixtures.host_responses }
	decoded : Try({ requests : List(Hosts.Request), responses : List(Hosts.Response) }, _)
	decoded = Json.parse(hosts_json)
	Json.to_str(hosts) == hosts_json.trim() and decoded == Ok(hosts)
}

expect !Json.to_str(Fixtures.host_responses).contains("t0ken")

expect {
	usage = { requests: [Refresh], responses: [Accepted], reports: Fixtures.usage_reports }
	decoded : Try({ requests : List(Usage.Request), responses : List(Usage.Response), reports : List(Usage.Report) }, _)
	decoded = Json.parse(usage_json)
	Json.to_str(usage) == usage_json.trim() and decoded == Ok(usage)
}

expect {
	limits = { requests: Fixtures.limit_requests, responses: [Accepted, Rejected("a limit is a percent from 1 to 100, not 0")], status: Fixtures.limit_status }
	decoded : Try({ requests : List(Limits.Request), responses : List(Limits.Response), status : Limits.Status }, _)
	decoded = Json.parse(limits_json)
	Json.to_str(limits) == limits_json.trim() and decoded == Ok(limits)
}

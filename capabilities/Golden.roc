## Golden tests: each fixture encodes to exactly its file in tests/, and the
## file decodes back to the fixture, so the wire format changes only on purpose.
import Chat
import Fixtures
import Manifest
import Schedules
import Tickets

import "tests/manifest.json" as manifest_json : Str
import "tests/requests.json" as requests_json : Str
import "tests/responses.json" as responses_json : Str
import "tests/timeline.json" as timeline_json : Str
import "tests/tickets.json" as tickets_json : Str
import "tests/schedules.json" as schedules_json : Str

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

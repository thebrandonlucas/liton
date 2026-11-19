## What History panes show of chat.v1's history (docs/protocol.md,
## ListHistory): what is typed in their search, and the sessions the daemon
## listed for it, archived ones too, the latest first, a page at a time.
import cap.Chat

History := [].{

	## A page asked for: of the sessions `search` finds, the first, or those
	## from `cursor` on.
	Asked : { search : Str, cursor : Try(Str, [Missing]) }

	## What is typed in the search and the page asked for last; the sessions
	## listed so far and the cursor of the page after them, if any; the page
	## the daemon answered last, and why it couldn't, "" when it could.
	State : { search : Str, cursor : Try(Str, [Missing]), sessions : List(Chat.Session), next : Try(Str, [Missing]), answered : Try(Asked, [NotAnswered]), failed : Str }

	## Nothing searched or listed yet.
	initial : State
	initial = { search: "", cursor: Err(Missing), sessions: [], next: Err(Missing), answered: Err(NotAnswered), failed: "" }

	## How many sessions a page asks for.
	page_size : U64
	page_size = 50

	## The page to ask for.
	asked : State -> Asked
	asked = |history| { search: history.search, cursor: history.cursor }

	## Whether the page asked for hasn't been answered yet.
	loading : State -> Bool
	loading = |history| history.answered != Ok(History.asked(history))

	## The first page of what `text` finds.
	searched : State, Str -> State
	searched = |history, text| { ..history, search: text, cursor: Err(Missing) }

	## The page after those listed, if there is one.
	more : State -> State
	more = |history|
		match history.next {
			Ok(cursor) => { ..history, cursor: Ok(cursor) }
			Err(Missing) => history
		}

	## Takes the daemon's answer to `page`, unless another was
	## asked for since: a first page's sessions in place of those listed, a
	## later one's after them, or why it failed.
	listed : State, Asked, Try({ sessions : List(Chat.Session), next : Try(Str, [Missing]) }, Str) -> State
	listed = |history, page, answer|
		if page != History.asked(history) {
			history
		} else {
			match answer {
				Ok({ sessions, next }) => {
					kept = if (page.cursor.is_ok()) history.sessions.drop_if(|listed_session| sessions.any(|found| found.id == listed_session.id)) else []
					{ ..history, sessions: kept.concat(sessions), next, answered: Ok(page), failed: "" }
				}
				Err(reason) => { ..history, answered: Ok(page), failed: reason }
			}
		}
}

expect {
	found = |id| Chat.session({ id, provider: "mock", agent: "claude", title: id, status: Idle })
	asked = History.searched(History.initial, "log")
	first = History.listed(asked, History.asked(asked), Ok({ sessions: [found("a"), found("b")], next: Ok("c2") }))
	second = History.more(first)
	both = History.listed(second, History.asked(second), Ok({ sessions: [found("c")], next: Err(Missing) }))
	History.loading(asked) and !History.loading(first) and History.loading(second) and both.sessions.map(|shown| shown.id) == ["a", "b", "c"] and History.more(both) == both
}

# An answer to a page no longer asked for is dropped; a failure says why.
expect {
	asked = History.searched(History.initial, "log")
	stale = History.listed(History.searched(asked, "login"), History.asked(asked), Ok({ sessions: [], next: Err(Missing) }))
	failed = History.listed(asked, History.asked(asked), Err("Paseo can't be reached"))
	History.loading(stale) and failed.failed == "Paseo can't be reached" and !History.loading(failed)
}

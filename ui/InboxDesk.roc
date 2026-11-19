## What an Inbox pane lists of attention.v1's items, each joined with the
## session it is of: those of the tab its `list` option picks, narrowed by
## Focus, its filters and the counter picked, then grouped and sorted as its
## options say. Its options are kept per pane, so a snapshot keeps them.
import cap.Attention
import cap.Context
import Model

InboxDesk := [].{

	## An item as a row shows it: the project its session works in, the
	## provider, model and thinking level ("" when untold), and the group it
	## is of, with how many rows the group has, and whether it is the
	## group's first.
	Row : { item : Attention.Item, project : Str, provider : Str, model : Str, thinking : Str, group : Str, group_count : U64, starts_group : Bool }

	## The filters whose choices come from the rows, by their option's key.
	filters : List({ key : Str, label : Str })
	filters = [{ key: "project", label: "Project" }, { key: "provider", label: "Provider" }, { key: "model", label: "Model" }, { key: "thinking", label: "Thinking" }]

	## Each item joined with its session.
	joined : Model.State -> List(Row)
	joined = |state|
		Model.inbox_items(state).map(
			|item| {
				session = Model.session(state, item.session_id)
				workspace = state.workspaces.workspaces.find_first(|listed| listed.session_ids.contains(item.session_id))
				named = workspace.map_ok(|listed| state.workspaces.projects.find_first(|project| project.id == listed.project_id).map_ok(|project| project.name) ?? "") ?? ""
				directory = session.workspace.map_ok(|place| place.directory.drop_suffix("/").split_last("/").map_ok(|parts| parts.after) ?? place.directory) ?? ""
				{ item, project: if (named.is_empty()) directory else named, provider: item.provider, model: session.model ?? "", thinking: session.thinking ?? "", group: "", group_count: 0, starts_group: Bool.False }
			},
		)

	## What a row holds for a filter.
	field : Row, Str -> Str
	field = |row, key|
		match key {
			"project" => row.project
			"provider" => row.provider
			"model" => row.model
			"thinking" => row.thinking
			_ => ""
		}

	## Whether a row is in a tab: Inbox holds what isn't set aside and needs
	## you, failed, works or is unread, and the session focused, so it stays
	## while read; Snoozed what is set aside; All everything.
	in_tab : Model.State, Str, Row -> Bool
	in_tab = |state, tab, row|
		match tab {
			"All" => Bool.True
			"Snoozed" => row.item.set_aside != No
			_ => row.item.set_aside == No and (row.item.unread or (row.item.state != Done and row.item.state != Idle) or Session(row.item.session_id) == Model.focused(state, [Session, Workspace]))
		}

	## The rows of a pane's tab, Focus and filters: what its counters count.
	counted : Model.State, Model.Pane -> List(Row)
	counted = |state, pane| {
		focus = Model.option(pane, "focus") == "true"
		passes = |row| InboxDesk.filters.all(|filter| Model.option(pane, filter.key).is_empty() or InboxDesk.field(row, filter.key) == Model.option(pane, filter.key))
		InboxDesk.joined(state).keep_if(|row| InboxDesk.in_tab(state, Model.option(pane, "list"), row) and (!focus or row.item.state == NeedsYou) and passes(row))
	}

	## How many rows of a tab the tab's name counts: Inbox's that need you or
	## are unread, every one Snoozed holds, and none for All.
	tab_count : Model.State, Str -> U64
	tab_count = |state, tab| {
		in_it = InboxDesk.joined(state).keep_if(|row| InboxDesk.in_tab(state, tab, row))
		match tab {
			"All" => 0
			"Snoozed" => in_it.len()
			_ => in_it.count_if(|row| row.item.unread or row.item.state == NeedsYou)
		}
	}

	## The counters over a pane's rows, by state, and whether the pane shows
	## only that state.
	counters : Model.State, Model.Pane -> List({ state : Attention.State, label : Str, count : U64, picked : Bool })
	counters = |state, pane| {
		counted_rows = InboxDesk.counted(state, pane)
		[{ attention: NeedsYou, label: "waiting on you" }, { attention: Working, label: "running" }, { attention: Failed, label: "error" }, { attention: Idle, label: "idle" }, { attention: Done, label: "done" }].map(
			|counter| { state: counter.attention, label: counter.label, count: counted_rows.count_if(|row| row.item.state == counter.attention), picked: Model.option(pane, "status") == InboxDesk.state_key(counter.attention) },
		)
	}

	## A state as the `status` option holds it.
	state_key : Attention.State -> Str
	state_key = |attention| Str.inspect(attention)

	## The rows a pane shows: those counted of the state picked, if any, by
	## group then as its sort says, each with its group.
	rows : Model.State, Model.Pane -> List(Row)
	rows = |state, pane| {
		status = Model.option(pane, "status")
		grouping = Model.option(pane, "group")
		grouped = InboxDesk.counted(state, pane).keep_if(|row| status.is_empty() or InboxDesk.state_key(row.item.state) == status).map(|row| { ..row, group: InboxDesk.group_of(grouping, row) })
		descending = Model.option(pane, "direction") == "Descending"
		by_sort = |left, right| {
			ordered = InboxDesk.sort_order(Model.option(pane, "sort"), left, right)
			if (descending) InboxDesk.reversed(ordered) else ordered
		}
		sorted = grouped.sort_with(|left, right| [InboxDesk.group_order(grouping, left, right), by_sort(left, right), Model.text_order(left.item.session_id, right.item.session_id)].find_first(|so_far| so_far != Same) ?? Same)
		sorted.map_with_index(|row, index| { ..row, group_count: if (grouping == "None") 0 else sorted.count_if(|other| other.group == row.group), starts_group: grouping != "None" and (index == 0 or sorted.get(index - 1).map_ok(|before| before.group != row.group) ?? Bool.True) })
	}

	## The group a row is in, by the pane's `group` option, "" for none.
	group_of : Str, Row -> Str
	group_of = |grouping, row|
		match grouping {
			"Project" => if (row.project.is_empty()) "No project" else row.project
			"Provider" => row.provider
			"None" => ""
			_ => InboxDesk.state_title(row.item.state)
		}

	## Groups in order: by status as attention ranks them, else by name.
	group_order : Str, Row, Row -> [Before, After, Same]
	group_order = |grouping, left, right|
		match grouping {
			"Project" | "Provider" => Model.text_order(left.group, right.group)
			"None" => Same
			_ => InboxDesk.numbers(InboxDesk.rank(left), InboxDesk.rank(right))
		}

	## Rows in the order a sort names, ascending: the latest last, by
	## project, by status as attention ranks them, or by title.
	sort_order : Str, Row, Row -> [Before, After, Same]
	sort_order = |sort, left, right| {
		updated = InboxDesk.numbers(Attention.recency(left.item.updated), Attention.recency(right.item.updated))
		match sort {
			"Project" => [Model.text_order(left.project, right.project), InboxDesk.reversed(updated)].find_first(|so_far| so_far != Same) ?? Same
			"Status" => [InboxDesk.numbers(InboxDesk.rank(left), InboxDesk.rank(right)), InboxDesk.reversed(updated)].find_first(|so_far| so_far != Same) ?? Same
			"Title" => Model.text_order(left.item.title, right.item.title)
			_ => updated
		}
	}

	rank : Row -> U64
	rank = |row| Attention.ranks.find_first_index(|ranked| ranked == row.item.state) ?? 0

	numbers : U64, U64 -> [Before, After, Same]
	numbers = |left, right| if (left < right) Before else if (left > right) After else Same

	reversed : [Before, After, Same] -> [Before, After, Same]
	reversed = |ordered|
		match ordered {
			Before => After
			After => Before
			Same => Same
		}

	## A state as a group's heading and a row's status word say it.
	state_title : Attention.State -> Str
	state_title = |attention|
		match attention {
			NeedsYou => "Waiting on you"
			Failed => "Error"
			Working => "Running"
			Done => "Done"
			Idle => "Idle"
		}

	## A filter's choices: All, then each value the tab's rows hold, with
	## how many hold it.
	choices : Model.State, Model.Pane, Str -> List({ value : Str, label : Str })
	choices = |state, pane, key| {
		tabbed = InboxDesk.joined(state).keep_if(|row| InboxDesk.in_tab(state, Model.option(pane, "list"), row))
		values = tabbed.map(|row| InboxDesk.field(row, key)).drop_if(Str.is_empty).fold([], |kept, value| if (kept.contains(value)) kept else kept.append(value)).sort_with(Model.text_order)
		[{ value: "", label: "All (${tabbed.len().to_str()})" }].concat(values.map(|value| { value, label: "${value} (${tabbed.count_if(|row| InboxDesk.field(row, key) == value).to_str()})" }))
	}

	## Where New agent starts one, by the key of its workspace: the one the
	## session focused works in, else the first listed.
	new_agent_key : Model.State -> Try(Str, [NoWorkspace])
	new_agent_key = |state| {
		focused = Model.session_in(state, Model.focused(state, [Session, Workspace]))
		listed = state.workspaces.workspaces
		picked = listed.find_first(|workspace| workspace.session_ids.contains(focused)).on_err(|_| listed.first())
		picked.map_ok(|workspace| Context.to_str(Workspace(workspace.id))).map_err(|_| NoWorkspace)
	}

	## A state as a row's status word says it.
	state_word : Attention.State -> Str
	state_word = |attention|
		match attention {
			NeedsYou => "Waiting"
			Failed => "Error"
			Working => "Running"
			Done => "Done"
			Idle => "Idle"
		}

	## Why a row is listed: what its agent asks, why it failed, that it
	## works, or that what it finished isn't seen yet; or that it is set
	## aside.
	reason : Attention.Item -> Str
	reason = |item|
		match (item.set_aside, item.state) {
			(Snoozed, _) => "Snoozed until something new happens"
			(Settled, _) => "Settled until something new happens"
			(No, NeedsYou) => item.permissions.last().map_ok(|asked| "Asks: ${asked.tool} ${asked.description}") ?? "Waiting on you"
			(No, Failed) => if (item.summary.is_empty()) "Failed" else "Failed: ${item.summary}"
			(No, Working) => "Working"
			(No, _) if item.unread => "Finished: result not seen yet"
			(No, Done) => "Finished"
			(No, Idle) => ""
		}

	## A session's id, short: the first 4 characters of its last part.
	short_id : Str -> Str
	short_id = |session_id| {
		last = session_id.split_last("/").map_ok(|parts| parts.after) ?? session_id
		Str.from_utf8(last.to_utf8().take_first(4)) ?? last
	}

	## The sessions of `rows` selected.
	selected : Model.State, List(Row) -> List(Str)
	selected = |state, listed| listed.map(|row| row.item.session_id).keep_if(|session_id| state.inbox_selected.contains(session_id))

	## Selects a session, or no longer.
	select : Model.State, Str, Bool -> Model.State
	select = |state, session_id, picked| { ..state, inbox_selected: state.inbox_selected.drop_if(|kept| kept == session_id).concat(if (picked) [session_id] else []) }

	## Does to each session selected what `act` does to one, then selects
	## none.
	act_on_selected : Model.State, List(Str), (Model.State, Str -> Model.State) -> Model.State
	act_on_selected = |state, session_ids, act| { ..session_ids.fold(state, act), inbox_selected: [] }
}

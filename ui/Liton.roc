## liton's UI: columns of panes, each a widget bound to a capability the
## daemon advertises, and the effects that keep them current.
import pf.Engine exposing [Elem, In, Root, Row, RowRef, State, Val]
import pf.Html
import cap.Chat
import cap.Manifest
import Model
import Widgets

Liton := [].{
	Ctx : In(Root, Model.State)

	ColumnCtx : Row(Ctx, Model.Column)

	PaneCtx : Row(ColumnCtx, Model.Pane)

	snapshot_key : Str
	snapshot_key = "liton.snapshot"

	program : Engine.Program
	program = Engine.program_boot(
		{ storage_keys: [Liton.snapshot_key], max_inflight: 32 },
		|boot| Engine.state(Model.initial(Engine.boot_storage(boot, Liton.snapshot_key) ?? ""), Liton.page),
	)

	page : State(Ctx, Model.State) -> Elem(Ctx)
	page = |model|
		Html.div(
			"liton",
			[
				Liton.toolbar(model),
				Liton.snapshot_panel(model),
				# Shown by CSS on narrow screens, which show one column at a time.
				Html.div(
					"column-tabs",
					[
						Engine.each(
							model.val().map(|state| state.columns),
							|column| column.id,
							|row|
								Html.button_v(
									row.field(|column| Str.join_with(column.panes.map(|pane| Widgets.find(pane.widget).title), " · ")),
									[Html.flag("aria-pressed", row.key().map2(model.val().lift_row(), |key, state| key == state.active_column))],
									model.lift_row().update_by(row.key(), |state, key| { ..state, active_column: key }),
								),
						),
					],
				),
				Html.div("columns", [Engine.each(model.val().map(|state| state.columns), |column| column.id, |row| Liton.column_view(model, row))]),
			].concat(Liton.effects(model)),
		)

	effects : State(Ctx, Model.State) -> List(Elem(Ctx))
	effects = |model| [
		Engine.watch(
			Engine.const({}),
			|_| [Http({ method: "GET", url: "/api/manifest", headers: [], body: "", timeout_ms: 5000 })],
			model.on_result(
				|state, _, res| {
					decoded : Try(Manifest.Advertised, _)
					decoded = Json.parse(Engine.http_text(res) ?? "")
					match decoded {
						Ok(advertised) => Model.advertise(state, advertised)
						Err(_) => { ..state, notice: "Could not read the daemon's manifest." }
					}
				},
			),
		),
		Engine.watch(Engine.const({}), |_| [Interval(1000)], model.on_result(|state, _, _| { ..state, ticks: state.ticks + 1 })),
		Engine.watch(
			model.val().map(|state| { ticks: state.ticks, watches: Model.watches(state) }),
			|asked| [Http({ method: "POST", url: "/api/chat/poll", headers: [("Content-Type", "application/json")], body: Json.to_str({ watches: asked.watches }), timeout_ms: 5000 })],
			model.on_result(
				|state, _, res| {
					decoded : Try(Chat.Polled, _)
					decoded = Json.parse(Engine.http_text(res) ?? "")
					match decoded {
						Ok(answer) => Model.polled(state, answer)
						Err(_) => state
					}
				},
			),
		),
		Engine.on_change(
			model.val().map(|state| state.outbox),
			|outbox| [Http({ method: "POST", url: "/api/chat", headers: [("Content-Type", "application/json")], body: Json.to_str(outbox.request), timeout_ms: 5000 })],
			model.on_result(
				|state, outbox, res| {
					decoded : Try(Chat.Response, _)
					decoded = Json.parse(Engine.http_text(res) ?? "")
					match decoded {
						Ok(Rejected(reason)) => Model.refused(state, outbox.serial, reason)
						# Polls at once for what the request changed.
						Ok(_) => { ..state, ticks: state.ticks + 1 }
						Err(_) => Model.refused(state, outbox.serial, "The daemon did not answer.")
					}
				},
			),
		),
		Engine.on_change(
			model.val().map(|state| Json.to_str(Model.snapshot(state))),
			|text| [StorageSet(Liton.snapshot_key, text)],
			Engine.ignore({}),
		),
	]

	toolbar : State(Ctx, Model.State) -> Elem(Ctx)
	toolbar = |model|
		Html.div(
			"toolbar",
			[Html.span_v(Engine.const("liton"), [Engine.class("brand")])]
				.concat(
					Widgets.all.map(
						|widget|
							Html.button_v(
								model.val().map(
									|state|
										match Widgets.missing(widget, state.capabilities) {
											[] => "+ ${widget.title}"
											_ => "+ ${widget.title} (unavailable)"
										},
								),
								[Engine.class("add")],
								model.update(|state| Model.add_pane(state, widget.id)),
							),
					),
				)
				.concat([
					Html.button("Snapshot", [Engine.class("snapshot-toggle")], model.update(|state| { ..state, show_snapshot: !state.show_snapshot, snapshot_text: Json.to_str(Model.snapshot(state)) })),
					Html.span_v(model.val().map(|state| state.notice), [Engine.class("notice")]),
				]),
		)

	snapshot_panel : State(Ctx, Model.State) -> Elem(Ctx)
	snapshot_panel = |model|
		Engine.when(
			model.val().map(|state| state.show_snapshot),
			||
				Html.div(
					"snapshot",
					[
						Html.p("This layout as a snapshot. Copy it to share it, or paste one and load it.", ""),
						Html.textarea(Engine.const("Snapshot"), model.val().map(|state| state.snapshot_text), [], model.set_value(|state, text| { ..state, snapshot_text: text })),
						Html.button("Load snapshot", [], model.update(Model.load_snapshot)),
						Html.button("Reset to the Developer preset", [], model.update(|state| Model.layout(state, Model.preset))),
					],
				),
			|| Engine.text(""),
		)

	## A column: a bar of its tabs, when tabbed, and its controls, over its panes.
	column_view : State(Ctx, Model.State), RowRef(Ctx, Model.Column) -> Elem(ColumnCtx)
	column_view = |model0, row| {
		model = model0.lift_row()
		id = row.key()
		column = row.field(|shown| shown)
		classes = column.map2(model.val(), |shown, state| "column${if (shown.tabbed) " tabbed" else ""}${if (shown.id == state.active_column) " shown" else ""}")
		Engine.element(
			"div",
			[Engine.class_v(classes), Engine.attr_v("style", row.field(|shown| "flex-grow: ${shown.size.to_str()}"))],
			[
				Html.div(
					"column-header",
					[
						Engine.each(
							row.field(|shown| shown.panes),
							|pane| pane.id,
							|tab|
								Html.button_v(
									tab.field(|pane| Widgets.find(pane.widget).title),
									[Engine.class("tab"), Html.flag("aria-pressed", tab.key().map2(column.lift_row(), |key, shown| key == shown.active))],
									model.lift_row().update_by(tab.key(), Model.activate_tab),
								),
						),
						Html.button_v(row.field(|shown| if (shown.tabbed) "Stack" else "Tabs"), [Engine.class("layout")], model.update_by(id, Model.toggle_tabs)),
						Html.icon_button("−", Engine.const("Make column narrower"), "resize", model.update_by(id, |state, column_id| Model.resize(state, column_id, Narrower))),
						Html.icon_button("+", Engine.const("Make column wider"), "resize", model.update_by(id, |state, column_id| Model.resize(state, column_id, Wider))),
					],
				),
				Engine.each(row.field(|shown| shown.panes), |pane| pane.id, |pane_row| Liton.pane_view(model, column, pane_row)),
			],
		)
	}

	pane_view : State(ColumnCtx, Model.State), Val(ColumnCtx, Model.Column), RowRef(ColumnCtx, Model.Pane) -> Elem(PaneCtx)
	pane_view = |model0, column, row| {
		model = model0.lift_row()
		id = row.key()
		title = row.field(|pane| Widgets.find(pane.widget).title)
		shown = row.field(|pane| pane).map2(model.val(), |pane, state| { pane: pane, state: state })
		Engine.element(
			"section",
			[Html.aria_label_v(title), Engine.class_v(id.map2(column.lift_row(), |pane_id, group| if (group.tabbed and pane_id != group.active) "pane hidden" else "pane"))],
			[
				Html.div(
					"pane-header",
					[
						Html.span_v(title, [Engine.class("pane-title")]),
						Html.span_v(shown.map(|{ pane, state }| Liton.context_label(state, pane)), [Engine.class("pane-context")]),
						Engine.when(
							shown.map(|{ pane, state }| Widgets.find(pane.widget).follows_session and Model.session(state, Model.session_of(state, pane)).status == AwaitingPermission and (Model.loading(state, Model.session_of(state, pane)) or Model.pending(state, pane.id).is_ok())),
							|| Html.span_v(Engine.const("waiting for you"), [Engine.class("badge waiting"), Engine.test_id("session-status")]),
							|| Engine.text(""),
						),
						Engine.when(
							row.field(|pane| Widgets.find(pane.widget).follows_session),
							|| Html.button_v(row.field(|pane| if (pane.pinned.is_empty()) "Pin" else "Unpin"), [Engine.class("pin")], model.update_by(id, Model.toggle_pin)),
							|| Engine.text(""),
						),
						Html.icon_button("←", title.map(|name| "Move ${name} left"), "move", model.update_by(id, |state, pane_id| Model.move_pane(state, pane_id, Left))),
						Html.icon_button("→", title.map(|name| "Move ${name} right"), "move", model.update_by(id, |state, pane_id| Model.move_pane(state, pane_id, Right))),
						Html.button("×", [Html.aria_label("Close pane"), Engine.class("close")], model.update_by(id, Model.close_pane)),
					],
				),
				Engine.switch(
					shown.map(|{ pane, state }| Model.body(state, pane)),
					[Sessions, Chat, Capabilities, Connecting, Missing],
					|body|
						match body {
							Sessions => Liton.sessions(model)
							Chat => Liton.chat(model, id, shown)
							Capabilities => Liton.capabilities(model)
							Connecting => Html.p("Connecting to the daemon…", "missing")
							Missing =>
								Html.p_v(
									shown.map(|{ pane, state }| "This widget needs ${Model.missing(state, pane)}, which no connected provider supplies. Connect one that does, and it fills in here."),
									[Engine.class("missing")],
								)
						},
				),
			],
		)
	}

	context_label : Model.State, Model.Pane -> Str
	context_label = |state, pane|
		if (!Widgets.find(pane.widget).follows_session)
			""
		else {
			title = Model.session(state, Model.session_of(state, pane)).title
			if (pane.pinned.is_empty()) "following ${title}" else "pinned to ${title}"
		}

	sessions : State(PaneCtx, Model.State) -> Elem(PaneCtx)
	sessions = |model0|
		Html.ul(
			[Engine.class("sessions")],
			[
				Engine.each(
					model0.val().map(|state| state.sessions),
					|session| session.id,
					|row| {
						model = model0.lift_row()
						Html.li(
							[Engine.class_v(row.key().map2(model.val(), |key, state| if (key == state.focus) "session focused" else "session"))],
							[
								Html.button_v(row.field(|session| "${session.title}"), [], model.update_by(row.key(), |state, key| { ..state, focus: key })),
								Html.div(
									"session-meta",
									[
										Engine.text_v(row.field(|session| session.agent)),
										Html.span_v(row.field(|session| Liton.status_text(session.status)), [Engine.class_v(row.field(|session| Liton.badge_class(session.status))), Engine.test_id("session-status")]),
									],
								),
							],
						)
					},
				),
			],
		)

	chat : State(PaneCtx, Model.State), Val(PaneCtx, Str), Val(PaneCtx, { pane : Model.Pane, state : Model.State }) -> Elem(PaneCtx)
	chat = |model0, id, shown| {
		pending = id.map2(model0.val(), |pane_id, state| Model.pending(state, pane_id))
		Html.div(
			"chat",
			[
				# Reversed in CSS, so the scroll position stays on the newest entry.
				Html.div(
					"timeline-scroll",
					[
						Html.ul(
							[Engine.class("timeline")],
							[
								Engine.each(
									shown.map(|{ pane, state }| Model.with_tool_cards(Model.entries(state, Model.session_of(state, pane)))),
									|entry| entry.sequence.to_str(),
									|row|
										Html.li(
											[Engine.class_v(row.field(|entry| Liton.entry_class(entry.event)))],
											[
												Engine.when(
													row.field(|entry| entry.card.is_ok()),
													|| Liton.tool_card(row.field(|entry| entry.card ?? { tool: "", input: "", state: Running, output: "", folded: "" })),
													|| Html.pre_v(row.field(|entry| Liton.describe(entry.event)), []),
												),
											],
										),
								),
								Engine.each(
									shown.map(|{ pane, state }| Model.unconfirmed(state, Model.session_of(state, pane))),
									|sent| sent.serial.to_str(),
									|row|
										Html.li(
											[Engine.class_v(row.field(|sent| Liton.sent_class(sent)))],
											[
												Html.pre_v(row.field(|sent| Liton.sent_text(sent.request)), []),
												Html.span_v(row.field(|sent| Liton.sent_status(sent)), [Engine.class("sent-status"), Engine.test_id("sent-status")]),
												Engine.when(
													row.field(|sent| !sent.failed.is_empty()),
													|| Html.button("Retry", [], model0.lift_row().update_by(row.key(), Model.retry)),
													|| Engine.text(""),
												),
											],
										),
								),
							],
						),
					],
				),
				Engine.when(
					shown.map(|{ pane, state }| Model.loading(state, Model.session_of(state, pane))),
					|| Html.p("Loading…", "missing"),
					|| Engine.text(""),
				),
				Engine.when(
					pending.map(|waiting| waiting.is_ok()),
					||
						Html.div(
							"permission",
							[
								Html.span_v(pending.map(|waiting| waiting.map_ok(|asked| "Allow ${asked.tool}: ${asked.description}?") ?? ""), []),
								Html.button("Allow", [Engine.class("allow")], model0.update_by(id, |state, pane_id| Model.answer(state, pane_id, Bool.True))),
								Html.button("Deny", [Engine.class("deny")], model0.update_by(id, |state, pane_id| Model.answer(state, pane_id, Bool.False))),
							],
						),
					|| Engine.text(""),
				),
				Html.form(
					"Send a message",
					[Engine.class("composer"), Engine.on("submit:prevent", model0.update_by(id, Model.submit))],
					[
						Html.text_input(Engine.const("Message"), "text", id.map2(model0.val(), |pane_id, state| Model.draft(state, pane_id)), [Engine.attr("placeholder", "Message the agent")], model0.set_value_by(id, Model.set_draft)),
						Html.submit_button("Send", []),
					],
				),
			],
		)
	}

	capabilities : State(PaneCtx, Model.State) -> Elem(PaneCtx)
	capabilities = |model|
		Html.pre_v(
			model.val().map(
				|state|
					Str.join_with(
						state.providers.map(|provider| "${provider.name} (${provider.id})\n${Str.join_with(provider.capabilities.map(|id| "  ${id.name}.v${id.version.to_str()}"), "\n")}"),
						"\n\n",
					),
			),
			[Engine.class("manifest")],
		)

	status_text : Chat.Status -> Str
	status_text = |status|
		match status {
			Idle => "idle"
			Running => "running"
			AwaitingPermission => "waiting for you"
			Finished => "finished"
			Failed(reason) => "failed: ${reason}"
		}

	badge_class : Chat.Status -> Str
	badge_class = |status|
		match status {
			AwaitingPermission => "badge waiting"
			Failed(_) => "badge failed"
			_ => "badge"
		}

	## A tool call's name and state over its input, then its output with all
	## but the first lines folded away.
	tool_card : Val(ctx, Model.ToolCard) -> Elem(ctx)
	tool_card = |card| {
		state = card.map(
			|shown|
				match shown.state {
					Running => "running"
					Done => "done"
					Failed => "failed"
				},
		)
		Html.div_attrs(
			[Engine.class_v(state.map(|name| "tool-card ${name}"))],
			[
				Html.div(
					"tool-header",
					[
						Html.span_v(card.map(|shown| shown.tool), [Engine.class("tool-name")]),
						Html.span_v(state, [Engine.class_v(state.map(|name| "badge ${name}")), Engine.test_id("tool-state")]),
					],
				),
				Html.pre_v(card.map(|shown| shown.input), [Engine.class("tool-input")]),
				Html.pre_v(card.map(|shown| shown.output), [Engine.class("tool-output")]),
				Engine.when(
					card.map(|shown| !shown.folded.is_empty()),
					||
						Engine.element(
							"details",
							[],
							[
								Engine.element("summary", [], [Engine.text_v(card.map(|shown| "${shown.folded.split_on("\n").len().to_str()} more lines"))]),
								Html.pre_v(card.map(|shown| shown.folded), [Engine.class("tool-output")]),
							],
						),
					|| Engine.text(""),
				),
			],
		)
	}

	describe : Chat.Event -> Str
	describe = |event|
		match event {
			UserMessage({ text }) => text
			AgentMessage({ text }) => text
			ToolCall({ tool, input, .. }) => "${tool}: ${input}"
			ToolResult({ output, .. }) => output
			PermissionRequested({ tool, description, .. }) => "asks to ${tool}: ${description}"
			PermissionAnswered({ allowed, .. }) => if (allowed) "allowed" else "denied"
			StatusChanged(status) => Liton.status_text(status)
		}

	sent_text : Chat.Request -> Str
	sent_text = |request|
		match request {
			SendMessage({ text, .. }) => text
			AnswerPermission({ allowed, .. }) => if (allowed) "Allowing…" else "Denying…"
			_ => ""
		}

	## A message's state; an answer's is in its text.
	sent_status : Model.Sent -> Str
	sent_status = |sent|
		match sent.request {
			SendMessage(_) => if (sent.failed.is_empty()) "Sending…" else "Not sent: ${sent.failed}"
			_ => ""
		}

	sent_class : Model.Sent -> Str
	sent_class = |sent|
		match sent.request {
			SendMessage(_) => if (sent.failed.is_empty()) "entry user pending" else "entry user failed"
			_ => "entry answer pending"
		}

	entry_class : Chat.Event -> Str
	entry_class = |event|
		match event {
			UserMessage(_) => "entry user"
			AgentMessage(_) => "entry agent"
			ToolCall(_) => "entry tool"
			ToolResult({ failed, .. }) => if (failed) "entry result failed" else "entry result"
			PermissionRequested(_) => "entry permission"
			PermissionAnswered(_) => "entry answer"
			StatusChanged(_) => "entry status"
		}
}

## liton's UI: columns of panes, each a widget bound to a capability the
## daemon advertises, and the effects that keep them current.
import pf.Engine exposing [Elem, In, Root, Row, RowRef, State, Val]
import pf.Html
import cap.Attention
import cap.Capability
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
				Liton.settings(model),
				# Shown by CSS on narrow screens: Tiling shows the column picked here,
				# and a Workbench, which is swiped through, scrolls to it.
				Html.div(
					"column-tabs",
					[
						Engine.each(
							model.val().map(|state| state.columns),
							|column| column.id,
							|row|
								Html.button_v(
									row.field(|column| column).map2(model.val().lift_row(), |column, state| Str.join_with(column.panes.map(|pane| Liton.label(state, pane)), " · ")),
									[
										Html.flag("aria-pressed", row.key().map2(model.val().lift_row(), |key, state| key == state.active_column)),
										Engine.test_id_v(row.key().map2(model.val().lift_row(), |key, state| "show-${Model.slot_name(Model.slot_of(state, key))}")),
									],
									model.lift_row().update_by(row.key(), Model.show_column),
								),
						),
					],
				),
				Html.div_v(
					model.val().map(|state| if (state.shell == Workbench) "columns workbench" else "columns tiling"),
					[Engine.each(model.val().map(|state| state.columns), |column| column.id, |row| Liton.column_view(model, row))],
				),
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
		Engine.watch(
			model.val().map(|state| { ticks: state.ticks, advertised: state.capabilities.contains(Capability.attention_v1) }),
			|asked| if (asked.advertised) [Http({ method: "GET", url: "/api/attention", headers: [], body: "", timeout_ms: 5000 })] else [],
			model.on_result(
				|state, asked, res| {
					decoded : Try(List(Attention.Item), _)
					decoded = Json.parse(Engine.http_text(res) ?? "")
					match decoded {
						Ok(items) => Model.attention_fetched(state, asked.ticks, items)
						Err(_) => state
					}
				},
			),
		),
		Engine.on_change(
			model.val().map(|state| state.attention_outbox),
			|outbox| [Http({ method: "POST", url: "/api/attention", headers: [("Content-Type", "application/json")], body: Json.to_str(outbox.request), timeout_ms: 5000 })],
			model.on_result(
				|state, outbox, res| {
					decoded : Try(Attention.Response, _)
					decoded = Json.parse(Engine.http_text(res) ?? "")
					Model.set_aside_answered(state, outbox.serial, decoded ?? Rejected("The daemon did not answer."))
				},
			),
		),
		Engine.watch(model.val().map(Model.needs_you), |count| [Title(if (count == 0) "liton" else "(${count.to_str()}) liton")], Engine.ignore({})),
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
		Engine.watch(model.val().map(|state| state.jump), |jump| if (jump.panel.is_empty()) [] else [Focus(jump.panel)], Engine.ignore({})),
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
			[
				Html.span_v(Engine.const("liton"), [Engine.class("brand")]),
				Engine.when(
					model.val().map(|state| state.shell == Workbench),
					|| Html.div("drawer-toggles", [Liton.drawer_toggle(model, Left, "◧", "Left drawer"), Liton.drawer_toggle(model, Right, "◨", "Right drawer")]),
					|| Engine.text(""),
				),
				Html.button("Settings", [Engine.class("settings-toggle"), Html.flag("aria-expanded", model.val().map(|state| state.show_settings))], model.update(|state| Model.with_snapshot_text({ ..state, show_settings: !state.show_settings }))),
				Html.span_v(model.val().map(|state| state.notice), [Engine.class("notice")]),
			],
		)

	drawer_toggle : State(Ctx, Model.State), Model.Slot, Str, Str -> Elem(Ctx)
	drawer_toggle = |model, drawer, glyph, name|
		Html.button(glyph, [Html.aria_label(name), Html.flag("aria-expanded", model.val().map(|state| !state.collapsed.contains(drawer)))], model.update(|state| Model.toggle_drawer(state, drawer)))

	## Picks the preset, adds widgets, and shows the layout as a snapshot.
	settings : State(Ctx, Model.State) -> Elem(Ctx)
	settings = |model|
		Engine.when(
			model.val().map(|state| state.show_settings),
			||
				Html.section(
					"Settings",
					"settings",
					[
						Html.h3("Preset", ""),
						Html.div(
							"choices",
							[
								Html.button("Developer preset", [Html.flag("aria-pressed", model.val().map(|state| state.shell == Workbench and !Liton.inbox_preset(state)))], model.update(|state| Model.with_snapshot_text(Model.layout(state, Model.developer)))),
								Html.button("Inbox preset", [Html.flag("aria-pressed", model.val().map(Liton.inbox_preset))], model.update(|state| Model.with_snapshot_text(Model.toggle_drawer(Model.layout(state, Model.inbox), Right)))),
								Html.button("Tiling preset", [Html.flag("aria-pressed", model.val().map(|state| state.shell == Tiling))], model.update(|state| Model.with_snapshot_text(Model.layout(state, Model.tiling)))),
							],
						),
						Html.h3("Add a widget", ""),
						Html.div(
							"choices",
							Widgets.all.map(
								|widget|
									Html.button_v(
										model.val().map(|state| if (Widgets.missing(widget, state.capabilities).is_empty()) "+ ${widget.title}" else "+ ${widget.title} (unavailable)"),
										[],
										model.update(|state| Model.with_snapshot_text(Model.add_pane(state, widget.id))),
									),
							),
						),
						Html.h3("Snapshot", ""),
						Html.p("This layout as a snapshot. Copy it to share it, or paste one and load it.", ""),
						Html.textarea(Engine.const("Snapshot"), model.val().map(|state| state.snapshot_text), [], model.set_value(|state, text| { ..state, snapshot_text: text })),
						Html.div("choices", [Html.button("Load snapshot", [], model.update(Model.load_snapshot))]),
					],
				),
			|| Engine.text(""),
		)

	## A column: a bar of its tabs, when tabbed, and its controls, over its
	## panes. In a Workbench it is a slot, without the controls.
	column_view : State(Ctx, Model.State), RowRef(Ctx, Model.Column) -> Elem(ColumnCtx)
	column_view = |model0, row| {
		model = model0.lift_row()
		id = row.key()
		column = row.field(|shown| shown)
		slot = id.map2(model.val(), |column_id, state| Model.slot_of(state, column_id))
		tiling = model.val().map(|state| state.shell == Tiling)
		classes = column.map2(model.val(), |shown, state| Liton.column_class(state, shown))
		Engine.element(
			"div",
			[
				Engine.class_v(classes),
				Engine.test_id_v(slot.map(|shown| "slot-${Model.slot_name(shown)}")),
				Engine.attr_v("style", column.map2(model.val(), |shown, state| if (state.shell == Tiling) "flex-grow: ${shown.size.to_str()}" else "")),
				# Swiping shows no state, but using a panel says it is the one shown.
				Engine.on("focus", model.update_by(id, |state, column_id| { ..state, active_column: column_id })),
			],
			[
				Engine.switch(
					slot,
					[Left, Main, Right, Free],
					|shown| if (shown == Free) Engine.text("") else Engine.element("span", [Engine.ref(Model.panel_ref(shown)), Engine.attr("tabindex", "-1"), Engine.class("panel-anchor")], []),
				),
				Html.div(
					"column-header",
					[
						Engine.each(
							row.field(|shown| shown.panes),
							|pane| pane.id,
							|tab|
								Html.button_v(
									tab.field(|pane| pane).map2(model.val().lift_row(), |pane, state| Liton.label(state, pane)),
									[Engine.class("tab"), Html.flag("aria-pressed", tab.key().map2(column.lift_row(), |key, shown| key == shown.active))],
									model.lift_row().update_by(tab.key(), Model.activate_tab),
								),
						),
						Engine.when(
							tiling,
							||
								Html.div(
									"column-controls",
									[
										Html.button_v(row.field(|shown| if (shown.tabbed) "Stack" else "Tabs"), [], model.update_by(id, Model.toggle_tabs)),
										Html.icon_button("−", Engine.const("Make column narrower"), "resize", model.update_by(id, |state, column_id| Model.resize(state, column_id, Narrower))),
										Html.icon_button("+", Engine.const("Make column wider"), "resize", model.update_by(id, |state, column_id| Model.resize(state, column_id, Wider))),
									],
								),
							|| Engine.text(""),
						),
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
						Html.span_v(shown.map(|{ pane, state }| Liton.label(state, pane)), [Engine.class("pane-title")]),
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
						Engine.when(
							model.val().map(|state| state.shell == Tiling),
							||
								Html.div(
									"moves",
									[
										Html.icon_button("←", title.map(|name| "Move ${name} left"), "move", model.update_by(id, |state, pane_id| Model.move_pane(state, pane_id, Left))),
										Html.icon_button("→", title.map(|name| "Move ${name} right"), "move", model.update_by(id, |state, pane_id| Model.move_pane(state, pane_id, Right))),
									],
								),
							|| Engine.text(""),
						),
						Html.button("×", [Html.aria_label("Close pane"), Engine.class("close")], model.update_by(id, Model.close_pane)),
					],
				),
				Engine.switch(
					shown.map(|{ pane, state }| Model.body(state, pane)),
					[Sessions, Chat, Inbox, Capabilities, Connecting, Missing],
					|body|
						match body {
							Sessions => Liton.sessions(model)
							Chat => Liton.chat(model, id, shown)
							Inbox => Liton.inbox(model)
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

	column_class : Model.State, Model.Column -> Str
	column_class = |state, column| {
		slot = Model.slot_of(state, column.id)
		classes = [
			if (slot == Free) "" else "slot slot-${Model.slot_name(slot)}",
			if (column.tabbed) "tabbed" else "",
			if (column.id == state.active_column) "shown" else "",
			if (state.collapsed.contains(slot)) "collapsed" else "",
		]
		Str.join_with(classes.drop_if(|class| class.is_empty()).prepend("column"), " ")
	}

	## A pane's title, the inbox's with how many items need you.
	label : Model.State, Model.Pane -> Str
	label = |state, pane| {
		title = Widgets.find(pane.widget).title
		count = Model.needs_you(state)
		if (pane.widget == "inbox" and count > 0) "${title} (${count.to_str()})" else title
	}

	inbox_preset : Model.State -> Bool
	inbox_preset = |state| state.shell == Workbench and (state.columns.first().map_ok(|column| column.panes.any(|pane| pane.widget == "inbox")) ?? Bool.False)

	## What needs you, then what failed, is done or working, then what you set
	## aside, folded away.
	inbox : State(PaneCtx, Model.State) -> Elem(PaneCtx)
	inbox = |model|
		Html.div(
			"inbox",
			[
				Liton.inbox_section(model, "Needs you", |state| Model.waiting(state, NeedsYou)),
				Liton.inbox_section(model, "Failed", |state| Model.waiting(state, Failed)),
				Liton.inbox_section(model, "Done", |state| Model.waiting(state, Done)),
				Liton.inbox_section(model, "Working", |state| Model.waiting(state, Working)),
				Engine.when(
					model.val().map(|state| !Model.later(state).is_empty()),
					||
						Engine.element(
							"details",
							[Engine.class("inbox-later"), Engine.test_id("later")],
							[Engine.element("summary", [], [Engine.text_v(model.val().map(|state| "Later (${Model.later(state).len().to_str()})"))]), Liton.inbox_items(model, Model.later)],
						),
					|| Engine.text(""),
				),
			],
		)

	inbox_section : State(PaneCtx, Model.State), Str, (Model.State -> List(Attention.Item)) -> Elem(PaneCtx)
	inbox_section = |model, name, items|
		Engine.when(
			model.val().map(|state| !items(state).is_empty()),
			|| Html.div("inbox-section", [Html.h3(name, ""), Liton.inbox_items(model, items)]),
			|| Engine.text(""),
		)

	## Each item: its title, which opens it, its agent, state and summary, the
	## permission it asks for, and Settle and Snooze, or Bring back once set aside.
	inbox_items : State(PaneCtx, Model.State), (Model.State -> List(Attention.Item)) -> Elem(PaneCtx)
	inbox_items = |model0, items|
		Html.ul(
			[Engine.class("inbox-items")],
			[
				Engine.each(
					model0.val().map(items),
					|item| item.session_id,
					|row| {
						model = model0.lift_row()
						id = row.key()
						title = row.field(|item| item.title)
						permission = id.map2(model.val(), |session_id, state| Model.item_permission(state, session_id))
						Html.li(
							[Engine.class_v(id.map2(model.val(), |key, state| if (key == state.focus) "inbox-item focused" else "inbox-item"))],
							[
								Html.button_v(title, [], model.update_by(id, Model.open_item)),
								Html.div(
									"session-meta",
									[
										Engine.text_v(row.field(|item| item.agent)),
										Html.span_v(row.field(|item| Liton.attention_text(item.state)), [Engine.class_v(row.field(|item| Liton.attention_class(item.state))), Engine.test_id("attention-state")]),
									],
								),
								Html.p_v(row.field(|item| item.summary), [Engine.class("summary")]),
								Engine.when(
									permission.map(|asked| asked.is_ok()),
									||
										Html.div(
											"permission",
											[
												Html.span_v(permission.map(|asked| asked.map_ok(|{ tool, description, .. }| "Allow ${tool}: ${description}?") ?? ""), []),
												Html.button("Allow", [Engine.class("allow"), Html.aria_label_v(title.map(|name| "Allow ${name}"))], model.update_by(id, |state, session_id| Model.answer_item(state, session_id, Bool.True))),
												Html.button("Deny", [Engine.class("deny"), Html.aria_label_v(title.map(|name| "Deny ${name}"))], model.update_by(id, |state, session_id| Model.answer_item(state, session_id, Bool.False))),
											],
										),
									|| Engine.text(""),
								),
								Html.span_v(id.map2(model.val(), |session_id, state| Str.join_with(Model.unconfirmed(state, session_id).keep_oks(Liton.answering), " ")), [Engine.class("sent-status"), Engine.test_id("answer-status")]),
								Engine.when(
									row.field(|item| item.set_aside == No),
									||
										Html.div(
											"inbox-actions",
											[
												Html.button("Settle", [Html.aria_label_v(title.map(|name| "Settle ${name}"))], model.update_by(id, |state, session_id| Model.set_aside(state, session_id, Settled))),
												Html.button("Snooze 1 h", [Html.aria_label_v(title.map(|name| "Snooze ${name}"))], model.update_by(id, |state, session_id| Model.set_aside(state, session_id, Snoozed))),
											],
										),
									|| Html.div("inbox-actions", [Html.button("Bring back", [Html.aria_label_v(title.map(|name| "Bring back ${name}"))], model.update_by(id, |state, session_id| Model.set_aside(state, session_id, No)))]),
								),
							],
						)
					},
				),
			],
		)

	## "Allowing…" or "Denying…" for an answer on its way.
	answering : Model.Sent -> Try(Str, [NotAnswer])
	answering = |sent|
		match sent.request {
			AnswerPermission(_) => Ok(Liton.sent_text(sent.request))
			_ => Err(NotAnswer)
		}

	attention_text : Attention.State -> Str
	attention_text = |state|
		match state {
			NeedsYou => "needs you"
			Failed => "failed"
			Working => "working"
			Done => "done"
			Idle => "idle"
		}

	attention_class : Attention.State -> Str
	attention_class = |state|
		match state {
			NeedsYou => "badge waiting"
			Failed => "badge failed"
			_ => "badge"
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

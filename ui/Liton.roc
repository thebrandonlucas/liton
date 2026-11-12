## liton's UI: a row of panes, each a widget bound to a capability the
## daemon advertises, and the effects that keep them current.
import pf.Engine exposing [Elem, In, Root, Row, RowRef, State, Val]
import pf.Html
import cap.Chat
import cap.Manifest
import Model
import Widgets

Liton := [].{
	Ctx : In(Root, Model.State)

	PaneCtx : Row(Ctx, Model.Pane)

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
				Html.div(
					"panes",
					[Engine.each(model.val().map(|state| state.panes), |pane| pane.id, |row| Liton.pane_view(model, row))],
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
		Engine.on_change(
			model.val().map(|state| state.outbox),
			|outbox| [Http({ method: "POST", url: "/api/chat", headers: [("Content-Type", "application/json")], body: Json.to_str(outbox.request), timeout_ms: 5000 })],
			model.on_result(
				|state, _, res| {
					decoded : Try(Chat.Response, _)
					decoded = Json.parse(Engine.http_text(res) ?? "")
					match decoded {
						Ok(Rejected(reason)) => { ..state, notice: reason }
						Ok(_) => state
						Err(_) => { ..state, notice: "The daemon did not answer." }
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
						Html.button("Reset to the Developer preset", [], model.update(|state| { ..state, panes: Model.preset, next_pane: Model.preset.len() + 1 })),
					],
				),
			|| Engine.text(""),
		)

	pane_view : State(Ctx, Model.State), RowRef(Ctx, Model.Pane) -> Elem(PaneCtx)
	pane_view = |model0, row| {
		model = model0.lift_row()
		id = row.key()
		shown = row.field(|pane| pane).map2(model.val(), |pane, state| { pane: pane, state: state })
		Html.section_v(
			row.field(|pane| Widgets.find(pane.widget).title),
			"pane",
			[
				Html.div(
					"pane-header",
					[
						Html.span_v(row.field(|pane| Widgets.find(pane.widget).title), [Engine.class("pane-title")]),
						Html.span_v(shown.map(|{ pane, state }| Liton.context_label(state, pane)), [Engine.class("pane-context")]),
						Engine.when(
							row.field(|pane| Widgets.find(pane.widget).follows_session),
							|| Html.button_v(row.field(|pane| if (pane.pinned.is_empty()) "Pin" else "Unpin"), [Engine.class("pin")], model.update_by(id, Model.toggle_pin)),
							|| Engine.text(""),
						),
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
			session_id = Model.session_of(state, pane)
			if (pane.pinned.is_empty()) "following ${session_id}" else "pinned to ${session_id}"
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
								Html.span_v(row.field(|session| "${session.agent} · ${Liton.status_text(session.status)}"), [Engine.class("session-meta")]),
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
									shown.map(|{ pane, state }| Model.entries(state, Model.session_of(state, pane))),
									|entry| entry.sequence.to_str(),
									|row|
										Html.li(
											[Engine.class_v(row.field(|entry| Liton.entry_class(entry.event)))],
											[Html.pre_v(row.field(|entry| Liton.describe(entry.event)), [])],
										),
								),
							],
						),
					],
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
					"Message",
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

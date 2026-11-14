## liton's UI: columns of panes, each a widget bound to a capability the
## daemon advertises, and the effects that keep them current.
import pf.Engine exposing [Elem, Handler, In, Root, Row, RowRef, Signal, State]
import pf.Html
import cap.Attention
import cap.Capability
import cap.Chat
import cap.Manifest
import cap.Protocol
import cap.WorkspaceGit
import setup.Setup
import Highlight
import Markdown
import Ports
import Themes
import Model
import Widgets

Liton := [].{
	Ctx : In(Root, Model.State)

	ColumnCtx : Row(Ctx, Model.Column)

	PaneCtx : Row(ColumnCtx, Model.Pane)

	snapshot_key : Str
	snapshot_key = "liton.snapshot"

	## Whether tiles blur what is behind them, "on" or "off": this browser's,
	## not the snapshot's, as it is about the device.
	glass_key : Str
	glass_key = "liton.glass"

	program : Engine.Program
	program = Engine.program_boot(
		{ storage_keys: [Liton.snapshot_key, Liton.glass_key], max_inflight: 32 },
		|boot| Engine.state({ ..Model.initial(Engine.boot_storage(boot, Liton.snapshot_key) ?? ""), glass: Engine.boot_storage(boot, Liton.glass_key) != Ok("off") }, Liton.page),
	).with_ports(Ports.registrations)

	## The theme is custom properties on the root (`Themes.style`), which the
	## stylesheet alone uses. Keys pressed outside a text field reach the root
	## (`Model.pressed`): roc-signals 0.5.0 delivers none at the document and
	## no modifiers, so text fields stop theirs with a handler that does
	## nothing (roc-issues RS-004, lukewilliamboswell/roc-signals#212).
	page : State(Ctx, Model.State) -> Elem(Ctx)
	page = |model|
		Engine.element(
			"div",
			[
				Engine.class("liton"),
				Engine.attr_s("style", model.signal().map(|state| Themes.style(Model.theme_shown(state), state.glass))),
				Engine.attr("tabindex", "-1"),
				Engine.ref("app"),
				Engine.on("keydown", model.set_value(Model.pressed)),
			],
			[
				Liton.bar(model),
				Html.div(
					"work",
					[
						# Shown by CSS on narrow screens: Tiling shows the column picked here,
						# and a Workbench, which is swiped through, scrolls to it.
						Html.div(
							"column-tabs",
							[
								Engine.each(
									model.signal().map(|state| state.columns),
									|column| column.id,
									|row|
										Html.button_s(
											row.field(|column| column).map2(model.signal().lift_row(), |column, state| Str.join_with(column.panes.map(|pane| Liton.label(state, pane)), " · ")),
											[
												Html.flag("aria-pressed", row.key().map2(model.signal().lift_row(), |key, state| key == state.active_column)),
												Engine.test_id_s(row.key().map2(model.signal().lift_row(), |key, state| "show-${Model.slot_name(Model.slot_of(state, key))}")),
											],
											model.lift_row().update_by(row.key(), Model.show_column),
										),
								),
							],
						),
						Html.div_s(
							model.signal().map(|state| if (state.shell == Workbench) "columns workbench" else "columns tiling"),
							[Engine.each(model.signal().map(|state| state.columns), |column| column.id, |row| Liton.column_view(model, row))],
						),
						Liton.settings(model),
					],
				),
				# Under an open ⋯ menu's pane: a click anywhere else closes the menu.
				Engine.when(model.signal().map(|state| !state.menu.is_empty()), || Html.div_attrs([Engine.class("menu-backdrop"), Engine.on_click(model.update(|state| { ..state, menu: "" }))], []), || Engine.text("")),
			].concat(Liton.effects(model)),
		)

	## Every request to the daemon is a call or a poll of /liton/v1
	## (docs/protocol.md). One poll at a time follows every topic the panes
	## show, each second and at once when what they show changes.
	effects : State(Ctx, Model.State) -> List(Elem(Ctx))
	effects = |model| [
		Engine.watch(
			Engine.const({}),
			|_| [Http({ method: "GET", url: "/liton/v1/manifest", headers: [], body: "", timeout_ms: 5000 })],
			model.on_result(
				|state, _, res| {
					text = Engine.http_text(res) ?? ""
					decoded : Try(Manifest.Offered, _)
					decoded = Json.parse(text)
					# The setup's presets and themes, which a daemon may leave out.
					set_up : Try({ setup : Setup.Offered }, _)
					set_up = Json.parse(text)
					match decoded {
						Ok(offered) => Model.set_up(Model.advertise(state, offered), set_up.map_ok(|manifest| manifest.setup) ?? Setup.offered(Setup.empty))
						Err(_) => { ..state, notice: "Could not read the daemon's manifest." }
					}
				},
			),
		),
		Engine.watch(Engine.const({}), |_| [Interval(1000)], model.on_result(|state, _, _| Model.tick(state))),
		Engine.watch(model.signal().map(Model.subjects), |_| [Self], model.on_result(|state, _, _| Model.follow(state))),
		Engine.watch_changes(
			model.signal().map(|state| state.poll),
			|poll| [Http({ method: "POST", url: "/liton/v1/poll", headers: [("Content-Type", "application/json")], body: Json.to_str({ topics: poll.topics }), timeout_ms: 10000 })],
			model.on_result(
				|state, poll, res| {
					decoded : Try(Protocol.Polled, _)
					decoded = Json.parse(Engine.http_text(res) ?? "")
					match decoded {
						Ok(answer) => Model.polled(state, poll, answer.topics)
						Err(_) => Model.poll_failed(state)
					}
				},
			),
		),
		Engine.watch_changes(
			model.signal().map(|state| state.attention_outbox),
			|outbox| [Liton.call(Json.to_str({ capability: "attention.v1", request: outbox.request }))],
			model.on_result(
				|state, outbox, res| {
					decoded : Try(Protocol.Answer(Attention.Response), _)
					decoded = Json.parse(Engine.http_text(res) ?? "")
					Model.set_aside_answered(state, outbox.serial, decoded ?? Err({ code: Unavailable, message: "The daemon did not answer." }))
				},
			),
		),
		Engine.watch(model.signal().map(Model.needs_you), |count| [Title(if (count == 0) "liton" else "(${count.to_str()}) liton")], Engine.ignore({})),
		Engine.watch_changes(
			model.signal().map(|state| state.outbox),
			|outbox| [Liton.call(Json.to_str({ capability: "chat.v1", request: outbox.request }))],
			model.on_result(
				|state, outbox, res| {
					decoded : Try(Protocol.Answer(Chat.Response), _)
					decoded = Json.parse(Engine.http_text(res) ?? "")
					Model.called(state, outbox.serial, decoded ?? Err({ code: Unavailable, message: "The daemon did not answer." }))
				},
			),
		),
		# An agent or workspace to create, whose answer may take a provider a while.
		Engine.watch_changes(
			model.signal().map(|state| state.create_outbox),
			|outbox| [Http({ method: "POST", url: "/liton/v1/call", headers: [("Content-Type", "application/json")], body: outbox.text, timeout_ms: 60000 })],
			model.on_result(|state, outbox, res| Model.created(state, outbox.serial, Engine.http_text(res) ?? "")),
		),
		# Keys reach the root only from inside it.
		Engine.watch(Engine.const({}), |_| [Focus("app")], Engine.ignore({})),
		Engine.watch(model.signal().map(|state| state.jump), |jump| if (jump.panel.is_empty()) [] else [Focus(jump.panel)], Engine.ignore({})),
		# A composer cleared by sending is built anew, out of focus: focus it.
		Engine.watch_changes(model.signal().map(|state| state.cleared), |_| [Focus("composer")], Engine.ignore({})),
		Engine.watch_changes(model.signal().map(|state| state.jumps), |_| [Focus("latest")], Engine.ignore({})),
		Engine.watch_changes(
			model.signal().map(|state| state.clipboard),
			|clipboard| [Ports.copy.request(clipboard.text)],
			model.on_result(|state, clipboard, res| Model.copy_answered(state, clipboard.serial, Ports.copy.result(res) == Ok(Bool.True))),
		),
		Engine.watch_changes(
			model.signal().map(|state| Json.to_str(Model.snapshot(state))),
			|text| [StorageSet(Liton.snapshot_key, text)],
			Engine.ignore({}),
		),
		Engine.watch_changes(model.signal().map(|state| state.glass), |glass| [StorageSet(Liton.glass_key, if (glass) "on" else "off")], Engine.ignore({})),
	]

	## A call, its JSON `body` naming the capability and holding the request.
	call : Str -> Engine.Request
	call = |body| Http({ method: "POST", url: "/liton/v1/call", headers: [("Content-Type", "application/json")], body, timeout_ms: 5000 })

	## A bar over the tiles: the presets as numbered workspaces, the one shown
	## marked, and, as status modules, what needs you, the agents running, the
	## Workbench's drawers and Settings.
	bar : State(Ctx, Model.State) -> Elem(Ctx)
	bar = |model|
		Engine.element(
			"header",
			[Engine.class("bar")],
			[
				Engine.element(
					"nav",
					[Engine.class("workspaces"), Html.aria_label("Workspaces")],
					[
						Html.span_s(Engine.const("liton"), [Engine.class("brand")]),
						Engine.each(
							model.signal().map(|state| state.presets.map_with_index(|preset, index| { name: preset.name, number: (index + 1).to_str(), title: if (index < 9) "${preset.name} (Alt+${(index + 1).to_str()})" else preset.name })),
							|workspace| workspace.name,
							|row| {
								shown = row.key().map2(model.signal().lift_row(), |name, state| name == Model.workspace_shown(state))
								number = row.field(|workspace| workspace.number)
								Engine.element(
									"button",
									[
										Engine.attr("type", "button"),
										Engine.class("workspace"),
										Html.flag("aria-pressed", shown),
										Engine.attr_s("aria-label", row.field(|workspace| "${workspace.number} ${workspace.name}")),
										Engine.attr_s("title", row.field(|workspace| workspace.title)),
										Engine.on_click(model.lift_row().update_by(row.key(), |state, name| Model.with_snapshot_text(Model.use_preset(state, name)))),
									],
									[Html.span_s(number, [Engine.class("number")]), Html.span_s(row.key(), [Engine.class("name")])],
								)
							},
						),
					],
				),
				Html.span_s(model.signal().map(|state| state.notice), [Engine.class("notice")]),
				Html.div(
					"modules",
					[
						Liton.count_module(model.signal().map(Model.needs_you), "needs-you", "need you"),
						Liton.count_module(model.signal().map(Model.running), "running", "running"),
						Engine.when(
							model.signal().map(|state| state.shell == Workbench),
							|| Html.div("drawer-toggles", [Liton.drawer_toggle(model, Left, "Left drawer"), Liton.drawer_toggle(model, Right, "Right drawer")]),
							|| Engine.text(""),
						),
						Html.button("Settings", [Engine.class("module settings-toggle"), Engine.attr("title", "Settings (Esc closes)"), Html.flag("aria-expanded", model.signal().map(|state| state.show_settings))], model.update(|state| Model.with_snapshot_text({ ..state, show_settings: !state.show_settings }))),
					],
				),
			],
		)

	## Keeps a text field's keys from the root's shortcuts (`Liton.page`).
	keeps_keys : State(ctx, Model.State) -> Engine.Attr(ctx)
	keeps_keys = |model| Engine.on("keydown", model.set_value(|state, _| state))

	## A count and what it counts, marked while it isn't 0.
	count_module : Signal(Ctx, U64), Str, Str -> Elem(Ctx)
	count_module = |count, class, counted|
		Engine.element(
			"span",
			[Engine.class_s(count.map(|shown| if (shown > 0) "module ${class} counting" else "module ${class}")), Engine.test_id(class)],
			[Html.span_s(count.map(|shown| shown.to_str()), [Engine.class("count")]), Html.span_s(Engine.const(" ${counted}"), [Engine.class("counted")])],
		)

	## Shows or hides a drawer. Its icon is the stylesheet's.
	drawer_toggle : State(Ctx, Model.State), Model.Slot, Str -> Elem(Ctx)
	drawer_toggle = |model, drawer, name|
		Html.button("", [Engine.class("module drawer-${Model.slot_name(drawer)}"), Html.aria_label(name), Engine.attr("title", name), Html.flag("aria-expanded", model.signal().map(|state| !state.collapsed.contains(drawer)))], model.update(|state| Model.toggle_drawer(state, drawer)))

	## A side sheet that picks the preset, lists each slot's or column's panes
	## to move, remove or set the options of, adds widgets, and shows the
	## layout as a snapshot. Every change shows at once.
	settings : State(Ctx, Model.State) -> Elem(Ctx)
	settings = |model|
		Engine.when(
			model.signal().map(|state| state.show_settings),
			||
				Html.section(
					"Settings",
					"settings",
					[
						Html.div("settings-header", [Html.h2("Settings", ""), Html.button("×", [Html.aria_label("Close settings"), Engine.class("close")], model.update(|state| { ..state, show_settings: Bool.False }))]),
						Html.h3("Preset", ""),
						Html.div(
							"choices",
							[
								Engine.each(
									model.signal().map(|state| state.presets),
									|preset| preset.name,
									|row|
										Html.button_s(
											row.key().map(|name| "${name} preset"),
											[Html.flag("aria-pressed", row.key().map2(model.signal().lift_row(), |name, state| Model.preset_shown(state, name)))],
											model.lift_row().update_by(row.key(), |state, name| Model.with_snapshot_text(Model.use_preset(state, name))),
										),
								),
							],
						),
						Html.h3("Theme", ""),
						Html.div(
							"choices",
							[
								Engine.each(
									model.signal().map(|state| state.themes),
									|theme| theme.name,
									|row|
										Engine.element(
											"button",
											[
												Engine.attr("type", "button"),
												Engine.class("theme-choice"),
												Engine.attr_s("aria-label", row.key().map(|name| "${name} theme")),
												Html.flag("aria-pressed", row.key().map2(model.signal().lift_row(), |name, state| Model.theme_shown(state).name == name)),
												Engine.on_click(model.lift_row().update_by(row.key(), |state, name| Model.with_snapshot_text(Model.use_theme(state, name)))),
											],
											[Html.span_s(Engine.const(""), [Engine.class("swatch"), Engine.attr_s("style", row.field(Themes.swatch))]), Engine.text_s(row.key())],
										),
								),
							],
						),
						Engine.element("label", [Engine.class("toggle")], [Html.checkbox(Engine.const("Glass"), model.signal().map(|state| state.glass), [], model.set_value(|state, checked| { ..state, glass: checked == "true" })), Engine.text("Glass")]),
						Html.p("Blurs what is behind the tiles. Blurring is work for the graphics card: turn it off on a slow device.", "help"),
						Html.h3("Layout", ""),
						Engine.each(model.signal().map(|state| state.columns), |column| column.id, |row| Liton.settings_column(model, row)),
						Html.h3("Add a widget", ""),
						Html.div(
							"choices",
							[
								# A Workbench adds to its main area; Tiling takes any widget.
								Engine.each(
									model.signal().map(|state| Widgets.all.keep_if(|widget| Widgets.fits(widget, if (state.shell == Workbench) Main else Free))),
									|widget| widget.id,
									|row|
										Html.button_s(
											row.field(|widget| widget).map2(model.signal().lift_row(), |widget, state| if (Widgets.missing(widget, state.capabilities).is_empty()) "+ ${widget.title}" else "+ ${widget.title} (unavailable)"),
											[],
											model.lift_row().update_by(row.key(), |state, widget| Model.with_snapshot_text(Model.add_pane(state, widget))),
										),
								),
							],
						),
						Html.h3("Snapshot", ""),
						Html.p("This layout as a snapshot. Copy it to share it, or paste one and load it.", ""),
						Html.textarea(Engine.const("Snapshot"), model.signal().map(|state| state.snapshot_text), [Liton.keeps_keys(model)], model.set_value(|state, text| { ..state, snapshot_text: text })),
						Html.div("choices", [Html.button("Load snapshot", [], model.update(Model.load_snapshot))]),
					],
				),
			|| Engine.text(""),
		)

	## A slot's or column's panes in settings.
	settings_column : State(Ctx, Model.State), RowRef(Ctx, Model.Column) -> Elem(ColumnCtx)
	settings_column = |model0, row| {
		model = model0.lift_row()
		slot = row.key().map2(model.signal(), |column_id, state| Model.slot_of(state, column_id))
		Html.div(
			"settings-column",
			[
				Html.span_s(slot.map(Liton.slot_title), [Engine.class("settings-slot")]),
				Engine.each(row.field(|column| column.panes), |pane| pane.id, |pane_row| Liton.settings_pane(model, slot, pane_row)),
			],
		)
	}

	slot_title : Model.Slot -> Str
	slot_title = |slot|
		match slot {
			Left => "Left drawer"
			Main => "Main area"
			Right => "Right drawer"
			Free => "Column"
		}

	## A pane in settings: in a Workbench, the slots its widget fits to move it
	## to; Remove; and, folded, a form of its widget's options.
	settings_pane : State(ColumnCtx, Model.State), Signal(ColumnCtx, Model.Slot), RowRef(ColumnCtx, Model.Pane) -> Elem(PaneCtx)
	settings_pane = |model0, slot, row| {
		model = model0.lift_row()
		id = row.key()
		pane = row.field(|shown| shown)
		title = row.field(|shown| Widgets.find(shown.widget).title)
		Engine.element(
			"details",
			[Engine.class("settings-pane")],
			[
				Engine.element(
					"summary",
					[],
					[
						Html.span_s(title, [Engine.class("settings-pane-title")]),
						Engine.when(
							model.signal().map(|state| state.shell == Workbench),
							||
								Html.select(
									title.map(|name| "Move ${name} to"),
									slot.lift_row().map(Model.slot_name),
									[Liton.keeps_keys(model)],
									[Engine.each(row.field(|shown| Widgets.find(shown.widget).slots), Model.slot_name, |choice| Engine.element("option", [Engine.attr_s("value", choice.key())], [Engine.text_s(choice.field(Liton.slot_title))]))],
									model.set_value_by(id, |state, pane_id, name| Model.with_snapshot_text(Model.move_to_slot(state, pane_id, Model.slot_named(name)))),
								),
							|| Engine.text(""),
						),
						Html.button("Remove", [Html.aria_label_s(title.map(|name| "Remove ${name}"))], model.update_by(id, |state, pane_id| Model.with_snapshot_text(Model.close_pane(state, pane_id)))),
					],
				),
				Engine.each(row.field(|shown| Widgets.find(shown.widget).options), |option| option.key, |option_row| Liton.option_control(model, pane, option_row)),
			],
		)
	}

	## A control for one of a pane's options, from its kind: a checkbox, or a
	## drop-down of its choices.
	option_control : State(PaneCtx, Model.State), Signal(PaneCtx, Model.Pane), RowRef(PaneCtx, Widgets.Option) -> Elem(Row(PaneCtx, Widgets.Option))
	option_control = |model0, pane0, row| {
		model = model0.lift_row()
		pane = pane0.lift_row()
		label = row.field(|option| option.label)
		value = pane.map2(row.key(), Model.option)
		set = model.set_value_by(pane.map2(row.key(), |shown, key| { pane_id: shown.id, key }), |state, { pane_id, key }, text| Model.with_snapshot_text(Model.set_option(state, pane_id, key, text)))
		choices = row.field(
			|option|
				match option.kind {
					Choice({ choices: listed, .. }) => listed
					Bool(_) => []
				},
		)
		checkbox = row.field(
			|option|
				match option.kind {
					Bool(_) => Bool.True
					Choice(_) => Bool.False
				},
		)
		Html.div(
			"settings-option",
			[
				Engine.when(
					checkbox,
					|| Engine.element("label", [], [Html.checkbox(label, value.map(|shown| shown == "true"), [], set), Engine.text_s(label)]),
					|| Engine.element("label", [], [Engine.text_s(label), Html.select(label, value, [Liton.keeps_keys(model)], [Engine.each(choices, |choice| choice, |choice| Html.option_s(choice.key()))], set)]),
				),
				Html.p_s(row.field(|option| option.help), [Engine.class("help")]),
			],
		)
	}

	## A column: a bar of its tabs, when tabbed, and its controls, over its
	## panes. In a Workbench it is a slot, without the controls.
	column_view : State(Ctx, Model.State), RowRef(Ctx, Model.Column) -> Elem(ColumnCtx)
	column_view = |model0, row| {
		model = model0.lift_row()
		id = row.key()
		column = row.field(|shown| shown)
		slot = id.map2(model.signal(), |column_id, state| Model.slot_of(state, column_id))
		tiling = model.signal().map(|state| state.shell == Tiling)
		classes = column.map2(model.signal(), |shown, state| Liton.column_class(state, shown))
		Engine.element(
			"div",
			[
				Engine.class_s(classes),
				Engine.test_id_s(slot.map(|shown| "slot-${Model.slot_name(shown)}")),
				Engine.attr_s("style", column.map2(model.signal(), |shown, state| if (state.shell == Tiling) "flex-grow: ${shown.size.to_str()}; --minimum-width: ${shown.panes.fold(0, |widest, pane| U32.max(widest, Widgets.find(pane.widget).minimum_width)).to_str()}px" else "")),
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
								Html.button_s(
									tab.field(|pane| pane).map2(model.signal().lift_row(), |pane, state| Liton.label(state, pane)),
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
										Html.button_s(row.field(|shown| if (shown.tabbed) "Stack" else "Tabs"), [], model.update_by(id, Model.toggle_tabs)),
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

	pane_view : State(ColumnCtx, Model.State), Signal(ColumnCtx, Model.Column), RowRef(ColumnCtx, Model.Pane) -> Elem(PaneCtx)
	pane_view = |model0, column, row| {
		model = model0.lift_row()
		id = row.key()
		title = row.field(|pane| Widgets.find(pane.widget).title)
		shown = row.field(|pane| pane).map2(model.signal(), |pane, state| { pane: pane, state: state })
		Engine.element(
			"section",
			[
				Html.aria_label_s(title),
				Engine.class_s(id.map2(column.lift_row(), |pane_id, group| if (group.tabbed and pane_id != group.active) "pane hidden" else "pane").map2(id.map2(model.signal(), |pane_id, state| pane_id == state.focused_pane), |class, focused| if (focused) "${class} focused" else class)),
				# Clicking anywhere in it focuses it, or what was clicked in it.
				Engine.attr("tabindex", "-1"),
				Engine.on("focus", model.update_by(id.map2(column.lift_row(), |pane_id, group| { pane: pane_id, column: group.id }), Model.focus_pane)),
			],
			[
				Html.div_attrs(
					[Engine.class("pane-header"), Engine.attr("data-part", "header")],
					[
						Engine.when(
							shown.map(|{ pane, state }| pane.widget == "chat" and !Model.session_of(state, pane).is_empty()),
							|| Liton.agent_header(model, id, shown.map(|{ pane, state }| Liton.agent_of(state, pane))),
							||
								Html.div(
									"pane-heading",
									[
										Html.span_s(shown.map(|{ pane, state }| Liton.label(state, pane)), [Engine.class("pane-title")]),
										Html.span_s(shown.map(|{ pane, state }| if (Widgets.find(pane.widget).follows_session) Model.context_title(state, pane) else ""), [Engine.class("pane-context")]),
									],
								),
						),
						Html.span_s(row.field(|pane| if (pane.pinned.is_empty()) "" else "pinned"), [Engine.class("badge pinned")]),
						Engine.when(
							row.field(|pane| pane.widget == "workspaces"),
							|| Html.icon_button("+", Engine.const("New workspace"), "new-workspace", model.update_by(id, |state, pane_id| Model.open_form(state, { pane_id, key: "" }))),
							|| Engine.text(""),
						),
						Liton.pane_menu(model, id, title, shown),
					],
				),
				Engine.switch(
					shown.map(|{ pane, state }| Model.body(state, pane)),
					[Sessions, Workspaces, Chat, Inbox, Changes, Capabilities, Connecting, Missing],
					|body|
						match body {
							Sessions => Liton.tree(model, id, shown.map(|{ pane, state }| Model.session_rows(state, pane)))
							Workspaces => Html.div("workspaces-pane", [Liton.create_form(model, id), Liton.tree(model, id, shown.map(|{ pane, state }| Model.workspace_rows(state, pane)))])
							Chat => Liton.chat(model, id, shown)
							Inbox => Liton.inbox(model, row.field(|pane| pane))
							Changes => Liton.changes(model, id, row.field(|pane| pane))
							Capabilities => Liton.capabilities(model)
							Connecting => Html.p("Connecting to the daemon…", "missing")
							Missing =>
								Html.p_s(
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

	## What a chat pane's header tells of its session's agent: its status as a
	## dot and a word, its kind and model, where it works, and whether Stop
	## shows, is on its way or was refused (`not_stopped`).
	Agent : { title : Str, status : Str, dot : Str, reason : Str, kind : Str, place : Str, stop : [Hidden, Stop, Stopping], not_stopped : Str }

	agent_of : Model.State, Model.Pane -> Agent
	agent_of = |state, pane| {
		session = Model.session(state, Model.session_of(state, pane))
		# Waiting for you only while there is a prompt to answer.
		asking = Model.loading(state, session.id) or Model.pending(state, pane.id).is_ok()
		(status, dot) = match session.status {
			_ if Model.starting(state, session.id) => ("starting…", "starting")
			Running => ("running", "running")
			AwaitingPermission if asking => ("waiting for you", "waiting")
			AwaitingPermission => ("running", "running")
			Failed(_) => ("failed", "failed")
			other => (Liton.status_text(other), "idle")
		}
		model = session.model.map_ok(|name| name.drop_prefix("${session.agent}-")) ?? ""
		directory = session.workspace.map_ok(|workspace| workspace.directory.drop_suffix("/").split_last("/").map_ok(|parts| parts.after) ?? workspace.directory) ?? ""
		(stop, not_stopped) = match Model.stopping(state, session.id) {
			Stopping => (Stopping, "")
			NotStopped(reason) if Model.busy(session.status) => (Stop, "Not stopped: ${reason}")
			_ => (if (Model.busy(session.status)) Stop else Hidden, "")
		}
		{
			title: session.title,
			status,
			dot,
			reason: match session.status {
				Failed(reason) => reason
				_ => ""
			},
			kind: Str.join_with([session.agent, model].drop_if(Str.is_empty), " · "),
			place: Str.join_with([directory, session.branch ?? ""].drop_if(Str.is_empty), " · "),
			stop,
			not_stopped,
		}
	}

	## A chat pane's header: its session's title and status, Stop while its
	## agent works, and under them the agent and where it works.
	agent_header : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Agent) -> Elem(PaneCtx)
	agent_header = |model, id, agent|
		Html.div(
			"agent-header",
			[
				Html.div(
					"agent-line",
					[
						Html.span_s(Engine.const(""), [Engine.class_s(agent.map(|shown| "status-dot ${shown.dot}")), Engine.attr("aria-hidden", "true")]),
						Html.span_s(agent.map(|shown| shown.title), [Engine.class("pane-title"), Engine.attr_s("title", agent.map(|shown| shown.title)), Engine.test_id("session-title")]),
						Html.span_s(agent.map(|shown| shown.status), [Engine.class_s(agent.map(|shown| "status-word ${shown.dot}")), Engine.attr_s("title", agent.map(|shown| shown.reason)), Engine.test_id("session-status")]),
						Html.span_s(agent.map(|shown| shown.not_stopped), [Engine.class("stop-status failed"), Engine.test_id("stop-failed")]),
						Engine.switch(
							agent.map(|shown| shown.stop),
							[Hidden, Stop, Stopping],
							|stop|
								match stop {
									Hidden => Engine.text("")
									Stop => Html.button("Stop", [Engine.class("stop"), Engine.attr("title", "Stop the agent")], model.update_by(id, Model.stop))
									Stopping => Html.span_s(Engine.const("Stopping…"), [Engine.class("stop-status"), Engine.test_id("stop-status")])
								},
						),
					],
				),
				Html.div("agent-meta", [Html.span_s(agent.map(|shown| shown.kind), [Engine.class("agent-kind")]), Html.span_s(agent.map(|shown| shown.place), [Engine.class("agent-place")])]),
			],
		)

	## A pane's ⋯ menu: the session it follows or is pinned to, Pin, the moves
	## Tiling allows, and Close. Each closes the menu.
	pane_menu : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Str), Signal(PaneCtx, { pane : Model.Pane, state : Model.State }) -> Elem(PaneCtx)
	pane_menu = |model, id, title, shown| {
		closing = |change| |state, pane_id| { ..change(state, pane_id), menu: "" }
		Html.div(
			"pane-menu",
			[
				Engine.element(
					"button",
					[
						Engine.attr("type", "button"),
						Engine.class("menu-toggle"),
						Html.aria_label_s(title.map(|name| "${name} menu")),
						Engine.attr("aria-haspopup", "true"),
						Html.flag("aria-expanded", id.map2(model.signal(), |pane_id, state| state.menu == pane_id)),
						Engine.on_click(model.update_by(id, Model.toggle_menu)),
					],
					[Engine.text("⋯")],
				),
				Engine.when(
					id.map2(model.signal(), |pane_id, state| state.menu == pane_id),
					||
						Html.div(
							"menu",
							[
								Html.p_s(shown.map(|{ pane, state }| Liton.context_label(state, pane)), [Engine.class("pane-context")]),
								Engine.when(
									shown.map(|{ pane, .. }| Widgets.find(pane.widget).follows_session),
									|| Html.button_s(shown.map(|{ pane, .. }| if (pane.pinned.is_empty()) "Pin" else "Unpin"), [Engine.class("pin")], model.update_by(id, closing(Model.toggle_pin))),
									|| Engine.text(""),
								),
								Engine.when(
									model.signal().map(|state| state.shell == Tiling),
									||
										Html.div(
											"moves",
											[
												Html.button_s(title.map(|name| "← Move ${name} left"), [Html.aria_label_s(title.map(|name| "Move ${name} left"))], model.update_by(id, closing(|state, pane_id| Model.move_pane(state, pane_id, Left)))),
												Html.button_s(title.map(|name| "Move ${name} right →"), [Html.aria_label_s(title.map(|name| "Move ${name} right"))], model.update_by(id, closing(|state, pane_id| Model.move_pane(state, pane_id, Right)))),
											],
										),
									|| Engine.text(""),
								),
								Html.button("Close pane", [Engine.class("close")], model.update_by(id, closing(Model.close_pane))),
							],
						),
					|| Engine.text(""),
				),
			],
		)
	}

	## What needs you, then what failed, is done or working, then what you set
	## aside, folded away.
	inbox : State(PaneCtx, Model.State), Signal(PaneCtx, Model.Pane) -> Elem(PaneCtx)
	inbox = |model, pane|
		Html.div(
			"inbox",
			[
				Liton.inbox_section(model, pane, "Needs you", model.signal().map(|state| Model.waiting(state, NeedsYou))),
				Liton.inbox_section(model, pane, "Failed", model.signal().map(|state| Model.waiting(state, Failed))),
				Liton.inbox_section(model, pane, "Done", model.signal().map(|state| Model.waiting(state, Done))),
				Liton.inbox_section(model, pane, "Working", model.signal().map(|state| Model.waiting(state, Working))),
				Liton.inbox_section(model, pane, "Idle", pane.map2(model.signal(), |shown, state| if (Model.option(shown, "show_idle") == "true") Model.waiting(state, Idle) else [])),
				Engine.when(
					model.signal().map(|state| !Model.later(state).is_empty()),
					||
						Engine.element(
							"details",
							[Engine.class("inbox-later"), Engine.test_id("later")],
							[Engine.element("summary", [], [Engine.text_s(model.signal().map(|state| "Later (${Model.later(state).len().to_str()})"))]), Liton.inbox_items(model, pane, model.signal().map(Model.later))],
						),
					|| Engine.text(""),
				),
			],
		)

	inbox_section : State(PaneCtx, Model.State), Signal(PaneCtx, Model.Pane), Str, Signal(PaneCtx, List(Attention.Item)) -> Elem(PaneCtx)
	inbox_section = |model, pane, name, items|
		Engine.when(
			items.map(|listed| !listed.is_empty()),
			|| Html.div_attrs([Engine.class("inbox-section"), Engine.attr("data-part", "section")], [Html.h3(name, ""), Liton.inbox_items(model, pane, items)]),
			|| Engine.text(""),
		)

	## Each item: its title, which opens it, its agent, state and summary, the
	## permission it asks for, and Settle and Snooze, or Bring back once set aside.
	inbox_items : State(PaneCtx, Model.State), Signal(PaneCtx, Model.Pane), Signal(PaneCtx, List(Attention.Item)) -> Elem(PaneCtx)
	inbox_items = |model0, pane, items|
		Html.ul(
			[Engine.class("inbox-items")],
			[
				Engine.each(
					items,
					|item| item.session_id,
					|row| {
						model = model0.lift_row()
						id = row.key()
						title = row.field(|item| item.title)
						permission = id.map2(model.signal(), |session_id, state| Model.item_permission(state, session_id))
						snooze_length = pane.lift_row().map(|shown| Model.option(shown, "snooze_length"))
						Html.li(
							[Engine.class_s(id.map2(model.signal(), |key, state| if (Session(key) == state.focus) "inbox-item focused" else "inbox-item")), Engine.attr("data-part", "item")],
							[
								Html.button_s(title, [], model.update_by(id, |state, session_id| Model.open(state, Session(session_id)))),
								Html.div(
									"session-meta",
									[
										Engine.text_s(row.field(|item| item.agent)),
										Html.span_s(row.field(|item| Liton.attention_text(item.state)), [Engine.class_s(row.field(|item| Liton.attention_class(item.state))), Engine.test_id("attention-state")]),
									],
								),
								Html.p_s(row.field(|item| item.summary), [Engine.class("summary")]),
								Engine.when(
									permission.map(|asked| asked.is_ok()),
									||
										Html.div(
											"permission",
											[
												Html.span_s(permission.map(|asked| asked.map_ok(|{ tool, description, .. }| "Allow ${tool}: ${description}?") ?? ""), []),
												Html.button("Allow", [Engine.class("allow"), Html.aria_label_s(title.map(|name| "Allow ${name}"))], model.update_by(id, |state, session_id| Model.answer_item(state, session_id, Bool.True))),
												Html.button("Deny", [Engine.class("deny"), Html.aria_label_s(title.map(|name| "Deny ${name}"))], model.update_by(id, |state, session_id| Model.answer_item(state, session_id, Bool.False))),
											],
										),
									|| Engine.text(""),
								),
								Html.span_s(id.map2(model.signal(), |session_id, state| Str.join_with(Model.unconfirmed(state, session_id).keep_oks(Liton.answering), " ")), [Engine.class("sent-status"), Engine.test_id("answer-status")]),
								Engine.when(
									row.field(|item| item.set_aside == No),
									||
										Html.div_attrs(
											[Engine.class("inbox-actions"), Engine.attr("data-part", "actions")],
											[
												Html.button("Settle", [Html.aria_label_s(title.map(|name| "Settle ${name}"))], model.update_by(id, |state, session_id| Model.set_aside(state, session_id, Settled))),
												Html.button_s(
													snooze_length.map(|length| "Snooze ${length}"),
													[Html.aria_label_s(title.map(|name| "Snooze ${name}"))],
													model.update_by(id.map2(pane.lift_row(), |session_id, shown| { session_id, minutes: Model.snooze_minutes(shown) }), |state, { session_id, minutes }| Model.set_aside(state, session_id, Snoozed(minutes))),
												),
											],
										),
									|| Html.div_attrs([Engine.class("inbox-actions"), Engine.attr("data-part", "actions")], [Html.button("Bring back", [Html.aria_label_s(title.map(|name| "Bring back ${name}"))], model.update_by(id, |state, session_id| Model.set_aside(state, session_id, No)))]),
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
			title = Model.context_title(state, pane)
			if (pane.pinned.is_empty()) "following ${title}" else "pinned to ${title}"
		}

	## Rows of a tree, Workspaces' or Sessions': a dot for each one's state
	## (a workspace's is its most urgent session's), its title, its branch or
	## agent, its changes, its status, and +, on a workspace's to start an
	## agent there and on a project's to create a workspace of it. A group
	## folds; a workspace or a session is focused. Both widgets share it, as
	## one list of rows, each with every part the stylesheet hides where it
	## doesn't apply, to keep the module small.
	tree : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, List(Model.Row)) -> Elem(PaneCtx)
	tree = |model0, id, rows|
		Html.ul(
			[Engine.class("tree"), Engine.attr("data-part", "list")],
			[
				Engine.each(
					rows,
					|row| row.key,
					|row| {
						model = model0.lift_row()
						kind = row.field(
							|shown|
								match shown.kind {
									Group => "group"
									Workspace => "workspace"
									Session => "session"
								},
						)
						asked = row.key().map2(id.lift_row(), |key, pane_id| { pane_id, key })
						Html.li(
							[
								Engine.class_s(row.field(|shown| shown).map2(kind, |shown, name| "tree-row tree-${name}${if (shown.focused) " focused" else ""}${if (shown.folded) " folded" else ""}${if (shown.creatable) " creatable" else ""}")),
								Engine.attr_s("data-part", kind),
							],
							[
								Html.span_s(Engine.const(""), [Engine.class_s(row.field(|shown| "status-dot ${shown.dot}")), Engine.attr("aria-hidden", "true")]),
								Html.button_s(row.field(|shown| shown.title), [Engine.class("row-title")], model.update_by(asked, Model.pick_row)),
								Html.span_s(row.field(|shown| shown.detail), [Engine.class("branch")]),
								Html.span_s(row.field(|shown| shown.counts), [Engine.class("counts")]),
								Html.span_s(row.field(|shown| shown.status), [Engine.class_s(row.field(|shown| "status-word ${shown.dot}")), Engine.test_id("row-status")]),
								Html.icon_button("+", row.field(|shown| if (shown.kind == Group) "New workspace in ${shown.title}" else "New agent in ${shown.title}"), "new-agent", model.update_by(asked, Model.open_form)),
							],
						)
					},
				),
			],
		)

	## A Workspaces pane's form, while open in it: an agent to start in a
	## workspace, of a kind its provider offers, with a model and a first
	## prompt; or a workspace to create of a project, a worktree on a new
	## branch or a checkout. Either shows starting at once. Both are one
	## form, whose class shows the fields of the one open, to keep the
	## module small.
	create_form : State(PaneCtx, Model.State), Signal(PaneCtx, Str) -> Elem(PaneCtx)
	create_form = |model, id| {
		form = id.map2(model.signal(), |pane_id, state| if (state.form.pane == pane_id) state.form else Model.closed_form)
		set = |change| model.set_value(|state, text| { ..state, form: change(state.form, text) })
		field = |name, part, placeholder, value, change| Html.text_input(Engine.const(name), "text", form.map(value), [Engine.attr("placeholder", placeholder), Engine.class(part), Liton.keeps_keys(model)], set(change))
		option = |value, text| Engine.element("option", [Engine.attr("value", value)], [Engine.text(text)])
		Engine.when(
			form.map(|shown| shown.kind != Closed),
			||
				Html.form(
					"New agent or workspace",
					[Engine.class_s(form.map(|shown| if (shown.kind == Agent) "create-form for-agent" else "create-form for-workspace")), Engine.on("submit:prevent", model.update(Model.submit_form))],
					[
						Html.p_s(form.map2(model.signal(), |shown, state| if (shown.kind == Agent) "New agent in ${state.workspaces.workspaces.find_first(|listed| listed.id == shown.place).map_ok(|listed| listed.name) ?? shown.place}" else "New workspace"), [Engine.class("create-title")]),
						Html.select(Engine.const("Agent"), form.map(|shown| shown.agent), [Engine.class("agent-field"), Liton.keeps_keys(model)], Liton.choices(form.map2(model.signal(), |shown, state| Model.agent_kinds(state, shown.place).map(|agent| { value: agent, label: agent }))), set(|shown, text| { ..shown, agent: text })),
						field("Model", "agent-field", "Model (optional)", |shown| shown.model, |shown, text| { ..shown, model: text }),
						field("First prompt", "agent-field", "First prompt (optional)", |shown| shown.prompt, |shown, text| { ..shown, prompt: text }),
						Html.select(Engine.const("Project"), form.map(|shown| shown.place), [Engine.class("workspace-field"), Liton.keeps_keys(model)], Liton.choices(model.signal().map(|state| state.workspaces.projects.map(|project| { value: project.id, label: project.name }))), set(|shown, text| { ..shown, place: text })),
						Html.select(Engine.const("Kind"), form.map(|shown| if (shown.worktree) "Worktree" else "Checkout"), [Engine.class("workspace-field"), Liton.keeps_keys(model)], [option("Worktree", "Worktree on a new branch"), option("Checkout", "Checkout of the project")], set(|shown, text| { ..shown, worktree: text == "Worktree" })),
						field("Branch", "workspace-field", "Branch (optional)", |shown| shown.branch, |shown, text| { ..shown, branch: text }),
						Html.p_s(form.map(|shown| shown.failed), [Engine.class("create-failed"), Engine.test_id("create-failed")]),
						Html.div(
							"create-actions",
							[
								Html.submit_button("Start", [Engine.class("agent-field")]),
								Html.submit_button("Create", [Engine.class("workspace-field")]),
								Html.button("Cancel", [], model.update(|state| { ..state, form: Model.closed_form })),
							],
						),
					],
				),
			|| Engine.text(""),
		)
	}

	## A drop-down's options, each a value and what it says, as twelve
	## options, those left over hidden: of more, only the first twelve show.
	## Twelve elements cost the module far less than a list of them would.
	choices : Signal(ctx, List({ value : Str, label : Str })) -> List(Elem(ctx))
	choices = |listed| {
		slot = |index| {
			choice = listed.map(|shown| shown.get(index) ?? { value: "", label: "" })
			Engine.element("option", [Engine.attr_s("value", choice.map(|shown| shown.value)), Html.flag_maybe("hidden", choice.map(|shown| shown.value.is_empty()))], [Engine.text_s(choice.map(|shown| shown.label))])
		}
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map(slot)
	}

	chat : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, { pane : Model.Pane, state : Model.State }) -> Elem(PaneCtx)
	chat = |model0, id, shown| {
		pending = id.map2(model0.signal(), |pane_id, state| Model.pending(state, pane_id))
		Html.div(
			"chat",
			[
				# Reversed in CSS, so the scroll position stays on the newest entry.
				Html.div(
					"timeline-scroll",
					[
						# Shown by CSS once scrolled up from the newest entry, where
						# browsers can (animation-timeline). Jumping builds this pane's
						# anchor anew, so it is the one `Liton.effects` focuses.
						Html.div("jump", [Html.button("Jump to latest", [Engine.class("jump-to-latest")], model0.update_by(id, Model.jump_to_latest))]),
						Engine.remount_on(id.map2(model0.signal(), |pane_id, state| Model.jumps_of(state, pane_id)), || Engine.element("span", [Engine.ref("latest"), Engine.attr("tabindex", "-1"), Engine.class("latest-anchor")], [])),
						Html.ul(
							[Engine.class("timeline"), Engine.attr("data-part", "timeline")],
							[
								Engine.each(
									shown.map(|{ pane, state }| Model.chat_entries(state, pane)),
									|entry| entry.sequence.to_str(),
									|row|
										Html.li(
											[Engine.class_s(row.field(|entry| Liton.entry_class(entry.event))), Engine.attr("data-part", "bubble")],
											[
												Engine.switch(
													row.field(|entry| if (entry.card.is_ok()) Card else if (Liton.message(entry.event).is_ok()) Message else Plain),
													[Card, Message, Plain],
													|kind|
														match kind {
															Card => Liton.tool_card(row.field(|entry| entry.card ?? { tool: "", input: "", state: Running, output: "", folded: "" }))
															Message => Liton.markdown(model0.lift_row(), row.key().map2(id.lift_row(), |sequence, pane_id| "${pane_id}/${sequence}"), row.field(|entry| Markdown.blocks(Liton.message(entry.event) ?? "")))
															Plain => Html.pre_s(row.field(|entry| Liton.describe(entry.event)), [])
														},
												),
											],
										),
								),
								Engine.each(
									shown.map(|{ pane, state }| Model.unconfirmed(state, Model.session_of(state, pane))),
									|sent| sent.serial.to_str(),
									|row|
										Html.li(
											[Engine.class_s(row.field(|sent| Liton.sent_class(sent))), Engine.attr("data-part", "bubble")],
											[
												Html.pre_s(row.field(|sent| Liton.sent_text(sent.request)), []),
												Html.span_s(row.field(|sent| Liton.sent_status(sent)), [Engine.class("sent-status"), Engine.test_id("sent-status")]),
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
						Html.div_attrs(
							[Engine.class("permission"), Engine.attr("data-part", "permission")],
							[
								Html.span_s(pending.map(|waiting| waiting.map_ok(|asked| "Allow ${asked.tool}: ${asked.description}?") ?? ""), []),
								Html.button("Allow", [Engine.class("allow")], model0.update_by(id, |state, pane_id| Model.answer(state, pane_id, Bool.True))),
								Html.button("Deny", [Engine.class("deny")], model0.update_by(id, |state, pane_id| Model.answer(state, pane_id, Bool.False))),
							],
						),
					|| Engine.text(""),
				),
				Html.form(
					"Send a message",
					[Engine.class("composer"), Engine.attr("data-part", "composer"), Engine.on("submit:prevent", model0.update_by(id, Model.submit))],
					[
						# roc-signals 0.5.0 writes a new value into a focused text box only
						# once it loses focus, so a draft cleared by pressing Enter would
						# stay in the box. Sending builds the box anew instead, which
						# `Liton.effects` focuses. No upstream issue yet.
						Engine.when(
							id.map2(model0.signal(), |pane_id, state| (state.cleared.find_first(|composer| composer.pane == pane_id).map_ok(|composer| composer.count) ?? 0) % 2 == 0),
							|| Liton.composer_input(model0, id),
							|| Liton.composer_input(model0, id),
						),
						Html.submit_button("Send", []),
					],
				),
			],
		)
	}

	composer_input : State(PaneCtx, Model.State), Signal(PaneCtx, Str) -> Elem(PaneCtx)
	composer_input = |model, id| Html.text_input(Engine.const("Message"), "text", id.map2(model.signal(), |pane_id, state| Model.draft(state, pane_id)), [Engine.attr("placeholder", "Message the agent"), Engine.ref("composer"), Liton.keeps_keys(model)], model.set_value_by(id, Model.set_draft))

	## The git of the session a pane shows: its branch, the files of the scope
	## picked, the diff of the file picked and the branch's commits. Polls
	## follow them only while it is on screen (see `Model.subjects`).
	changes : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Model.Pane) -> Elem(PaneCtx)
	changes = |model, id, pane| {
		shown = pane.map2(model.signal(), |pane_shown, state| { pane: pane_shown, state })
		git = shown.map(|{ pane: pane_shown, state }| Model.git_of(state, pane_shown))
		scope = id.map2(model.signal(), |pane_id, state| Model.git_pane(state, pane_id).scope)
		files = shown.map(|{ pane: pane_shown, state }| Model.git_files(state, pane_shown))
		hunks = shown.map(|{ pane: pane_shown, state }| Model.git_hunks_of(state, pane_shown))
		Html.div(
			"changes",
			[
				Engine.switch(
					shown.map(|{ pane: pane_shown, state }| Model.git_shown(state, pane_shown)),
					[NoSession, Loading, Unreadable, NotGit, Shown],
					|showing|
						match showing {
							NoSession => Html.p("Pick a session to see its changes.", "missing")
							Loading => Html.p("Loading…", "missing")
							Unreadable => Html.p("Can't read this workspace right now.", "missing")
							NotGit => Html.p("Not a git workspace.", "missing")
							Shown =>
								Html.div(
									"git",
									[
										Html.div_attrs(
											[Engine.class("git-status"), Engine.attr("data-part", "status")],
											[
												Html.span_s(git.map(|known| Liton.branch_text(known.status)), [Engine.class("branch")]),
												Html.span_s(git.map(|known| Liton.base_text(known.status)), [Engine.test_id("ahead-behind")]),
												Html.span_s(git.map(|known| if (Liton.dirty(known.status)) "uncommitted changes" else ""), [Engine.class("badge dirty")]),
											],
										),
										Html.div(
											"choices",
											[
												Liton.scope_button(model, id, scope, "Uncommitted", Uncommitted),
												Liton.scope_button(model, id, scope, "Against base", AgainstBase),
												Html.span_s(scope.map2(git, Liton.commit_text), [Engine.class("badge")]),
											],
										),
										Engine.when(files.map(|listed| listed == Loading), || Html.p("Loading…", "missing"), || Html.p_s(files.map2(scope, Liton.no_files_text), [Engine.class("missing")])),
										Html.ul(
											[Engine.class("git-files"), Engine.attr("data-part", "files")],
											[
												Engine.each(
													files.map(
														|listed|
															match listed {
																Files(shown_files) => shown_files
																Loading => []
															},
													),
													|file| file.path,
													|row| {
														asked = row.key().map2(id.lift_row(), |path, pane_id| { path, pane_id })
														picked = asked.map2(model.signal().lift_row(), |{ path, pane_id }, state| Model.git_pane(state, pane_id).file == Selected(path))
														Liton.git_file(row.field(|file| file), picked, model.lift_row().update_by(asked, |state, { path, pane_id }| Model.show_git(state, pane_id, Model.git_pane(state, pane_id).scope, Selected(path))))
													},
												),
											],
										),
										Engine.switch(
											hunks.map(
												|asked|
													match asked {
														Hunks(_) => Shown
														Loading => Loading
														NoFile => NoFile
													},
											),
											[Shown, Loading, NoFile],
											|hunks_shown|
												match hunks_shown {
													NoFile => Engine.text("")
													Loading => Html.p("Loading…", "missing")
													Shown => Liton.git_diff(pane.map(|pane_shown| Model.option(pane_shown, "diff_layout")), hunks.map(Liton.hunks_or_none))
												},
										),
										Engine.when(shown.map(|{ pane: pane_shown, state }| Model.option(pane_shown, "show_commits") == "true" and !Model.git_of(state, pane_shown).commits.is_empty()), || Liton.git_commits(model, id, git), || Engine.text("")),
									],
								)
						},
				),
			],
		)
	}

	## Shows a scope's files at once, pressed while shown. Top-level because,
	## as a closure inside `changes`, it keeps `roc check` (nightly-2026-11-07)
	## from ever finishing; not reported upstream yet.
	scope_button : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, WorkspaceGit.Scope), Str, WorkspaceGit.Scope -> Elem(PaneCtx)
	scope_button = |model, id, scope, name, picked| Html.button(name, [Html.flag("aria-pressed", scope.map(|current| current == picked))], model.update_by(id, |state, pane_id| Model.show_git(state, pane_id, picked, NoFile)))

	## A changed file: its path, which picks it, how it changed and by how many
	## lines.
	git_file : Signal(ctx, WorkspaceGit.File), Signal(ctx, Bool), Handler(ctx) -> Elem(ctx)
	git_file = |file, picked, pick|
		Html.li(
			[Engine.class("git-file"), Engine.attr("data-part", "file")],
			[
				Html.button_s(file.map(Liton.file_label), [Html.flag("aria-pressed", picked)], pick),
				Html.span_s(file.map(|shown| Liton.change_text(shown.change)), [Engine.class_s(file.map(|shown| "badge change ${Liton.change_text(shown.change)}"))]),
				Html.span_s(file.map(Liton.file_lines), [Engine.class("lines")]),
			],
		)

	## A file's hunks, in one column or old beside new.
	git_diff : Signal(ctx, Str), Signal(ctx, List(WorkspaceGit.Hunk)) -> Elem(ctx)
	git_diff = |layout, hunks|
		Html.div_s(
			layout.map(|shown| if (shown == "Split") "file-diff split" else "file-diff unified"),
			[
				Engine.when(hunks.map(|listed| listed.is_empty()), || Html.p("No diff to show.", "missing"), || Engine.text("")),
				Engine.each(
					hunks,
					|hunk| "${hunk.old_start.to_str()},${hunk.new_start.to_str()}",
					|row|
						Html.div_attrs(
							[Engine.class("hunk"), Engine.attr("data-part", "hunk")],
							[
								Html.div("hunk-header", [Engine.text_s(row.field(|hunk| "@@ -${hunk.old_start.to_str()},${hunk.old_count.to_str()} +${hunk.new_start.to_str()},${hunk.new_count.to_str()} @@"))]),
								Engine.each(
									row.field(|hunk| hunk.lines).map2(layout.lift_row(), |lines, shown| Model.diff_rows(shown, lines)),
									|line| line.key,
									|line_row| Html.div_attrs([Engine.class("diff-line"), Engine.attr("data-part", "line")], [Engine.each(line_row.field(|line| line.cells), |cell| cell.key, |cell| Html.span_s(cell.field(|shown| shown.text), [Engine.class_s(cell.field(|shown| shown.class))]))]),
								),
							],
						),
				),
			],
		)

	## The branch's commits, folded away, each with its files, which pick that
	## commit's diff of them.
	git_commits : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Model.Git) -> Elem(PaneCtx)
	git_commits = |model, id, git|
		Engine.element(
			"details",
			[Engine.class("git-commits"), Engine.attr("data-part", "commits")],
			[
				Engine.element("summary", [], [Engine.text_s(git.map(|known| "Commits (${known.commits.len().to_str()})"))]),
				Html.ul(
					[Engine.class("commits")],
					[
						Engine.each(
							git.map(|known| known.commits),
							|commit| commit.sha,
							|row|
								Html.li(
									[Engine.class("commit")],
									[
										Html.div(
											"commit-line",
											[
												Html.span_s(row.field(|commit| commit.short_sha), [Engine.class("sha")]),
												Html.span_s(row.field(|commit| commit.subject), [Engine.class("subject")]),
												Html.span_s(row.field(|commit| if (commit.pushed) "pushed" else "not pushed"), [Engine.class("badge")]),
											],
										),
										Html.div("session-meta", [Engine.text_s(row.field(|commit| "${commit.author} · ${commit.date.split_first("T").map_ok(|parts| parts.before) ?? commit.date}"))]),
										Html.ul(
											[Engine.class("git-files")],
											[
												Engine.each(
													row.field(|commit| commit.files),
													|file| file.path,
													|file_row| {
														asked = file_row.key().map2(row.key().lift_row(), |path, sha| { path, sha }).map2(id.lift_row().lift_row(), |{ path, sha }, pane_id| { path, sha, pane_id })
														picked = asked.map2(model.signal().lift_row().lift_row(), |{ path, sha, pane_id }, state| Model.git_pane(state, pane_id).scope == Commit(sha) and Model.git_pane(state, pane_id).file == Selected(path))
														Liton.git_file(file_row.field(|file| file), picked, model.lift_row().lift_row().update_by(asked, |state, { path, sha, pane_id }| Model.show_git(state, pane_id, Commit(sha), Selected(path))))
													},
												),
											],
										),
									],
								),
						),
					],
				),
			],
		)

	hunks_or_none : [Hunks(List(WorkspaceGit.Hunk)), Loading, NoFile] -> List(WorkspaceGit.Hunk)
	hunks_or_none = |asked|
		match asked {
			Hunks(listed) => listed
			_ => []
		}

	branch_text : [Status(WorkspaceGit.Status), NoStatus] -> Str
	branch_text = |status|
		match status {
			Status({ branch: Branch(name), .. }) => name
			Status({ branch: Detached, .. }) => "detached"
			NoStatus => ""
		}

	## "1 ahead / 0 behind main", against the base.
	base_text : [Status(WorkspaceGit.Status), NoStatus] -> Str
	base_text = |status|
		match status {
			Status({ base: Base(name), ahead, behind, .. }) => "${ahead.to_str()} ahead / ${behind.to_str()} behind ${name}"
			_ => ""
		}

	dirty : [Status(WorkspaceGit.Status), NoStatus] -> Bool
	dirty = |status|
		match status {
			Status(known) => known.dirty
			NoStatus => Bool.False
		}

	## The commit a pane shows the files of, by its short sha.
	commit_text : WorkspaceGit.Scope, Model.Git -> Str
	commit_text = |scope, git|
		match scope {
			Commit(sha) => "Commit ${git.commits.find_first(|commit| commit.sha == sha).map_ok(|commit| commit.short_sha) ?? sha}"
			_ => ""
		}

	no_files_text : [Files(List(WorkspaceGit.File)), Loading], WorkspaceGit.Scope -> Str
	no_files_text = |files, scope|
		match (files, scope) {
			(Files([]), Uncommitted) => "Working tree clean"
			(Files([]), AgainstBase) => "No changes against the base"
			(Files([]), _) => "No files changed"
			_ => ""
		}

	## A path, or a rename's old path → new path.
	file_label : WorkspaceGit.File -> Str
	file_label = |file|
		match file.change {
			Renamed({ from }) if !from.is_empty() => "${from} → ${file.path}"
			_ => file.path
		}

	change_text : WorkspaceGit.Change -> Str
	change_text = |change|
		match change {
			Added => "added"
			Modified => "modified"
			Deleted => "deleted"
			Renamed(_) => "renamed"
		}

	## "+3 −1", or what a diff can't show.
	file_lines : WorkspaceGit.File -> Str
	file_lines = |file|
		match file.body {
			Text => "+${file.additions.to_str()} −${file.deletions.to_str()}"
			Binary => "Binary"
			TooLarge => "Too large"
		}

	## The providers and transformers, each with what it offers.
	capabilities : State(PaneCtx, Model.State) -> Elem(PaneCtx)
	capabilities = |model|
		Html.pre_s(
			model.signal().map(
				|state|
					Str.join_with(
						state.providers
							.map(|provider| "${provider.name} (${provider.id})\n${Str.join_with(provider.capabilities.map(|id| "  ${Capability.to_str(id)}"), "\n")}")
							.concat(state.transformers.map(|transformer| "${transformer.name} (${transformer.id})\n  ${Capability.to_str(transformer.offers)} from ${Str.join_with(transformer.uses.map(Capability.to_str), ", ")}")),
						"\n\n",
					),
			),
			[Engine.class("manifest"), Engine.attr("data-part", "manifest")],
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

	## A tool call's name and state over its input, then its output with all
	## but the first lines folded away.
	tool_card : Signal(ctx, Model.ToolCard) -> Elem(ctx)
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
			[Engine.class_s(state.map(|name| "tool-card ${name}")), Engine.attr("data-part", "tool-card")],
			[
				Html.div(
					"tool-header",
					[
						Html.span_s(card.map(|shown| shown.tool), [Engine.class("tool-name")]),
						Html.span_s(state, [Engine.class_s(state.map(|name| "badge ${name}")), Engine.test_id("tool-state")]),
					],
				),
				Html.pre_s(card.map(|shown| shown.input), [Engine.class("tool-input")]),
				Html.pre_s(card.map(|shown| shown.output), [Engine.class("tool-output")]),
				Engine.when(
					card.map(|shown| !shown.folded.is_empty()),
					||
						Engine.element(
							"details",
							[],
							[
								Engine.element("summary", [], [Engine.text_s(card.map(|shown| "${shown.folded.split_on("\n").len().to_str()} more lines"))]),
								Html.pre_s(card.map(|shown| shown.folded), [Engine.class("tool-output")]),
							],
						),
					|| Engine.text(""),
				),
			],
		)
	}

	## A message's text, which shows as Markdown.
	message : Chat.Event -> Try(Str, [NotMessage])
	message = |event|
		match event {
			UserMessage({ text }) | AgentMessage({ text }) => Ok(text)
			_ => Err(NotMessage)
		}

	## Markdown's blocks as elements (ui/Markdown.roc), each code block's
	## Copy keyed under `key`.
	markdown : State(ctx, Model.State), Signal(ctx, Str), Signal(ctx, List(Markdown.Block)) -> Elem(ctx)
	markdown = |model0, key0, blocks|
		Html.div(
			"markdown",
			[
				Engine.each(
					blocks,
					|block| block.key,
					|row| {
						model = model0.lift_row()
						key = key0.lift_row().map2(row.key(), |entry, index| "${entry}/${index}")
						attrs = |name| [Engine.class(name)]
						Html.div_attrs(
							[Engine.class_s(row.field(|block| if (block.quote > 0) "md-block quoted" else "md-block")), Engine.attr_s("style", row.field(|block| "--indent: ${block.indent.to_str()}"))],
							[
								Engine.switch(
									row.field(|block| block.kind),
									[Paragraph, Heading, Code, List, Rule],
									|kind|
										match kind {
											Paragraph => Engine.element("p", attrs("md-p"), [Liton.spans(row.field(|block| block.spans))])
											Heading => Engine.element("p", attrs("md-h").concat([Engine.attr("role", "heading"), Engine.attr_s("aria-level", row.field(|block| block.level.to_str()))]), [Liton.spans(row.field(|block| block.spans))])
											Rule => Engine.element("hr", attrs("md-rule"), [])
											Code => Liton.code_block(model, key, row.field(|block| block.code), attrs("md-code"))
											List =>
												Engine.element(
													"ul",
													attrs("md-list"),
													[
														Engine.each(
															row.field(|block| block.items.map_with_index(|item, index| { index: index.to_str(), item })),
															|keyed| keyed.index,
															|item| Html.li([Engine.class("md-item"), Engine.attr_s("style", item.field(|keyed| "--depth: ${keyed.item.depth.to_str()}"))], [Html.span_s(item.field(|keyed| keyed.item.marker), [Engine.class("md-marker")]), Engine.element("span", [], [Liton.spans(item.field(|keyed| keyed.item.spans))])]),
														),
													],
												)
										},
								),
							],
						)
					},
				),
			],
		)

	## Inline Markdown: text, set as its class says, and links, which open in
	## a new tab.
	spans : Signal(ctx, List(Markdown.Span)) -> Elem(ctx)
	spans = |listed|
		Engine.each(
			listed.map(|shown| shown.map_with_index(|span, index| { index: index.to_str(), span })),
			|keyed| keyed.index,
			|row|
				Engine.element(
					"span",
					[Engine.class_s(row.field(|keyed| keyed.span.class))],
					[
						Engine.when(
							row.field(|keyed| !keyed.span.href.is_empty()),
							|| Engine.element("a", [Engine.attr_s("href", row.field(|keyed| keyed.span.href)), Engine.attr("target", "_blank"), Engine.attr("rel", "noopener noreferrer")], [Engine.text_s(row.field(|keyed| keyed.span.text))]),
							|| Engine.text_s(row.field(|keyed| keyed.span.text)),
						),
					],
				),
		)

	## A code block: its language and Copy, which says Copied at once, over
	## its highlighted lines.
	code_block : State(ctx, Model.State), Signal(ctx, Str), Signal(ctx, { language : Str, text : Str, lines : List(List(Highlight.Token)) }), List(Engine.Attr(ctx)) -> Elem(ctx)
	code_block = |model, key, code, attrs|
		Html.div_attrs(
			attrs,
			[
				Html.div(
					"md-code-bar",
					[
						Html.span_s(code.map(|shown| shown.language), [Engine.class("md-language")]),
						Html.button_s(key.map2(model.signal(), |copying, state| if (state.copied == copying) "Copied" else "Copy"), [Engine.class("copy"), Engine.attr("title", "Copy the code")], model.update_by(key.map2(code, |copying, shown| { key: copying, text: shown.text }), Model.copy)),
					],
				),
				Engine.element(
					"pre",
					[],
					[
						Engine.element(
							"code",
							[],
							[
								Engine.each(
									code.map(|shown| shown.lines.map_with_index(|tokens, index| { index: index.to_str(), tokens })),
									|keyed| keyed.index,
									|line| Engine.element("span", [Engine.class("line")], [Engine.each(line.field(|keyed| keyed.tokens.map_with_index(|token, index| { index: index.to_str(), token })), |keyed| keyed.index, |token| Html.span_s(token.field(|keyed| keyed.token.text), [Engine.class_s(token.field(|keyed| keyed.token.class))]))]),
								),
							],
						),
					],
				),
			],
		)

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

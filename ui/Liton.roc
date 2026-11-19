## liton's UI: a grid of tiles of panes, each a widget bound to a capability
## the daemon advertises, and the effects that keep them current.
import pf.Engine exposing [Elem, Handler, In, Root, Row, RowRef, Signal, State]
import pf.Html
import cap.Attention
import cap.Capability
import cap.Chat
import cap.Manifest
import cap.Protocol
import cap.Review
import cap.Rooms
import cap.WorkspaceGit
import setup.Setup
import Highlight
import Markdown
import Microphone
import Ports
import Themes
import Model
import TicketDesk
import Widgets
import Dropdown
import Drag
import Wallpaper

Liton := [].{

	## The model, and the drag of a pane apart from it, so that a pointer's
	## moves wake only what shows the drag.
	Ctx : In(In(Root, Model.State), Drag.Gesture)

	TileCtx : Row(Ctx, Model.Tile)

	PaneCtx : Row(TileCtx, Model.Pane)

	snapshot_key : Str
	snapshot_key = "liton.snapshot"

	## Whether tiles blur what is behind them, "on" or "off": this browser's,
	## not the snapshot's, as it is about the device.
	glass_key : Str
	glass_key = "liton.glass"

	coarse_pointer_query : Str
	coarse_pointer_query = "(pointer: coarse)"

	program : Engine.Program
	program = Engine.program_boot(
		{ storage_keys: [Liton.snapshot_key, Liton.glass_key, Wallpaper.url_key, Wallpaper.dim_key], media: [Liton.coarse_pointer_query], max_inflight: 32 },
		|boot| Engine.state(Wallpaper.restored(Model.went({ ..Model.initial(Engine.boot_storage(boot, Liton.snapshot_key) ?? ""), glass: Engine.boot_storage(boot, Liton.glass_key) != Ok("off"), coarse_pointer: Engine.boot_media(boot, Liton.coarse_pointer_query) ?? Bool.False, now: boot.now_ms }, boot.url), Engine.boot_storage(boot, Wallpaper.url_key) ?? "", Engine.boot_storage(boot, Wallpaper.dim_key) ?? ""), |model| Engine.state(Drag.idle, |drag| Liton.page(model.lift(), drag))),
	).with_ports(Ports.registrations)

	## The theme is custom properties on the root (`Themes.style`), which the
	## stylesheet alone uses. The shortcuts (`Liton.shortcuts`) with Cmd
	## anywhere, and with Ctrl or other keys outside a text field, whose
	## Ctrl+B and Ctrl+E move the cursor on a Mac, reach `Model.pressed`.
	page : State(Ctx, Model.State), State(Ctx, Drag.Gesture) -> Elem(Ctx)
	page = |model, drag|
		Engine.element(
			"div",
			[
				Engine.class("liton"),
				Engine.attr_s("style", model.signal().map(|state| Themes.style(Wallpaper.over(Model.theme_shown(state), state), state.glass))),
				Engine.on_document_key({ keymap: Engine.const(Engine.Keymap.prevent(Liton.shortcuts.map(|(chord, _)| chord.with_meta())).concat(Engine.Keymap.prevent(Liton.shortcuts.map(|(chord, _)| chord.with_ctrl())).outside_text()).concat(Engine.Keymap.keep([Engine.Chord.plain("Escape")])).concat(Engine.Keymap.every.outside_text())) }, model.set_value_by(drag.signal(), |state, gesture, key| if (Drag.dragging(gesture) and key.key == "Escape") state else Model.pressed(state, Liton.shortcuts.find_first(|(chord, _)| chord.primary().any(|alternative| alternative == key.heard)).map_ok(|(_, name)| name) ?? key.key)).also(drag.set_value(|gesture, key| Drag.key_pressed(gesture, key.key)))),
			],
			[
				# A Workbench has no bar: its drawers' buttons are in the main
				# area's header, Settings and what needs you in the left drawer's.
				Engine.when(model.signal().map(|state| state.shell != Workbench), || Liton.bar(model), || Engine.text("")),
				Html.div(
					"work",
					[
						# Shown by CSS on narrow screens: Tiling shows the tile picked here,
						# and a Workbench, which is swiped through, scrolls to it. Its left
						# drawer's tab counts what needs you, unless an inbox there does.
						Html.div(
							"tile-tabs",
							[
								Engine.each(
									model.signal().map(Model.tiles_in_order),
									|tile| tile.id,
									|row|
										Html.button_s(
											row.field(|tile| tile).map2(model.signal().lift_row(), |tile, state| Str.join_with(Model.shown_panes(state, tile).map(|pane| Liton.label(state, pane)), " · ")),
											[
												Html.flag("aria-pressed", row.key().map2(model.signal().lift_row(), |key, state| key == state.active_tile)),
												Engine.test_id_s(row.key().map2(model.signal().lift_row(), |key, state| "show-${Model.slot_name(Model.slot_of(state, key))}")),
												Engine.attr_presence("data-badge", row.field(|tile| tile).map2(model.signal().lift_row(), |tile, state| if (Model.slot_of(state, tile.id) != Left or tile.panes.any(|pane| pane.widget == "inbox") or Model.needs_you(state) == 0) Absent else Present(Model.needs_you(state).to_str()))),
											],
											model.lift_row().update_by(row.key(), Model.show_tile),
										),
								),
							],
						),
						# The tiles laid out on the grid's tracks (`Liton.grid_style`).
						# `focusing` dims the panes not focused (style.css): a class, as
						# a :has() selector there restyled every pane on each change.
						Html.div_attrs(
							[
								Engine.class_s(model.signal().map(|state| "grid ${if (state.shell == Workbench) "workbench" else "tiling"}${if (Model.panes(state).any(|pane| pane.id == state.focused_pane)) " focusing" else ""}")),
								Engine.attr_s("style", model.signal().map(Liton.grid_style)),
							],
							[Engine.each(model.signal().map(Model.tiles_in_order), |tile| tile.id, |row| Liton.tile_view(model, drag, row))],
						),
						Liton.settings(model),
						Liton.toast(model),
					],
				),
				# Under an open ⋯ menu's pane, or a phone's Settings sheet: a click
				# anywhere else closes it.
				Engine.when(
					model.signal().map(|state| !state.menu.is_empty() or state.show_settings),
					|| Html.div_attrs([Engine.class_s(model.signal().map(|state| if (state.menu.is_empty()) "sheet-backdrop" else "menu-backdrop")), Engine.on_click(model.update(|state| if (state.menu.is_empty()) { ..state, show_settings: Bool.False } else { ..state, menu: "" }))], []),
					|| Engine.text(""),
				),
			].concat(Liton.effects(model)).concat(Microphone.effects(model)).concat(Wallpaper.effects(model)),
		)

	## Every request to the daemon is a call or a poll of /liton/v1
	## (docs/protocol.md). One poll at a time follows every topic the panes
	## show, each second and at once when what they show changes.
	effects : State(Ctx, Model.State) -> List(Elem(Ctx))
	effects = |model| [
		Engine.watch(
			Engine.const({}),
			|_| [Engine.http_body({ url: "/liton/v1/manifest", timeout: Ms(5000) })],
			model.on_result(
				|state, _, res| {
					text = res ?? ""
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
		Engine.watch(Engine.const({}), |_| [Engine.interval(1000)], model.on_result(|state, _, at| Model.tick(state, at ?? state.now))),
		Engine.watch(model.signal().map(Model.subjects), |_| [Engine.again({})], model.on_result(|state, _, _| Model.follow(state))),
		Engine.watch_changes(
			model.signal().map(|state| state.poll),
			|poll| [Engine.http_body({ method: "POST", url: "/liton/v1/poll", headers: [("Content-Type", "application/json")], body: Json.to_str({ topics: poll.topics }), timeout: Ms(10000) })],
			model.on_result(
				|state, poll, res| {
					decoded : Try(Protocol.Polled, _)
					decoded = Json.parse(res ?? "")
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
					decoded = Json.parse(res ?? "")
					Model.attention_answered(state, outbox.serial, decoded ?? Err({ code: Unavailable, message: "The daemon did not answer." }))
				},
			),
		),
		Engine.watch(model.signal().map(Model.needs_you), |count| [Engine.command(Title(if (count == 0) "liton" else "(${count.to_str()}) liton"))], Engine.ignore({})),
		Engine.watch_changes(
			model.signal().map(|state| state.outbox),
			|outbox| [Liton.call(Json.to_str({ capability: "chat.v1", request: outbox.request }))],
			model.on_result(
				|state, outbox, res| {
					decoded : Try(Protocol.Answer(Chat.Response), _)
					decoded = Json.parse(res ?? "")
					Model.called(state, outbox.serial, decoded ?? Err({ code: Unavailable, message: "The daemon did not answer." }))
				},
			),
		),
		# An agent or workspace to create, whose answer may take a provider a
		# while, a review.v1, rooms.v1 or tickets.v1 request, or an edit of a listing.
		Engine.watch_changes(
			model.signal().map(|state| state.call_outbox),
			|outbox| [Engine.http_body({ method: "POST", url: "/liton/v1/call", headers: [("Content-Type", "application/json")], body: outbox.text, timeout: Ms(60000) })],
			model.on_result(
				|state, outbox, res|
					match outbox.key {
						"review.v1" => Model.reviewed(state, outbox.serial, res ?? "")
						"rooms.v1" => Model.rooms_answered(state, outbox.serial, res ?? "")
						"tickets.v1" => Model.tickets_answered(state, outbox.serial, res ?? "")
						"edit" => Model.edit_answered(state, outbox.serial, res ?? "")
						_ => Model.created(state, outbox.serial, res ?? "")
					},
			),
		),

		Engine.watch(model.signal().map(|state| state.jump), |jump| [(jump.replace, Replace(jump.replace)), (jump.push, Push(jump.push)), (jump.panel, Focus(jump.panel))].keep_if(|(text, _)| !text.is_empty()).map(|(_, command)| Engine.command(command)), Engine.ignore({})),
		# The browser's back and forward show the panel the URL names.
		Engine.watch(
			Engine.const({}),
			|_| [Engine.popstate({})],
			model.on_result(
				|state, _, res|
					match res {
						Ok(url) => Model.went(state, url)
						Err(_) => state
					},
			),
		),
		Engine.watch(
			Engine.const({}),
			|_| [Engine.media_changes(Liton.coarse_pointer_query)],
			model.on_result(|state, _, res| { ..state, coarse_pointer: res ?? state.coarse_pointer }),
		),
		# A draft sent or dictated replaces what its box shows, focused or not.
		Engine.watch_changes(model.signal().map(|state| state.drafts_rewritten), |rewritten| [Engine.command(ApplyValue("composer-${rewritten.pane}")), Engine.command(Focus("composer-${rewritten.pane}"))], Engine.ignore({})),
		# The pane that jumped is the latest in `jumps`.
		Engine.watch_changes(model.signal().map(|state| state.jumps), |jumps| jumps.last().map_ok(|jumped| [Engine.command(Focus("latest-${jumped.pane}"))]) ?? [], Engine.ignore({})),
		Engine.watch_changes(
			model.signal().map(|state| state.clipboard),
			|clipboard| [Ports.copy.ask(clipboard.text)],
			model.on_result(|state, clipboard, res| Model.copy_answered(state, clipboard.serial, res == Ok(Bool.True))),
		),
		Engine.watch_changes(
			model.signal().map(|state| Json.to_str(Model.snapshot(state))),
			|text| [Engine.command(StorageSet(Liton.snapshot_key, text))],
			Engine.ignore({}),
		),
		Engine.watch_changes(model.signal().map(|state| state.glass), |glass| [Engine.command(StorageSet(Liton.glass_key, if (glass) "on" else "off"))], Engine.ignore({})),
	]

	## The keys heard with Ctrl or Cmd, by the names `Model.pressed` takes:
	## B and E show or hide the drawers, as in Paseo, and comma Settings.
	shortcuts : List((Engine.Chord, Str))
	shortcuts = [(Engine.Chord.plain("b"), "Ctrl+B"), (Engine.Chord.plain("e"), "Ctrl+E"), (Engine.Chord.plain(","), "Ctrl+,")]

	## A call, its JSON `body` naming the capability and holding the request.
	call : Str -> Engine.Ask(Str, Engine.HttpError)
	call = |body| Engine.http_body({ method: "POST", url: "/liton/v1/call", headers: [("Content-Type", "application/json")], body, timeout: Ms(5000) })

	## Tiling's bar over the tiles: liton's name and, as status modules, what
	## needs you, the agents running and Settings, which picks the preset (as
	## Alt+1 to 9 do).
	bar : State(Ctx, Model.State) -> Elem(Ctx)
	bar = |model|
		Engine.element(
			"header",
			[Engine.class("bar")],
			[
				Html.span_s(Engine.const("liton"), [Engine.class("brand")]),
				Html.div(
					"modules",
					[
						Liton.count_module(model.signal().map(Model.needs_you), "needs-you", "need you"),
						Liton.count_module(model.signal().map(Model.running), "running", "running"),
						Liton.settings_toggle(model, "module icon settings-toggle"),
					],
				),
			],
		)

	## Opens or closes Settings.
	settings_toggle : State(ctx, Model.State), Str -> Elem(ctx)
	settings_toggle = |model, class| Html.button("", [Engine.class(class), Html.aria_label("Settings"), Engine.attr("title", "Settings (Ctrl+, or ⌘,)"), Html.flag("aria-expanded", model.signal().map(|state| state.show_settings))], model.update(|state| Model.with_snapshot_text({ ..state, show_settings: !state.show_settings })))

	## What went wrong last, over the tiles until dismissed or replaced.
	toast : State(Ctx, Model.State) -> Elem(Ctx)
	toast = |model|
		Engine.when(
			model.signal().map(|state| !state.notice.is_empty()),
			|| Html.div_attrs([Engine.class("toast"), Engine.attr("role", "status")], [Html.span_s(model.signal().map(|state| state.notice), [Engine.test_id("notice")]), Liton.icon_button(Engine.const("Dismiss"), "icon dismiss", model.update(|state| { ..state, notice: "" }))]),
			|| Engine.text(""),
		)

	## A count and what it counts, marked while it isn't 0.
	count_module : Signal(Ctx, U64), Str, Str -> Elem(Ctx)
	count_module = |count, class, counted|
		Engine.element(
			"span",
			[Engine.class_s(count.map(|shown| if (shown > 0) "module ${class} counting" else "module ${class}")), Engine.test_id(class)],
			[Html.span_s(count.map(|shown| shown.to_str()), [Engine.class("count")]), Html.span_s(Engine.const(" ${counted}"), [Engine.class("counted")])],
		)

	## Shows or hides a drawer, named by its panes when hovered, with the
	## `workspace_changes` shown beside its icon, which is the
	## stylesheet's, as are those of every button of class `icon`.
	drawer_toggle : State(ctx, Model.State), Model.Slot, Signal(ctx, Model.Counts) -> Elem(ctx)
	drawer_toggle = |model, drawer, workspace_changes| {
		key = if (drawer == Left) "Ctrl+B or ⌘B" else "Ctrl+E or ⌘E"
		panes = model.signal().map(|state| Str.join_with(state.grid.tiles.keep_if(|tile| Model.slot_of(state, tile.id) == drawer).join_map(|tile| Model.shown_panes(state, tile).map(|pane| Liton.label(state, pane))), " · "))
		Engine.element(
			"button",
			[
				Engine.attr("type", "button"),
				Engine.class("icon drawer-toggle drawer-${Model.slot_name(drawer)}"),
				Html.aria_label(if (drawer == Left) "Left drawer" else "Right drawer"),
				Engine.attr_s("title", panes.map(|names| "${names} (${key})")),
				Html.flag("aria-expanded", model.signal().map(|state| !state.collapsed.contains(drawer))),
				Engine.on_click(model.update(|state| Model.toggle_drawer(state, drawer))),
			],
			[Html.span_s(workspace_changes.map(|counts| counts.added), [Engine.class("added")]), Html.span_s(workspace_changes.map(|counts| counts.removed), [Engine.class("removed")])],
		)
	}

	## Where a pane's header is in a Workbench: the main area's shown tab,
	## with the drawers' buttons at its ends, or the left drawer's, with
	## Settings, which CSS moves to its bottom left on a wide screen. While
	## the left drawer is hidden or empty, Settings is in the main area's.
	header_place : Model.State, Model.Tile, Str -> [MainTab, MainTabWithSettings, LeftTab, Elsewhere]
	header_place = |state, tile, pane_id| {
		left_shown = !state.collapsed.contains(Left) and state.grid.tiles.any(|listed| Model.slot_of(state, listed.id) == Left and !listed.panes.is_empty())
		first = tile.id == Model.slot_tile(state, Model.slot_of(state, tile.id))
		match Model.slot_of(state, tile.id) {
			_ if state.shell != Workbench or tile.active != pane_id or !first => Elsewhere
			Main => if (left_shown) MainTab else MainTabWithSettings
			Left => LeftTab
			_ => Elsewhere
		}
	}

	## A side sheet that picks the preset, lists each slot's or tile's panes
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
						Html.p("Alt+1 to Alt+9 show them too, in this order, outside a text box. Ctrl+B and Ctrl+E (or ⌘B and ⌘E, in a text box too) show or hide the drawers, Ctrl+, (or ⌘,) opens Settings, and Escape closes a menu or Settings, or else stops the chat's agent.", "help"),
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
						Engine.element("label", [Engine.class("toggle")], [Html.checkbox(Engine.const("Glass"), model.signal().map(|state| state.glass), [], model.set_value(|state, checked| { ..state, glass: checked })), Engine.text("Glass")]),
						Html.p("Blurs what is behind the tiles. Blurring is work for the graphics card: turn it off on a slow device.", "help"),
						Html.h3("Background", ""),
						Wallpaper.settings(model),
						Microphone.settings(model, Liton.choices),
						Html.h3("Layout", ""),
						Engine.each(model.signal().map(Model.tiles_in_order), |tile| tile.id, |row| Liton.settings_tile(model, row)),
						Html.h3("Add a widget", ""),
						Html.div(
							"choices",
							[
								# A Workbench adds to its main area; Tiling takes any widget.
								Engine.each(
									model.signal().map(|state| Widgets.all.keep_if(|widget| Widgets.fits(widget, if (state.shell == Workbench) Main else Free))),
									|widget| widget.id,
									|row| {
										offer = row.field(|widget| widget).map2(model.signal().lift_row(), Liton.widget_offer)
										Html.button_s(
											offer.map(|offered| offered.text),
											[Html.aria_label_s(offer.map(|offered| offered.name)), Engine.class_s(offer.map(|offered| if (offered.present) "added" else ""))],
											# Closed, Settings shows the pane added rather than covering it.
											model.lift_row().update_by(row.key(), |state, widget| Model.with_snapshot_text({ ..Model.add_pane(state, widget), show_settings: Bool.False })),
										)
									},
								),
							],
						),
						Html.h3("Snapshot", ""),
						Html.p("This layout as a snapshot. Copy it to share it, or paste one and load it.", ""),
						Html.textarea(Engine.const("Snapshot"), model.signal().map(|state| state.snapshot_text), [], model.set_value(|state, text| { ..state, snapshot_text: text })),
						Html.div("choices", [Html.button("Load snapshot", [], model.update(Model.load_snapshot))]),
					],
				),
			|| Engine.text(""),
		)

	## How Settings offers a widget to add: unavailable while no provider
	## supplies what it needs, and checked (by CSS) while the layout has it
	## already, which a screen reader names. It can still be added again.
	widget_offer : Widgets.Widget, Model.State -> { text : Str, name : Str, present : Bool }
	widget_offer = |widget, state| {
		unavailable = !Widgets.missing(widget, state.capabilities).is_empty()
		present = Model.panes(state).any(|pane| pane.widget == widget.id)
		text = if (unavailable) "+ ${widget.title} (unavailable)" else "+ ${widget.title}"
		{ text, name: if (present) "+ ${widget.title} (${if (unavailable) "unavailable, " else ""}already in the layout)" else text, present }
	}

	## A tile's panes in settings, under the slot it is in.
	settings_tile : State(Ctx, Model.State), RowRef(Ctx, Model.Tile) -> Elem(TileCtx)
	settings_tile = |model0, row| {
		model = model0.lift_row()
		slot = row.key().map2(model.signal(), |tile_id, state| Model.slot_of(state, tile_id))
		Html.div(
			"settings-tile",
			[
				Html.span_s(slot.map(Liton.slot_title), [Engine.class("settings-slot")]),
				Engine.each(row.field(|tile| tile.panes), |pane| pane.id, |pane_row| Liton.settings_pane(model, slot, pane_row)),
			],
		)
	}

	slot_title : Model.Slot -> Str
	slot_title = |slot|
		match slot {
			Left => "Left drawer"
			Main => "Main area"
			Right => "Right drawer"
			Free => "Tile"
		}

	## A pane in settings: in a Workbench, the slots its widget fits to move it
	## to; Remove; and, folded, a form of its widget's options.
	settings_pane : State(TileCtx, Model.State), Signal(TileCtx, Model.Slot), RowRef(TileCtx, Model.Pane) -> Elem(PaneCtx)
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
								Dropdown.select(
									title.map(|name| "Move ${name} to"),
									slot.lift_row().map(Model.slot_name),
									[],
									[Engine.each(row.field(|shown| Widgets.find(shown.widget).slots), Model.slot_name, |choice| Engine.element("option", [Engine.prop_s(Engine.Prop.value, choice.key())], [Engine.text_s(choice.field(Liton.slot_title))]))],
									model.set_value_by(id, |state, pane_id, name| Model.with_snapshot_text({ ..Model.move_to_slot(state, pane_id, Model.slot_named(name)), show_settings: Bool.False })),
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
		option_label = row.field(|option| option.label)
		value = pane.map2(row.key(), Model.option)
		option_of = pane.map2(row.key(), |shown, key| { pane_id: shown.id, key })
		set = model.set_value_by(option_of, |state, { pane_id, key }, text| Model.with_snapshot_text(Model.set_option(state, pane_id, key, text)))
		set_checked = model.set_value_by(option_of, |state, { pane_id, key }, checked| Model.with_snapshot_text(Model.set_option(state, pane_id, key, if (checked) "true" else "false")))
		option_choices = row.field(
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
					|| Engine.element("label", [], [Html.checkbox(option_label, value.map(|shown| shown == "true"), [], set_checked), Engine.text_s(option_label)]),
					|| Engine.element("label", [], [Engine.text_s(option_label), Dropdown.select(option_label, value, [], [Engine.each(option_choices, |choice| choice, |choice| Dropdown.option_s(choice.key()))], set)]),
				),
				Html.p_s(row.field(|option| option.help), [Engine.class("help")]),
			],
		)
	}

	## A tile on the grid: a bar of its tabs, each with a × that hides it in
	## a Workbench and closes it in Tiling, and in Tiling its controls, over
	## its panes, the active one shown. A Workbench slot's first tile is its
	## panel.
	tile_view : State(Ctx, Model.State), State(Ctx, Drag.Gesture), RowRef(Ctx, Model.Tile) -> Elem(TileCtx)
	tile_view = |model0, drag0, row| {
		model = model0.lift_row()
		drag = drag0.lift_row()
		id = row.key()
		tile = row.field(|shown| shown)
		slot = id.map2(model.signal(), |tile_id, state| Model.slot_of(state, tile_id))
		panel = id.map2(model.signal(), |tile_id, state| if (Model.slot_tile(state, Model.slot_of(state, tile_id)) == tile_id) Model.slot_of(state, tile_id) else Free)
		tiling = model.signal().map(|state| state.shell == Tiling)
		classes = tile.map2(model.signal(), |shown, state| Liton.tile_class(state, shown))
		Engine.element(
			"div",
			[
				Engine.class_s(classes.map2(id.map2(drag.signal(), |tile_id, gesture| Liton.tile_drop_class(tile_id, Drag.over(gesture))), Liton.joined_classes)),
				Html.zone_s(id.map(|tile_id| "tile:${tile_id}")),
				Engine.test_id_s(slot.map(|shown| "slot-${Model.slot_name(shown)}")),
				Engine.attr_s("data-tile", id),
				Engine.attr_s("style", tile.map(|shown| "grid-area: ${(shown.top + 1).to_str()} / ${(shown.left + 1).to_str()} / ${(shown.bottom + 1).to_str()} / ${(shown.right + 1).to_str()}")),
				# Swiping shows no state, but using a panel says it is the one shown.
				Engine.on("focus", model.update_by(id, |state, tile_id| { ..state, active_tile: tile_id })),
			],
			[
				Engine.switch(
					panel,
					[Left, Main, Right, Free],
					|shown| if (shown == Free) Engine.text("") else Engine.element("span", [Engine.ref(Model.panel_ref(shown)), Engine.attr("tabindex", "-1"), Engine.class("panel-anchor")], []),
				),
				Html.div(
					"tile-header",
					[
						Engine.each(
							tile.map2(model.signal(), |shown, state| Model.shown_panes(state, shown)),
							|pane| pane.id,
							|tab|
								Engine.element(
									"span",
									[Engine.class_s(tab.key().map2(drag.signal().lift_row(), |pane_id, gesture| Liton.joined_classes("tab", Liton.pane_drag_class(pane_id, gesture))))],
									[
										Html.button_s(
											tab.field(|pane| pane).map2(model.signal().lift_row(), |pane, state| Liton.label(state, pane)),
											[Engine.class_s(tab.field(|pane| "tab-select widget-${pane.widget}")), Html.flag("aria-pressed", tab.key().map2(tile.lift_row(), |key, shown| key == shown.active))].concat(Liton.grip(model.lift_row(), drag.lift_row(), tab.key(), "tab")),
											model.lift_row().update_by(tab.key(), Model.activate_tab),
										),
										Liton.icon_button(tab.field(|pane| pane).map2(model.signal().lift_row(), |pane, state| "${if (state.shell == Workbench) "Hide" else "Close"} the ${Widgets.find(pane.widget).title} tab"), "icon tab-close", model.lift_row().update_by(tab.key(), Model.close_tab)),
									],
								),
						),
						Engine.when(
							tiling,
							||
								Html.div(
									"tile-controls",
									[
										Html.icon_button("−", Engine.const("Make tile narrower"), "resize", model.update_by(id, |state, tile_id| Model.resize(state, tile_id, Narrower))),
										Html.icon_button("+", Engine.const("Make tile wider"), "resize", model.update_by(id, |state, tile_id| Model.resize(state, tile_id, Wider))),
									],
								),
							|| Engine.text(""),
						),
					],
				),
				Engine.each(row.field(|shown| shown.panes), |pane| pane.id, |pane_row| Liton.pane_view(model, drag, tile, pane_row)),
			],
		)
	}

	## The grid's tracks as CSS: a Workbench's drawers as wide as a drawer is,
	## none while collapsed, and the main area's tracks and Tiling's weighed
	## by their sizes, none narrower than the widest pane of a tile over it
	## alone needs.
	grid_style : Model.State -> Str
	grid_style = |state| {
		tracks = state.grid.columns.len()
		widest = |track| state.grid.tiles.keep_if(|tile| tile.left == track and tile.right == track + 1).join_map(|tile| tile.panes).fold(0, |wide, pane| U32.max(wide, Widgets.find(pane.widget).minimum_width))
		column = |size, track|
			match state.shell {
				Workbench if track == 0 => if (state.collapsed.contains(Left)) "0px" else "minmax(200px, 280px)"
				Workbench if track + 1 == tracks => if (state.collapsed.contains(Right)) "0px" else "minmax(240px, 380px)"
				_ => "minmax(${widest(track).to_str()}px, ${size.to_str()}fr)"
			}
		"grid-template-columns: ${Str.join_with(state.grid.columns.map_with_index(column), " ")}; grid-template-rows: ${Str.join_with(state.grid.rows.map(|size| "minmax(0, ${size.to_str()}fr)"), " ")}"
	}

	pane_view : State(TileCtx, Model.State), State(TileCtx, Drag.Gesture), Signal(TileCtx, Model.Tile), RowRef(TileCtx, Model.Pane) -> Elem(PaneCtx)
	pane_view = |model0, drag0, tile, row| {
		model = model0.lift_row()
		drag = drag0.lift_row()
		id = row.key()
		title = row.field(|pane| Widgets.find(pane.widget).title)
		shown = row.field(|pane| pane).map2(model.signal(), |pane, state| { pane: pane, state: state })
		place = id.map2(tile.lift_row(), |pane_id, group| { pane_id, group }).map2(model.signal(), |{ pane_id, group }, state| Liton.header_place(state, group, pane_id))
		Engine.element(
			"section",
			[
				Html.aria_label_s(title),
				Engine.class_s(id.map2(tile.lift_row(), |pane_id, group| { pane_id, group }).map2(model.signal(), |{ pane_id, group }, state| Str.join_with(["pane", if (pane_id != group.active or state.hidden.contains(pane_id)) "hidden" else "", if (pane_id == state.focused_pane) "focused" else ""].drop_if(Str.is_empty), " ")).map2(id.map2(drag.signal(), Liton.pane_drag_class), Liton.joined_classes)),
				Html.zone_s(id.map(|pane_id| "pane:${pane_id}")),
				# Clicking anywhere in it focuses it, or what was clicked in it.
				Engine.attr("tabindex", "-1"),
				Engine.on("focus", model.update_by(id.map2(tile.lift_row(), |pane_id, group| { pane: pane_id, tile: group.id }), Model.focus_pane)),
			],
			[
				Html.div_attrs(
					[Engine.class("pane-header"), Engine.attr("data-part", "header")],
					[
						Engine.when(place.map(|at| at == MainTab or at == MainTabWithSettings), || Liton.drawer_toggle(model, Left, Engine.const(Model.no_counts)), || Engine.text("")),
						# Dragging its header moves the pane, as its tab does.
						Engine.element(
							"div",
							[Engine.class("pane-grip"), Engine.test_id_s(id.map(|pane_id| "grip-${pane_id}"))].concat(Liton.grip(model, drag, id, "head")),
							[
								Engine.when(
									shown.map(|{ pane, state }| pane.widget == "chat" and !Model.session_of(state, pane).is_empty()),
									|| Liton.agent_header(shown.map(|{ pane, state }| Liton.agent_of(state, pane))),
									||
										Html.div(
											"pane-heading",
											[
												Html.span_s(shown.map(|{ pane, state }| Liton.label(state, pane)), [Engine.class("pane-title")]),
												Html.span_s(shown.map(|{ pane, state }| if (!Widgets.find(pane.widget).follows.is_empty()) Model.context_title(state, pane) else ""), [Engine.class("pane-context")]),
											],
										),
								),
							],
						),
						Html.span_s(row.field(|pane| if (pane.pinned.is_empty()) "" else "pinned"), [Engine.class("badge pinned")]),
						Html.span_s(shown.map(|{ pane, state }| if ((pane.widget == "workspaces" or pane.widget == "sessions") and Model.needs_you(state) > 0) Model.needs_you(state).to_str() else ""), [Engine.class("needs-you-count"), Engine.attr("title", "Need you"), Engine.test_id("header-needs-you")]),
						Engine.when(
							row.field(|pane| pane.widget == "workspaces"),
							|| Liton.icon_button(Engine.const("New workspace"), "icon new-workspace", model.update_by(id, |state, pane_id| Model.open_form(state, { pane_id, key: "" }))),
							|| Engine.text(""),
						),
						Engine.when(place.map(|at| at == LeftTab or at == MainTabWithSettings), || Liton.settings_toggle(model, "icon settings-toggle"), || Engine.text("")),
						Liton.pane_menu(model, id, title, shown),
						Engine.when(place.map(|at| at == MainTab or at == MainTabWithSettings), || Liton.drawer_toggle(model, Right, shown.map(|{ pane, state }| Model.workspace_changes(state, pane))), || Engine.text("")),
					],
				),
				Engine.switch(
					shown.map(|{ pane, state }| Model.body(state, pane)),
					[Sessions, Workspaces, Chat, Inbox, Changes, Files, Tickets, Ticket, Rooms, Room, Capabilities, Connecting, Missing, MainDiff, NoView],
					|body|
						match body {
							Sessions => Liton.tree(model, id, shown.map(|{ pane, state }| Model.session_rows(state, pane)), Menus)
							Workspaces => Html.div("workspaces-pane", [Liton.create_form(model, id), Liton.tree(model, id, shown.map(|{ pane, state }| Model.workspace_rows(state, pane)), Menus)])
							Chat => Liton.chat(model, id, shown)
							Inbox => Liton.inbox(model, row.field(|pane| pane))
							Changes => Liton.changes(model, id, row.field(|pane| pane))
							Files => Liton.files_pane(model, id, row.field(|pane| pane))
							Tickets => Liton.tickets(model, id)
							Ticket => Liton.ticket_view(model, id)
							Rooms => Liton.rooms(model)
							Room => Liton.room_view(model, id)
							Capabilities => Liton.capabilities(model)
							MainDiff => Liton.main_diff(model, id)
							Connecting => Html.p("Connecting to the daemon…", "missing")
							NoView => Html.p("liton can't show this widget yet.", "missing")
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

	## What lets a tab or header drag pane `id`: its zone, and its pointer's
	## press, moves, release and cancel. The pointer is captured on the press,
	## so its moves and release come here wherever it goes.
	grip : State(ctx, Model.State), State(ctx, Drag.Gesture), Signal(ctx, Str), Str -> List(Engine.Attr(ctx))
	grip = |model, drag, id, kind| [
		Html.zone_s(id.map(|pane_id| "${kind}:${pane_id}")),
		Html.on_pointer_down_capture(drag.set_value_by(id, Drag.pressed)),
		Html.on_pointer_move_paced(drag.set_value_by(model.signal(), Drag.moved)),
		Html.on_pointer_up(model.set_value_by(drag.signal(), Drag.dropped).also(drag.set_value(Drag.released))),
		Html.on_pointer_cancel(drag.set_value(Drag.released)),
	]

	## How a tile shows a pane dragged over it: dropping into its tabs, or a
	## new tile opening on one side.
	tile_drop_class : Str, Model.Drop -> Str
	tile_drop_class = |tile_id, drop|
		match drop {
			_ if Model.drop_tile(drop) != tile_id => ""
			Beside({ side: Left, .. }) => "drop-left"
			Beside({ side: Right, .. }) => "drop-right"
			Beside({ side: Up, .. }) => "drop-up"
			Beside({ side: Down, .. }) => "drop-down"
			_ => "drop-into"
		}

	## How a tab or pane shows a drag: dragged, or the side the pane drops on.
	pane_drag_class : Str, Drag.Gesture -> Str
	pane_drag_class = |pane_id, gesture|
		match gesture {
			Dragging(held) =>
				Liton.joined_classes(
					if (held.pane == pane_id) "dragged" else "",
					match held.over {
						Into({ at: Before(beside), .. }) if beside == pane_id => "drop-before"
						Into({ at: After(beside), .. }) if beside == pane_id => "drop-after"
						_ => ""
					},
				)
			_ => ""
		}

	joined_classes : Str, Str -> Str
	joined_classes = |first, second| Str.join_with([first, second].drop_if(Str.is_empty), " ")

	## A tile's classes: its slot's, `tabbed` while it shows more than one
	## pane, `shown` while a narrow screen shows it, and `collapsed` while its
	## drawer is.
	tile_class : Model.State, Model.Tile -> Str
	tile_class = |state, tile| {
		slot = Model.slot_of(state, tile.id)
		classes = [
			if (slot == Free) "" else "slot slot-${Model.slot_name(slot)}",
			if (Model.shown_panes(state, tile).len() > 1) "tabbed" else "",
			if (tile.id == state.active_tile) "shown" else "",
			if (state.collapsed.contains(slot)) "collapsed" else "",
		]
		Str.join_with(classes.drop_if(|class| class.is_empty()).prepend("tile"), " ")
	}

	## A pane's title, the inbox's with how many items need you.
	label : Model.State, Model.Pane -> Str
	label = |state, pane| {
		title = Widgets.find(pane.widget).title
		count = Model.needs_you(state)
		if (pane.widget == "inbox" and count > 0) "${title} (${count.to_str()})" else title
	}

	## What a chat pane's header tells of its session's agent: its status as a
	## dot and a word, its kind and model, where it works, and why a stop was
	## refused (`not_stopped`).
	Agent : { title : Str, status : Str, dot : Str, reason : Str, kind : Str, place : Str, not_stopped : Str }

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
		not_stopped = match Model.stopping(state, session.id) {
			NotStopped(reason) if Model.busy(session.status) => "Not stopped: ${reason}"
			_ => ""
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
			not_stopped,
		}
	}

	## A chat pane's header: its session's title and status, and under them
	## the agent and where it works.
	agent_header : Signal(PaneCtx, Agent) -> Elem(PaneCtx)
	agent_header = |agent|
		Html.div(
			"agent-header",
			[
				Html.div(
					"agent-line",
					[
						Html.span_s(Engine.const(""), [Engine.class_s(agent.map(|shown| "status-dot ${shown.dot}")), Engine.attr("aria-hidden", "true"), Engine.attr_s("title", agent.map(|shown| if (shown.reason.is_empty()) shown.status else "${shown.status}: ${shown.reason}"))]),
						Html.span_s(agent.map(|shown| shown.title), [Engine.class("pane-title"), Engine.attr_s("title", agent.map(|shown| shown.title)), Engine.test_id("session-title")]),
						Html.span_s(agent.map(|shown| shown.status), [Engine.class_s(agent.map(|shown| "status-word ${shown.dot}")), Engine.attr_s("title", agent.map(|shown| shown.reason)), Engine.test_id("session-status")]),
						Html.span_s(agent.map(|shown| shown.not_stopped), [Engine.class("stop-status failed"), Engine.test_id("stop-failed")]),
					],
				),
				Html.div("agent-meta", [Html.span_s(agent.map(|shown| shown.kind), [Engine.class("agent-kind")]), Html.span_s(agent.map(|shown| shown.place), [Engine.class("agent-place")])]),
			],
		)

	## An icon's button, its name for screen readers also its tooltip.
	icon_button : Signal(ctx, Str), Str, Handler(ctx) -> Elem(ctx)
	icon_button = |name, class, handler| Engine.element("button", [Engine.attr("type", "button"), Engine.class(class), Html.aria_label_s(name), Engine.attr_s("title", name), Engine.on_click(handler)], [])

	## A pane's ⋯ menu: the session it follows or is pinned to, Pin, where it
	## moves, and in Tiling Close; in a Workbench, Hide, and Show for each
	## pane its tile hides. Each closes the menu.
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
						Engine.class("icon menu-toggle"),
						Html.aria_label_s(title.map(|name| "${name} menu")),
						Engine.attr_s("title", title.map(|name| "${name} menu")),
						Engine.attr("aria-haspopup", "true"),
						Html.flag("aria-expanded", id.map2(model.signal(), |pane_id, state| state.menu == pane_id)),
						Engine.on_click(model.update_by(id, Model.toggle_menu)),
					],
					[],
				),
				Engine.when(
					id.map2(model.signal(), |pane_id, state| state.menu == pane_id),
					||
						Html.div(
							"menu",
							[
								Html.p_s(shown.map(|{ pane, state }| Liton.context_label(state, pane)), [Engine.class("pane-context")]),
								Engine.when(
									shown.map(|{ pane, .. }| !Widgets.find(pane.widget).follows.is_empty()),
									|| Html.button_s(shown.map(|{ pane, .. }| if (pane.pinned.is_empty()) "Pin" else "Unpin"), [Engine.class("pin")], model.update_by(id, closing(Model.toggle_pin))),
									|| Engine.text(""),
								),
								Html.div(
									"moves",
									[
										Engine.each(
											id.map2(model.signal(), |pane_id, state| Model.moves(state, pane_id).map(|offered| offered.label)),
											|move_label| move_label,
											|move_row| Html.button_s(move_row.key(), [], model.lift_row().update_by(id.lift_row().map2(move_row.key(), |pane_id, move_label| { pane_id, label: move_label }), |state, asked| { ..Model.move(state, asked), menu: "" })),
										),
									],
								),
								Engine.when(model.signal().map(|state| state.shell == Tiling), || Html.button("Close pane", [Engine.class("close")], model.update_by(id, closing(Model.close_pane))), || Engine.text("")),
								Engine.when(
									id.map2(model.signal(), |pane_id, state| !Model.hide_label(state, pane_id).is_empty()),
									|| Html.button_s(id.map2(model.signal(), |pane_id, state| Model.hide_label(state, pane_id)), [], model.update_by(id, closing(Model.hide_pane))),
									|| Engine.text(""),
								),
								Engine.each(
									id.map2(model.signal(), |pane_id, state| Model.hidden_beside(state, pane_id)),
									|pane| pane.id,
									|hidden_row| Html.button_s(hidden_row.field(|pane| "Show ${Widgets.find(pane.widget).title}"), [], model.lift_row().update_by(hidden_row.key(), closing(Model.show_pane))),
								),
							],
						),
					|| Engine.text(""),
				),
			],
		)
	}

	## An inbox: what needs you, then the rest the latest first, each marked
	## while unread, then what you set aside, folded away.
	inbox : State(PaneCtx, Model.State), Signal(PaneCtx, Model.Pane) -> Elem(PaneCtx)
	inbox = |model, pane|
		Html.div(
			"inbox",
			[
				Html.div(
					"inbox-toolbar",
					[
						Html.span_s(model.signal().map(|state| Liton.unread_text(Model.inbox_items(state).keep_if(|item| item.unread and item.set_aside == No).len())), [Engine.class("unread-count"), Engine.test_id("unread-count")]),
						Html.button("Mark all read", [], model.update(|state| Model.mark_seen(state, state.attention.map(|item| item.session_id), Bool.True))),
					],
				),
				Liton.inbox_section(model, pane, "Needs you", model.signal().map(|state| Model.waiting(state, NeedsYou))),
				Liton.inbox_section(model, pane, "Latest", pane.map2(model.signal(), |shown, state| Model.latest(state, shown))),
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
	## permission it asks for, and Mark read or unread (not while working),
	## Settle and Snooze, or Bring back once set aside. Unread, it is marked.
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
						permission = id.map2(model.signal(), |session_id, state| Model.item_permission(state, session_id).map_ok(|asked| { session_id, asked }))
						snooze_length = pane.lift_row().map(|shown| Model.option(shown, "snooze_length"))
						Html.li(
							[Engine.class_s(row.field(|item| item).map2(model.signal(), |item, state| Str.join_with(["inbox-item", if (Session(item.session_id) == Model.focused(state, [Session, Workspace])) "focused" else "", if (item.unread) "unread" else "", if (item.state == Working) "working" else ""].drop_if(Str.is_empty), " "))), Engine.attr("data-part", "item")],
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
									|| Liton.permission_card(model, id.map(|session_id| "inbox/${session_id}/permission"), permission.map(|asked| asked ?? Liton.no_permission), title),
									|| Engine.text(""),
								),
								Html.span_s(id.map2(model.signal(), |session_id, state| Str.join_with(Model.unconfirmed(state, session_id).keep_oks(Liton.answering), " ")), [Engine.class("sent-status"), Engine.test_id("answer-status")]),
								Engine.when(
									row.field(|item| item.set_aside == No),
									||
										Html.div_attrs(
											[Engine.class("inbox-actions"), Engine.attr("data-part", "actions")],
											[
												Html.button_s(row.field(|item| if (item.unread) "Mark read" else "Mark unread"), [Engine.class("mark"), Html.aria_label_s(row.field(|item| if (item.unread) "Mark ${item.title} read" else "Mark ${item.title} unread"))], model.update_by(row.field(|item| item), |state, item| Model.mark_seen(state, [item.session_id], item.unread))),
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

	## A permission request waiting for an answer, as a card: what its tool
	## would do, its body as Markdown, if any, and a button for each of its
	## choices (`Model.choices`) as its provider styles it, named for screen
	## readers with what it is `of`, such as an inbox item's title. An answer
	## hides it at once (`Model.answer`).
	permission_card : State(ctx, Model.State), Signal(ctx, Str), Signal(ctx, { session_id : Str, asked : Chat.Permission }), Signal(ctx, Str) -> Elem(ctx)
	permission_card = |model, key, waiting, of|
		Html.div_attrs(
			[Engine.class("permission"), Engine.attr("data-part", "permission")],
			[
				Html.span_s(waiting.map(|{ asked, .. }| if (asked.choices.is_ok()) asked.description else "Allow ${asked.tool}: ${asked.description}?"), [Engine.class("permission-title")]),
				Engine.when(waiting.map(|{ asked, .. }| asked.body.is_ok()), || Liton.markdown(model, key, waiting.map(|{ asked, .. }| Markdown.blocks(asked.body ?? ""))), || Engine.text("")),
				Html.div(
					"permission-choices",
					[
						Engine.each(
							waiting.map(|{ asked, .. }| Model.choices(asked)),
							|choice| choice.label,
							|row|
								Html.button_s(
									row.field(|choice| choice.label),
									[Engine.class_s(row.field(|choice| Liton.choice_class(choice.style))), Html.aria_label_s(row.field(|choice| choice.label).map2(of.lift_row(), |choice_label, name| if (name.is_empty()) choice_label else "${choice_label} ${name}"))],
									model.lift_row().update_by(row.field(|choice| choice).map2(waiting.lift_row(), |choice, { session_id, asked }| { session_id, request_id: asked.request_id, choice }), Model.answer),
								),
						),
					],
				),
			],
		)

	no_permission : { session_id : Str, asked : Chat.Permission }
	no_permission = { session_id: "", asked: Chat.permission({ request_id: "", tool: "", description: "" }) }

	choice_class : [Primary, Secondary, Danger] -> Str
	choice_class = |style|
		match style {
			Primary => "allow"
			Secondary => "secondary"
			Danger => "deny"
		}

	unread_text : U64 -> Str
	unread_text = |count| if (count == 0) "All read" else "${count.to_str()} unread"

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
		if (Widgets.find(pane.widget).follows.is_empty())
			""
		else {
			title = Model.context_title(state, pane)
			if (pane.pinned.is_empty()) "following ${title}" else "pinned to ${title}"
		}

	## A Tickets pane: its filters, which `Tickets.matches` applies, over its
	## tickets, the latest changed first, the one focused marked, each with
	## its key, title, which focuses it, status, assignees, source and how
	## long ago it changed.
	tickets : State(PaneCtx, Model.State), Signal(PaneCtx, Str) -> Elem(PaneCtx)
	tickets = |model, id| {
		view = id.map2(model.signal(), |pane_id, state| TicketDesk.view(state.tickets, pane_id))
		filtered = |change| model.set_value_by(id, |state, pane_id, text| Model.filter_tickets(state, pane_id, |filter| change(filter, text)))
		listed = view.map2(model.signal(), |shown, state| TicketDesk.listed(state.tickets, shown))
		Html.div(
			"tickets",
			[
				Html.div_attrs(
					[Engine.class("ticket-filters"), Engine.attr("data-part", "filters")],
					[
						Html.text_input(Engine.const("Search tickets"), "search", view.map(|shown| shown.filter.text), [Engine.attr("placeholder", "Search tickets")], filtered(|filter, text| { ..filter, text })),
						Dropdown.select(Engine.const("Source"), view.map(|shown| shown.filter.sources.first() ?? ""), [], [Dropdown.option("", "All sources")].concat(Liton.choices(model.signal().map(|state| state.tickets.listing.sources.map(|source| { value: source.id, label: source.name })))), filtered(|filter, text| { ..filter, sources: if (text.is_empty()) [] else [text] })),
						Dropdown.select(Engine.const("Status"), view.map(|shown| TicketDesk.kinds_name(shown.filter.kinds)), [], TicketDesk.kinds.map(|named| Dropdown.option(named.name, named.name)), filtered(|filter, text| { ..filter, kinds: TicketDesk.kinds_named(text) })),
						Dropdown.select(Engine.const("Assignee"), view.map(|shown| TicketDesk.assignee_name(shown.filter.assignee)), [], [Dropdown.option("Anyone", "Anyone"), Dropdown.option("Me", "Assigned to me"), Dropdown.option("Nobody", "Unassigned")], filtered(|filter, text| { ..filter, assignee: TicketDesk.assignee_named(text) })),
					],
				),
				Html.ul(
					[Engine.class("ticket-list"), Engine.attr("data-part", "list")],
					[
						Engine.each(
							listed,
							|ticket| ticket.id,
							|row| {
								state = model.signal().lift_row()
								Html.li(
									[Engine.class_s(row.key().map2(state, |ticket_id, shown| if (Model.focused(shown, [Ticket]) == Ticket(ticket_id)) "ticket-row focused" else "ticket-row")), Engine.attr("data-part", "ticket")],
									[
										Engine.element(
											"button",
											[Engine.attr("type", "button"), Engine.class("ticket-title"), Html.aria_label_s(row.field(|ticket| "${ticket.key} ${ticket.title}")), Engine.on_click(model.lift_row().update_by(row.key(), |shown, ticket_id| Model.open(shown, Ticket(ticket_id))))],
											[Html.span_s(row.field(|ticket| ticket.key), [Engine.class("ticket-key")]), Engine.text_s(row.field(|ticket| ticket.title))],
										),
										Html.div(
											"ticket-meta",
											[
												Html.span_s(row.field(|ticket| ticket.status.name), [Engine.class_s(row.field(|ticket| Liton.kind_class(ticket.status.kind))), Engine.test_id("ticket-status")]),
												Html.span_s(row.field(|ticket| Str.join_with(ticket.assignees.map(|person| person.name), ", ")), [Engine.class("assignees")]),
												Html.span_s(row.field(|ticket| ticket.source).map2(state, |source_id, shown| TicketDesk.source_name(shown.tickets, source_id)), [Engine.class("source")]),
												Html.span_s(row.field(|ticket| ticket.updated).map2(state, |updated, shown| Model.ago(shown, updated)), [Engine.class("age")]),
											],
										),
									],
								)
							},
						),
					],
				),
				Html.p_s(listed.map2(model.signal(), |shown, state| if (state.tickets.listing.sources.is_empty()) "Loading tickets…" else if (shown.is_empty()) "No tickets match." else ""), [Engine.class("ticket-empty")]),
			],
		)
	}

	## A Ticket pane: the ticket it shows, or where to pick one.
	ticket_view : State(PaneCtx, Model.State), Signal(PaneCtx, Str) -> Elem(PaneCtx)
	ticket_view = |model, id| {
		ticket_id = id.map2(model.signal(), |pane_id, state| Model.ticket_of(state, pane_id))
		Engine.when(ticket_id.map(Str.is_empty), || Html.p("Pick a ticket in Tickets to show it here.", "missing"), || Liton.ticket_detail(model, id, ticket_id))
	}

	## A ticket shown: its key, a link to it where its source keeps it, its title, status, assignees, source and
	## labels, the sessions working on it, each to open or unlink, and to
	## link the session focused; its body and comments as Markdown; and its
	## status, its
	## assignees, of its source's people, and a comment to add, each shown
	## at once, saving until the daemon has it.
	ticket_detail : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Str) -> Elem(PaneCtx)
	ticket_detail = |model, id, opened_ticket| {
		shown = opened_ticket.map2(model.signal(), |opened_id, state| TicketDesk.ticket_shown(state.tickets, opened_id) ?? TicketDesk.missing)
		summary = shown.map(|opened| opened.summary)
		Html.div_attrs(
			[Engine.class("ticket"), Engine.attr("data-part", "ticket")],
			[
				Html.div(
					"ticket-bar",
					[
						Html.span_s(summary.map(|listed| listed.key), [Engine.class("ticket-key")]),
						Engine.element("a", [Engine.attr_s("href", summary.map(|listed| listed.url)), Engine.attr("target", "_blank"), Engine.attr("rel", "noopener noreferrer"), Engine.class("ticket-link")], [Engine.text_s(summary.map2(model.signal(), |listed, state| "Open in ${TicketDesk.source_name(state.tickets, listed.source)}"))]),
					],
				),
				Engine.element("h3", [Engine.class("ticket-heading")], [Engine.text_s(summary.map(|listed| if (listed.id.is_empty()) "No such ticket" else listed.title))]),
				Html.div(
					"ticket-meta",
					[
						Html.span_s(summary.map(|listed| listed.status.name), [Engine.class_s(summary.map(|listed| Liton.kind_class(listed.status.kind))), Engine.test_id("ticket-status")]),
						Html.span_s(summary.map(|listed| Str.join_with(listed.assignees.map(|person| person.name), ", ")), [Engine.class("assignees")]),
						Html.span_s(summary.map(|listed| Str.join_with(listed.labels, " · ")), [Engine.class("labels")]),
					],
				),
				Html.div_attrs(
					[Engine.class("ticket-fields"), Engine.attr("data-part", "fields")],
					[
						Dropdown.select(Engine.const("Set status"), summary.map(|listed| listed.status.id), [], Liton.choices(summary.map2(model.signal(), |listed, state| (state.tickets.listing.sources.find_first(|source| source.id == listed.source).map_ok(|source| source.statuses) ?? []).map(|status| { value: status.id, label: status.name }))), model.set_value_by(summary.map(|listed| listed.id), |state, ticket_id, status_id| Model.ask_tickets(state, SetStatus({ ticket_id, status_id })))),
						Html.span_s(summary.map2(model.signal(), |listed, state| if (TicketDesk.pending(state.tickets, listed.id)) "Saving…" else ""), [Engine.class("ticket-saving"), Engine.test_id("ticket-saving")]),
						Engine.element(
							"fieldset",
							[Engine.class("ticket-people")],
							[
								Engine.element("legend", [], [Engine.text("Assignees")]),
								Engine.each(
									summary.map2(model.signal(), |listed, state| (state.tickets.listing.sources.find_first(|source| source.id == listed.source).map_ok(|source| source.people) ?? []).map(|person| { ticket_id: listed.id, person, assigned: listed.assignees.contains(person) })),
									|choice| choice.person.id,
									|row| Engine.element("label", [], [Html.checkbox(row.field(|choice| choice.person.name), row.field(|choice| choice.assigned), [], model.lift_row().set_value_by(row.field(|choice| { ticket_id: choice.ticket_id, person_id: choice.person.id }), Model.assign)), Engine.text_s(row.field(|choice| choice.person.name))]),
								),
							],
						),
					],
				),
				Html.div_attrs(
					[Engine.class("ticket-sessions"), Engine.attr("data-part", "sessions")],
					[
						Engine.each(
							summary.map2(model.signal(), |listed, state| TicketDesk.links_shown(state.tickets).keep_if(|link| link.ticket_id == listed.id)),
							|link| link.session_id,
							|row| {
								title = row.key().map2(model.signal().lift_row(), |session_id, state| Model.session(state, session_id).title)
								Html.div(
									"ticket-session",
									[
										Html.button_s(title, [Engine.class("session-title"), Html.aria_label_s(title.map(|name| "Open ${name}"))], model.lift_row().update_by(row.key(), |state, session_id| Model.open(state, Session(session_id)))),
										Html.span_s(row.field(|link| if (link.inferred) "by its branch" else "linked"), [Engine.class("link-kind")]),
										Html.button("Unlink", [Html.aria_label_s(title.map(|name| "Unlink ${name}"))], model.lift_row().update_by(row.key(), |state, unlinked| Model.ask_tickets(state, Unlink({ session_id: unlinked })))),
									],
								)
							},
						),
						Engine.when(
							summary.map2(model.signal(), |listed, state| Liton.linkable(state, listed.id)),
							|| Html.button_s(model.signal().map(|state| "Link to ${Model.session(state, Model.focused_session(state)).title}"), [Engine.class("link-session")], model.update_by(summary.map(|listed| listed.id), Model.link_ticket)),
							|| Engine.text(""),
						),
					],
				),
				Html.p_s(opened_ticket.map2(model.signal(), |opened_id, state| if (TicketDesk.loaded(state.tickets, opened_id)) "" else "Loading…"), [Engine.class("ticket-empty")]),
				Liton.markdown(model, id.map(|pane_id| "${pane_id}/ticket"), shown.map(|opened| Markdown.blocks(opened.body))),
				Html.ul(
					[Engine.class("ticket-comments")],
					[
						Engine.each(
							shown.map(|opened| opened.comments),
							|posted| posted.id,
							|row|
								Html.li(
									[Engine.class_s(row.key().map(|comment_id| if (comment_id.starts_with("pending-")) "ticket-comment pending" else "ticket-comment")), Engine.attr("data-part", "comment")],
									[
										Html.div(
											"comment-header",
											[
												Html.span_s(row.field(|posted| posted.author.name), [Engine.class("comment-author")]),
												Html.span_s(row.field(|posted| posted.created).map2(model.signal().lift_row(), |created, state| Model.ago(state, created)), [Engine.class("age")]),
											],
										),
										Liton.markdown(model.lift_row(), row.key().map(|comment_id| "comment/${comment_id}"), row.field(|posted| Markdown.blocks(posted.body))),
									],
								),
						),
					],
				),
				Html.form(
					"New comment",
					[Engine.class("ticket-composer"), Engine.attr("data-part", "composer"), Engine.on("submit", model.update_by(id, Model.comment_ticket))],
					[
						Html.textarea(Engine.const("Comment on this ticket"), id.map2(model.signal(), |pane_id, state| Model.draft(state, "${pane_id}/ticket")), [Engine.attr("rows", "3"), Engine.attr("placeholder", "Comment, in Markdown")], model.set_value_by(id.map(|pane_id| "${pane_id}/ticket"), Model.set_draft)),
						Html.div("comment-actions", [Html.submit_button("Comment", [])]),
					],
				),
			],
		)
	}

	## Whether the session the focus shows can be linked to a ticket: one
	## that isn't starting nor linked to it already.
	linkable : Model.State, Str -> Bool
	linkable = |state, ticket_id| {
		session_id = Model.focused_session(state)
		!session_id.is_empty() and !Model.starting(state, session_id) and !TicketDesk.links_shown(state.tickets).contains({ session_id, ticket_id, inferred: Bool.False }) and !TicketDesk.links_shown(state.tickets).contains({ session_id, ticket_id, inferred: Bool.True })
	}

	## A status's badge, as its kind shows.
	kind_class : [Open, Started, Done, Canceled] -> Str
	kind_class = |kind|
		match kind {
			Open => "badge"
			Started => "badge started"
			Done => "badge done"
			Canceled => "badge canceled"
		}

	## Rows of a tree, Workspaces', Sessions', Files' or a review's threads: a
	## dot for each one's state (a workspace's is its most urgent session's),
	## its title, its branch or agent, its changes, its status, how long ago
	## it last changed, and +, on a
	## workspace's to start an agent there and on a project's to create a
	## workspace of it. A group folds, as a folder does, indented by its
	## depth; a workspace, a session or a file is focused, and a thread jumps
	## to its lines. With `Menus`, a project's, workspace's or session's row
	## has a ⋮ menu (`Model.row_menu`), which a right-click opens too. The
	## widgets share it, as one list of rows, each with
	## every part the stylesheet hides where it doesn't apply, to keep the
	## module small.
	tree : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, List(Model.Row)), [Menus, NoMenus] -> Elem(PaneCtx)
	tree = |model0, id, rows, menus|
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
									Folder => "folder"
									File => "file"
									Thread => "thread"
								},
						)
						asked = row.key().map2(id.lift_row(), |key, pane_id| { pane_id, key })
						Html.li(
							[
								Engine.class_s(row.field(|shown| shown).map2(kind, |shown, name| "tree-row tree-${name}${if (shown.focused) " focused" else ""}${if (shown.folded) " folded" else ""}${if (shown.creatable) " creatable" else ""}${if (shown.pinned) " pinned" else ""}${if (menus == Menus and Liton.has_menu(shown)) " has-menu" else ""}")),
								Engine.attr_s("data-part", kind),
								Engine.attr_s("style", row.field(|shown| "--depth: ${shown.depth.to_str()}")),
							].concat(if (menus == Menus) [Engine.on_with("contextmenu", { prevent: Bool.True }, model.update_by(asked, |state, at| if (Model.row_menu(state, at.key).is_empty()) state else { ..state, menu: Model.row_menu_key(at) }))] else []),
							[
								Html.span_s(Engine.const(""), [Engine.class_s(row.field(|shown| "status-dot ${shown.dot}")), Engine.attr("aria-hidden", "true"), Engine.attr_s("title", row.field(|shown| shown.status))]),
								if (menus == Menus) Liton.row_title(model, asked, row.field(|shown| shown.title)) else Html.button_s(row.field(|shown| shown.title), [Engine.class("row-title")], model.update_by(asked, Model.pick_row)),
								Html.span_s(row.field(|shown| shown.detail), [Engine.class("branch")]),
								Html.span_s(row.field(|shown| shown.counts.members), [Engine.class("counts")]),
								Html.span_s(row.field(|shown| shown.counts.added), [Engine.class("added")]),
								Html.span_s(row.field(|shown| shown.counts.removed), [Engine.class("removed")]),
								Html.span_s(row.field(|shown| shown.status), [Engine.class_s(row.field(|shown| "status-word ${shown.dot}")), Engine.test_id("row-status")]),
								Html.span_s(row.field(|shown| shown.age), [Engine.class("age"), Engine.test_id("row-age")]),
								Liton.icon_button(row.field(|shown| if (shown.kind == Group) "New workspace in ${shown.title}" else if (shown.kind == Session) "New agent beside ${shown.title}" else "New agent in ${shown.title}"), "icon new-agent", model.update_by(asked, Model.open_form)),
							].concat(if (menus == Menus) [Liton.row_menu(model, asked, row.field(|shown| shown.title))] else []),
						)
					},
				),
			],
		)

	## A row's title, which picks it, or while it is being renamed, a field
	## of its name, which Enter saves and Escape leaves.
	row_title : State(ctx, Model.State), Signal(ctx, { pane_id : Str, key : Str }), Signal(ctx, Str) -> Elem(ctx)
	row_title = |model, asked, title|
		Engine.when(
			asked.map2(model.signal(), |at, state| state.renaming.pane == at.pane_id and state.renaming.key == at.key),
			|| Html.form("Rename", [Engine.class("rename-form"), Engine.on("submit", model.update(Model.rename_row))], [Html.text_input(Engine.const("New name"), "text", model.signal().map(|state| state.renaming.text), [Engine.ref("rename"), Engine.class("rename")], model.set_value(|state, text| { ..state, renaming: { ..state.renaming, text } }))]),
			|| Html.button_s(title, [Engine.class("row-title")], model.update_by(asked, Model.pick_row)),
		)

	## Whether a row has a ⋮ menu: a project's, a workspace's, or a session's
	## not still starting.
	has_menu : Model.Row -> Bool
	has_menu = |row| row.kind == Workspace or (row.kind == Session and row.dot != "starting") or (row.kind == Group and row.creatable)

	## A row's ⋮ and, while open, its menu (`Model.row_menu`), each of whose
	## actions closes it.
	row_menu : State(ctx, Model.State), Signal(ctx, { pane_id : Str, key : Str }), Signal(ctx, Str) -> Elem(ctx)
	row_menu = |model, asked, title| {
		open = asked.map2(model.signal(), |at, state| state.menu == Model.row_menu_key(at))
		Html.div(
			"row-menu",
			[
				Engine.element(
					"button",
					[
						Engine.attr("type", "button"),
						Engine.class("icon menu-toggle row-menu-toggle"),
						Html.aria_label_s(title.map(|name| "${name} menu")),
						Engine.attr_s("title", title.map(|name| "${name} menu")),
						Engine.attr("aria-haspopup", "true"),
						Html.flag("aria-expanded", open),
						Engine.on_click(model.update_by(asked, |state, at| Model.toggle_menu(state, Model.row_menu_key(at)))),
					],
					[],
				),
				Engine.when(
					open,
					||
						Html.div(
							"menu",
							[
								Engine.each(
									asked.map2(model.signal(), |at, state| Model.row_menu(state, at.key)),
									|item| item.label,
									|item| Html.button_s(item.field(|shown| shown.label), [], model.lift_row().update_by(item.field(|shown| shown.action).map2(asked.lift_row(), |action, { pane_id, key }| { pane_id, key, action }), Model.row_act)),
								),
							],
						),
					|| Engine.text(""),
				),
			],
		)
	}

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
		field = |name, part, placeholder, value, change| Html.text_input(Engine.const(name), "text", form.map(value), [Engine.attr("placeholder", placeholder), Engine.class(part)], set(change))
		Engine.when(
			form.map(|shown| shown.kind != Closed),
			||
				Html.form(
					"New agent or workspace",
					[Engine.class_s(form.map(|shown| if (shown.kind == Agent) "create-form for-agent" else "create-form for-workspace")), Engine.on("submit", model.update(Model.submit_form))],
					[
						Html.p_s(form.map2(model.signal(), |shown, state| if (shown.kind == Agent) "New agent in ${state.workspaces.workspaces.find_first(|listed| listed.id == shown.place).map_ok(|listed| listed.name) ?? shown.place}" else "New workspace"), [Engine.class("create-title")]),
						Dropdown.select(Engine.const("Agent"), form.map(|shown| shown.agent), [Engine.class("agent-field")], Liton.choices(form.map2(model.signal(), |shown, state| Model.agent_kinds(state, shown.place).map(|agent| { value: agent, label: agent }))), set(|shown, text| { ..shown, agent: text })),
						field("Model", "agent-field", "Model (optional)", |shown| shown.model, |shown, text| { ..shown, model: text }),
						field("First prompt", "agent-field", "First prompt (optional)", |shown| shown.prompt, |shown, text| { ..shown, prompt: text }),
						Dropdown.select(Engine.const("Project"), form.map(|shown| shown.place), [Engine.class("workspace-field")], Liton.choices(model.signal().map(|state| state.workspaces.projects.map(|project| { value: project.id, label: project.name }))), set(|shown, text| { ..shown, place: text })),
						Dropdown.select(Engine.const("Kind"), form.map(|shown| if (shown.worktree) "Worktree" else "Checkout"), [Engine.class("workspace-field")], [Dropdown.option("Worktree", "Worktree on a new branch"), Dropdown.option("Checkout", "Checkout of the project")], set(|shown, text| { ..shown, worktree: text == "Worktree" })),
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
			Engine.element("option", [Engine.prop_s(Engine.Prop.value, choice.map(|shown| shown.value)), Html.boolean("hidden", choice.map(|shown| shown.value.is_empty()))], [Engine.text_s(choice.map(|shown| shown.label))])
		}
		[0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11].map(slot)
	}

	chat : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, { pane : Model.Pane, state : Model.State }) -> Elem(PaneCtx)
	chat = |model0, id, shown| {
		pending = id.map2(model0.signal(), |pane_id, state| Model.pending(state, pane_id))
		chip = shown.map(|{ pane, state }| Liton.model_chip(Model.session(state, Model.session_of(state, pane))))
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
						Engine.remount_on(id.map2(model0.signal(), |pane_id, state| Model.jumps_of(state, pane_id)), || Engine.element("span", [Engine.ref_s(id.map(|pane_id| "latest-${pane_id}")), Engine.attr("tabindex", "-1"), Engine.class("latest-anchor")], [])),
						Html.ul(
							[Engine.class("timeline"), Engine.attr("data-part", "timeline")],
							[
								Engine.each(
									shown.map(|{ pane, state }| Model.chat_entries(state, pane)),
									|entry| entry.fold.map_ok(|fold| fold.key) ?? entry.sequence.to_str(),
									|row|
										Html.li(
											[Engine.class_s(row.field(|entry| if (entry.fold.is_ok()) "entry fold" else Liton.entry_class(entry.event))), Engine.attr("data-part", "bubble")],
											[
												Engine.switch(
													row.field(|entry| if (entry.fold.is_ok()) Fold else if (entry.card.is_ok()) Card else if (Liton.message(entry.event).is_ok()) Message else Plain),
													[Fold, Card, Message, Plain],
													|kind|
														match kind {
															Fold => Liton.fold_line(model0.lift_row(), id.lift_row(), row.field(|entry| entry.fold ?? { key: "", summary: "", state: Done, open: Bool.False }))
															Card => Liton.tool_card(row.field(|entry| entry.card ?? { tool: "", input: "", state: Running, output: "", folded: "" }), shown.lift_row().map(|{ pane, .. }| Model.option(pane, "collapse") == "Full"))
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
								# While the agent works on a turn: a loader and for how long.
								Engine.when(
									shown.map(|{ pane, state }| Model.working(state, pane).is_ok()),
									|| Html.li([Engine.class("entry working"), Engine.attr("role", "status"), Html.aria_label("Working")], [Html.span_s(Engine.const(""), [Engine.class("loader"), Engine.attr("aria-hidden", "true")]), Html.span_s(shown.map(|{ pane, state }| Model.working(state, pane) ?? ""), [Engine.class("elapsed"), Engine.test_id("working")])]),
									|| Engine.text(""),
								),
							],
						),
						# Last, so shown first: the timeline is reversed. ui/ports.mjs
						# presses it as it scrolls into view.
						Engine.when(
							shown.map(|{ pane, state }| Model.has_earlier(state, pane)),
							|| Html.div("earlier", [Html.button("Show earlier", [Engine.class("show-earlier")], model0.update_by(id, Model.show_earlier))]),
							|| Engine.text(""),
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
					|| Liton.permission_card(model0, id.map(|pane_id| "${pane_id}/permission"), pending.map(|waiting| waiting ?? Liton.no_permission), Engine.const("")),
					|| Engine.text(""),
				),
				Html.form(
					"Send a message",
					[Engine.class("composer"), Engine.attr("data-part", "composer"), Engine.on("submit", model0.update_by(id, Microphone.send))],
					[
						Liton.composer_input(model0, id, { name: "Message", placeholder: Engine.const("Message the agent") }, Microphone.send),
						Html.div(
							"composer-row",
							[
								Html.span_s(chip.map(|named| named.name), [Engine.class("model-chip"), Engine.attr_s("title", chip.map(|named| named.title)), Engine.test_id("model-chip")]),
								Microphone.controls(model0, id),
								# One round button: Send, or Stop while the agent works and
								# nothing is typed, then a ring until it stops.
								Engine.switch(
									shown.map(|{ pane, state }| Liton.composer_action(state, pane)),
									[Send, Stop, Stopping],
									|action|
										match action {
											Send => Html.submit_button("", [Engine.class("send"), Html.aria_label("Send")])
											Stop => Html.icon_button("", Engine.const("Stop"), "send stop", model0.update_by(id, Model.stop))
											Stopping => Html.span_s(Engine.const("Stopping…"), [Engine.class("send stopping"), Engine.attr("role", "status"), Engine.test_id("stop-status")])
										},
								),
							],
						),
					],
				),
			],
		)
	}

	## What a composer's round button does: send, or stop its session's agent
	## while it works and nothing is typed, or nothing while it stops.
	composer_action : Model.State, Model.Pane -> [Send, Stop, Stopping]
	composer_action = |state, pane| {
		session = Model.session(state, Model.session_of(state, pane))
		match Model.stopping(state, session.id) {
			Stopping => Stopping
			_ if Model.busy(session.status) and Model.draft(state, pane.id).is_empty() => Stop
			_ => Send
		}
	}

	## The composer's chip: the model a session runs, or its agent when the
	## provider doesn't tell the model, and nothing without a session.
	model_chip : Chat.Session -> { name : Str, title : Str }
	model_chip = |session|
		match session.model {
			Ok(model) => { name: model.drop_prefix("${session.agent}-"), title: "${session.agent}, running ${model}" }
			Err(Missing) => { name: session.agent, title: if (session.agent.is_empty()) "" else "${session.agent}: its provider doesn't say which model it runs" }
		}

	## A box that grows with the draft kept under `key` to a few lines, with
	## the reference `composer-<key>`, which no other box shares. Enter sends it and Shift+Enter starts a new line,
	## except on a touch screen, where Enter starts one and Send sends. Enter
	## that ends an IME composition is never heard.
	composer_input : State(ctx, Model.State), Signal(ctx, Str), { name : Str, placeholder : Signal(ctx, Str) }, (Model.State, Str -> Model.State) -> Elem(ctx)
	composer_input = |model, key, { name, placeholder }, send| {
		enter = Engine.Chord.plain("Enter")
		sends = model.signal().map(|state| Engine.Keymap.prevent(if (state.coarse_pointer) [] else [enter].concat(enter.primary())))
		Html.textarea(Engine.const(name), key.map2(model.signal(), |draft_key, state| Model.draft(state, draft_key)), [Engine.attr("rows", "1"), Engine.attr_s("placeholder", placeholder), Engine.ref_s(key.map(|draft_key| "composer-${draft_key}")), Engine.on_key({ keymap: sends }, model.update_by(key, send))], model.set_value_by(key, Model.set_draft))
	}

	## The git of the session a pane shows: its branch, the files of the scope
	## picked, the diff of the file picked and the branch's commits. Polls
	## follow them only while it is on screen (see `Model.subjects`).
	changes : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Model.Pane) -> Elem(PaneCtx)
	changes = |model, id, pane| {
		shown = pane.map2(model.signal(), |pane_shown, state| { pane: pane_shown, state })
		git = shown.map(|{ pane: pane_shown, state }| Model.git_of(state, pane_shown))
		scope = id.map2(model.signal(), |pane_id, state| Model.git_pane(state, pane_id).scope)
		files = shown.map(|{ pane: pane_shown, state }| Model.git_files(state, pane_shown))
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
										Liton.review_panel(model, id, pane),
										Html.div_attrs(
											[Engine.class("git-status"), Engine.attr("data-part", "status")],
											[
												Html.span_s(git.map(|known| Liton.branch_text(known.status)), [Engine.class("branch")]),
												Html.span_s(git.map(|known| Liton.base_text(known.status)), [Engine.test_id("ahead-behind")]),
												Html.span_s(git.map(|known| if (Liton.dirty(known.status)) "uncommitted changes" else ""), [Engine.class("badge dirty")]),
											],
										),
										Html.div("choices", [Liton.scope_picker(model, id, scope, git), Html.span_s(files.map(|listed| Liton.total_lines(listed).added), [Engine.class("added")]), Html.span_s(files.map(|listed| Liton.total_lines(listed).removed), [Engine.class("removed")])]),
										Engine.when(files.map(|listed| listed == Loading), || Html.p("Loading…", "missing"), || Html.p_s(files.map2(scope, Liton.no_files_text), [Engine.class("missing")])),
										Html.ul([Engine.class("git-files git-tree"), Engine.attr("data-part", "files")], [Engine.each(shown.map(|{ pane: pane_shown, state }| Model.changed_tree(state, pane_shown)), |row| if (row.folder) "folder:${row.path}" else row.path, |row| Liton.changed_row(model, id, row))]),
										Engine.when(id.map2(model.signal(), |pane_id, state| Model.main_diff(state) != pane_id), || Liton.file_diff(model, id, pane), || Engine.text("")),
										Engine.when(shown.map(|{ pane: pane_shown, state }| Model.option(pane_shown, "show_commits") == "true" and !Model.git_of(state, pane_shown).commits.is_empty()), || Liton.git_commits(model, id, git), || Engine.text("")),
									],
								)
						},
				),
			],
		)
	}

	## The scope a Changes pane shows, uncommitted or against the base, or the
	## commit picked below; another shows its files at once. Top-level
	## because, as a closure inside `changes`, it keeps `roc check`
	## (nightly-2026-11-07) from ever finishing; not reported upstream yet.
	scope_picker : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, WorkspaceGit.Scope), Signal(PaneCtx, Model.Git) -> Elem(PaneCtx)
	scope_picker = |model, id, scope, git| {
		value = scope.map(|current| if (current == Uncommitted) "Uncommitted" else if (current == AgainstBase) "AgainstBase" else "Commit")
		pick = |state, pane_id, picked| Model.show_git(state, pane_id, if (picked == "Uncommitted") Uncommitted else if (picked == "AgainstBase") AgainstBase else Model.git_pane(state, pane_id).scope, NoFile)
		commit = Engine.element("option", [Engine.prop(Engine.Prop.value, "Commit"), Html.boolean("hidden", value.map(|shown| shown != "Commit"))], [Engine.text_s(scope.map2(git, Liton.commit_text))])
		Dropdown.select(Engine.const("Scope"), value, [Engine.class("scope")], [Dropdown.option("Uncommitted", "Uncommitted"), Dropdown.option("AgainstBase", "Against base"), commit], model.set_value_by(id, pick))
	}

	## The lines a scope's files add and remove, as "+14" and "−3".
	total_lines : [Files(List(WorkspaceGit.File)), Loading] -> { added : Str, removed : Str }
	total_lines = |listed|
		match listed {
			Files(files) if !files.is_empty() => { added: "+${files.fold(0, |sum, file| file.additions + sum).to_str()}", removed: "−${files.fold(0, |sum, file| file.deletions + sum).to_str()}" }
			_ => { added: "", removed: "" }
		}

	## A pane's review, over its files or changes, while it has drafts or
	## threads open: its drafts and the rounds sent, Send review while it has
	## drafts, which sends the drafts to the agent as one message,
	## and, opened, its threads, each jumping to its lines, and a comment on
	## the whole review.
	review_panel : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Model.Pane) -> Elem(PaneCtx)
	review_panel = |model, id, pane| {
		key = id.map(|pane_id| "${pane_id}/review")
		review = pane.map2(model.signal(), |shown, state| Model.review_of(state, Model.context_of(state, shown)))
		Html.div_attrs(
			[Engine.class("review-panel"), Engine.attr("data-part", "review"), Html.boolean("hidden", review.map2(model.signal(), |shown, state| !state.capabilities.contains(Capability.review_v1) or (Review.drafts(shown) == 0 and shown.threads.all(|thread| thread.resolved))))],
			[
				Engine.element(
					"details",
					[],
					[
						Engine.element("summary", [], [Html.span_s(Engine.const("Review"), [Engine.class("review-title")]), Html.span_s(pane.map2(model.signal(), |shown, state| Model.review_summary(state, shown)), [Engine.class("review-summary"), Engine.test_id("review-summary")])]),
						Liton.tree(model, id, pane.map2(model.signal(), |shown, state| Model.review_rows(state, shown)), NoMenus),
						Html.form(
							"Comment on the whole review",
							[Engine.class("review-overall"), Engine.on("submit", model.update_by(id, Model.comment_overall))],
							[
								Html.textarea(Engine.const("Comment on the whole review"), key.map2(model.signal(), |draft_key, state| Model.draft(state, draft_key)), [Engine.attr("rows", "2"), Engine.attr("placeholder", "On the whole review, in Markdown")], model.set_value_by(key, Model.set_draft)),
								Html.submit_button("Add", []),
							],
						),
					],
				),
				Engine.when(review.map(|shown| Review.drafts(shown) > 0), || Html.button("Send review", [Engine.class("send-review"), Engine.attr("title", "Send the drafts to the agent as one message")], model.update_by(id, Model.send_review)), || Engine.text("")),
			],
		)
	}

	## A context's files: its folders, each opened to list it, and the file
	## picked, its lines numbered and highlighted. Polls follow them only
	## while it is on screen (see `Model.subjects`).
	files_pane : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Model.Pane) -> Elem(PaneCtx)
	files_pane = |model, id, pane| {
		shown = pane.map2(model.signal(), |pane_shown, state| { pane: pane_shown, state })
		Html.div(
			"files",
			[
				Liton.review_panel(model, id, pane),
				Html.p_s(shown.map(|{ pane: pane_shown, state }| Model.tree_status(state, pane_shown)), [Engine.class("missing")]),
				Liton.tree(model, id, shown.map(|{ pane: pane_shown, state }| Model.file_rows(state, pane_shown)), NoMenus),
				Html.div_attrs(
					[Engine.class("file-view"), Engine.attr("data-part", "file")],
					[
						Html.p_s(id.map2(model.signal(), |pane_id, state| Model.file_pane(state, pane_id).file), [Engine.class("file-path")]),
						Html.p_s(shown.map(|{ pane: pane_shown, state }| Model.file_status(state, pane_shown)), [Engine.class("missing"), Engine.test_id("file-status")]),
						Liton.code_view(model, id, Engine.const("code-view file"), shown.map(|{ pane: pane_shown, state }| Model.file_code(state, pane_shown))),
					],
				),
			],
		)
	}

	## Rows of code, a file's or a diff's, `class` saying which: each line
	## under its old and new numbers, an old line beside the new in a split
	## diff, highlighted; and between them, the review's threads on the lines
	## they end on, and the composer of a comment under the lines picked.
	## Clicking a number picks its line (`Model.pick_line`).
	code_view : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Str), Signal(PaneCtx, List(Model.CodeRow)) -> Elem(PaneCtx)
	code_view = |model0, id, class, rows|
		Html.div_attrs(
			[Engine.class_s(class)],
			[
				Engine.each(
					rows,
					|row| row.key,
					|row| {
						model = model0.lift_row()
						asked = |pick| row.field(pick).map2(id.lift_row(), |picked, pane_id| { pane_id, picked })
						# A row of an each is one element.
						Html.div(
							"code-item",
							[
								Engine.switch(
									row.field(|shown| shown.kind),
									[Code, Composer, Comment],
									|kind|
										match kind {
											Code =>
												Html.div_attrs(
													[Engine.class_s(row.field(|shown| "code-row ${shown.class}")), Engine.attr("data-part", "line")],
													[
														Html.button_s(row.field(|shown| shown.old), [Engine.class("number")], model.update_by(asked(|shown| shown.old_pick), Model.pick_line)),
														Liton.highlighted(row.field(|shown| "left ${shown.left_class}"), row.field(|shown| shown.left)),
														Html.button_s(row.field(|shown| shown.new), [Engine.class("number")], model.update_by(asked(|shown| shown.new_pick), Model.pick_line)),
														Liton.highlighted(row.field(|shown| "right ${shown.right_class}"), row.field(|shown| shown.right)),
													],
												)
											Composer => Liton.comment_composer(model)
											Comment => Liton.comment(model, row.field(|shown| shown.note).map2(id.lift_row(), |note, pane_id| { pane_id, note }))
										},
								),
							],
						)
					},
				),
			],
		)

	## The composer of a comment on lines, a reply or a draft edited, in
	## Markdown: Comment keeps it as a draft at once, Cancel closes it.
	comment_composer : State(ctx, Model.State) -> Elem(ctx)
	comment_composer = |model|
		Html.form(
			"Comment",
			[Engine.class("comment-composer"), Engine.attr("data-part", "composer"), Engine.on("submit", model.update(Model.submit_comment))],
			[
				Html.p_s(model.signal().map(|state| Liton.composing(state.composer)), [Engine.class("composer-title")]),
				Html.textarea(Engine.const("Your comment"), model.signal().map(|state| state.composer.text), [Engine.attr("rows", "3"), Engine.attr("placeholder", "Comment, in Markdown"), Engine.ref("comment")], model.set_value(|state, text| { ..state, composer: { ..state.composer, text } })),
				Html.div("comment-actions", [Html.submit_button("Comment", []), Html.button("Cancel", [], model.update(|state| { ..state, composer: Model.closed_composer }))]),
			],
		)

	composing : Model.Composer -> Str
	composing = |composer|
		if !composer.editing.is_empty() {
			"Edit your draft"
		} else if !composer.thread.is_empty() {
			"Reply"
		} else {
			"Comment on ${Review.lines({ path: composer.path, scope: composer.scope, side: composer.side, start_line: composer.start, end_line: composer.end, quote: "" })}${if (composer.side == Old) ", removed" else ""}"
		}

	## A comment of a thread, as written, who said it and its state; Edit
	## and Delete for a draft, and under a thread's last, Reply and Resolve,
	## or Reopen for a resolved thread, folded to its first comment. The
	## stylesheet hides what doesn't apply.
	comment : State(ctx, Model.State), Signal(ctx, { pane_id : Str, note : Model.Note }) -> Elem(ctx)
	comment = |model, noted| {
		note = noted.map(|{ note: shown, .. }| shown)
		# One handler for every button, to keep the module small.
		acting = |action| noted.map(|{ pane_id, note: shown }| { pane_id, note: shown, action })
		flags = |shown| Str.join_with(["comment", if (shown.draft) "draft" else "", if (shown.last) "last" else "", if (shown.resolved) "resolved" else ""].drop_if(Str.is_empty), " ")
		Html.div_attrs(
			[Engine.class_s(note.map(flags)), Engine.attr("data-part", "comment")],
			[
				Html.div(
					"comment-header",
					[
						Html.span_s(note.map(|shown| shown.author), [Engine.class("comment-author")]),
						Html.span_s(note.map(|shown| if (shown.resolved) "resolved" else shown.state), [Engine.class("badge"), Engine.test_id("comment-state")]),
						Html.button("Edit", [Engine.class("for-draft")], model.update_by(acting(Edit), Model.review_comment)),
						Html.button("Delete", [Engine.class("for-draft")], model.update_by(acting(Delete), Model.review_comment)),
					],
				),
				Html.p_s(note.map(|shown| shown.text), [Engine.class("comment-text")]),
				Html.div(
					"thread-actions",
					[
						Html.button("Reply", [Engine.class("for-open")], model.update_by(acting(Reply), Model.review_comment)),
						Html.button_s(note.map(|shown| if (shown.resolved) "Reopen" else "Resolve"), [], model.update_by(acting(Resolve), Model.review_comment)),
					],
				),
			],
		)
	}

	## A line's text, its runs in their classes (ui/Highlight.roc).
	highlighted : Signal(ctx, Str), Signal(ctx, List(Highlight.Token)) -> Elem(ctx)
	highlighted = |class, listed| Engine.element("span", [Engine.class_s(class)], [Engine.each(listed.map(|shown| shown.map_with_index(|token, index| { index: index.to_str(), token })), |keyed| keyed.index, |token| Html.span_s(token.field(|keyed| keyed.token.text), [Engine.class_s(token.field(|keyed| keyed.token.class))]))])

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

	## A row of a Changes pane's tree, indented by its depth: a folder, which
	## folds, or a file, which shows its diff; its name, named by its path to
	## a screen reader, how it changed as a coloured square, and by how many
	## lines. Top-level for the reason `scope_picker` is.
	changed_row : State(PaneCtx, Model.State), Signal(PaneCtx, Str), RowRef(PaneCtx, Model.ChangedRow) -> Elem(Row(PaneCtx, Model.ChangedRow))
	changed_row = |model, id, row| {
		shown = row.field(|changed| changed)
		asked = shown.map2(id.lift_row(), |changed, pane_id| { pane_id, path: changed.path, folder: changed.folder })
		picked = asked.map2(model.signal().lift_row(), |{ pane_id, path, folder }, state| !folder and Model.git_pane(state, pane_id).file == Selected(path))
		Html.li(
			[Engine.class_s(shown.map(|changed| if (!changed.folder) "git-file" else if (changed.folded) "git-file git-folder folded" else "git-file git-folder")), Engine.attr("data-part", "file"), Engine.attr_s("style", shown.map(|changed| "--depth: ${changed.depth.to_str()}"))],
			[
				Html.button_s(
					shown.map(|changed| changed.path.split_last("/").map_ok(|parts| parts.after) ?? changed.path),
					[
						Html.aria_label_s(shown.map(|changed| if (changed.folder) changed.path else Liton.file_label(changed.file))),
						Engine.attr_presence("aria-pressed", shown.map2(picked, |changed, is_picked| if (changed.folder) Absent else Present(if (is_picked) "true" else "false"))),
						Engine.attr_presence("aria-expanded", shown.map(|changed| if (changed.folder) Present(if (changed.folded) "false" else "true") else Absent)),
					],
					model.lift_row().update_by(asked, Model.pick_changed),
				),
				Html.span_s(shown.map(|changed| if (changed.folder) "" else Liton.change_text(changed.file.change)), [Engine.class_s(shown.map(|changed| "change ${Liton.change_text(changed.file.change)}"))]),
				Html.span_s(shown.map(|changed| Liton.file_lines(changed.file)), [Engine.class("lines")]),
			],
		)
	}

	## The diff of a Changes pane's file picked, once its hunks are known.
	file_diff : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Model.Pane) -> Elem(PaneCtx)
	file_diff = |model, id, pane|
		Engine.switch(
			pane.map2(
				model.signal(),
				|shown, state|
					match Model.git_hunks_of(state, shown) {
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
					Shown => Liton.git_diff(model, id, pane)
				},
		)

	## The main area's pane while a Changes pane's diff shows in its place:
	## Back to it, and the diff.
	main_diff : State(PaneCtx, Model.State), Signal(PaneCtx, Str) -> Elem(PaneCtx)
	main_diff = |model, id| {
		changes_id = model.signal().map(Model.main_diff)
		Html.div(
			"changes main-diff",
			[
				Html.button_s(id.map2(model.signal(), |pane_id, state| "Back to ${Widgets.find(Model.pane(state, pane_id).widget).title}"), [Engine.class("back")], model.update_by(changes_id, |state, pane_id| Model.show_in_main(state, pane_id, Bool.False))),
				Liton.file_diff(model, changes_id, changes_id.map2(model.signal(), |pane_id, state| Model.pane(state, pane_id))),
			],
		)
	}

	## A file's diff in the code view, in one column or old beside new, under
	## its path, which Open in Files shows in the Files pane and Open in main
	## area in the main area, in place of the chat, until Back.
	git_diff : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Model.Pane) -> Elem(PaneCtx)
	git_diff = |model, id, pane| {
		rows = pane.map2(model.signal(), |shown, state| Model.git_code(state, shown))
		path = id.map2(
			model.signal(),
			|pane_id, state|
				match Model.git_pane(state, pane_id).file {
					Selected(selected) => selected
					NoFile => ""
				},
		)
		Html.div(
			"file-diff",
			[
				Html.div("diff-path", [Html.span_s(path, [Engine.class("file-path")]), Html.button("Open in Files", [Html.boolean("hidden", model.signal().map(|state| !Model.panes(state).any(|shown| shown.widget == "files")))], model.update_by(path, Model.open_file)), Html.button("Open in main area", [Html.boolean("hidden", id.map2(model.signal(), |pane_id, state| Model.main_area_pane(state).is_empty() or Model.main_area_pane(state) == pane_id or Model.main_diff(state) == pane_id))], model.update_by(id, |state, pane_id| Model.show_in_main(state, pane_id, Bool.True)))]),
				Engine.when(rows.map(|listed| listed.is_empty()), || Html.p("No diff to show.", "missing"), || Engine.text("")),
				Liton.code_view(model, id, pane.map(|shown| if (Model.option(shown, "diff_layout") == "Split") "code-view split" else "code-view unified"), rows),
			],
		)
	}

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

	## A Room pane: the room it shows, or where to pick one.
	room_view : State(PaneCtx, Model.State), Signal(PaneCtx, Str) -> Elem(PaneCtx)
	room_view = |model, id| Engine.when(id.map2(model.signal(), |pane_id, state| Model.room_pane(state, pane_id).room_id.is_empty()), || Html.p("Pick a room in Rooms to show it here.", "missing"), || Liton.room_opened(model, id))

	## A Rooms pane: the rooms the daemon lists, the one focused marked, each
	## one's name, which focuses it, its kind and what is unread in it, and
	## Join or Leave.
	rooms : State(PaneCtx, Model.State) -> Elem(PaneCtx)
	rooms = |model0|
		Html.ul(
			[Engine.class("room-list"), Engine.attr("data-part", "list")],
			[
				Engine.each(
					model0.signal().map(Model.rooms_listed),
					|room| room.id,
					|row| {
						model = model0.lift_row()
						Html.li(
							[Engine.class_s(row.key().map2(model.signal(), |room_id, state| if (Model.focused(state, [Room]) == Room(room_id)) "focused" else "").map2(row.field(|room| if (room.joined) "room-row" else "room-row not-joined"), Liton.joined_classes)), Engine.attr("data-part", "room")],
							[
								Html.button_s(row.field(|room| "#${room.name}"), [Engine.class("room-name")], model.update_by(row.key(), |state, room_id| Model.open(state, Room(room_id)))),
								Html.span_s(row.field(|room| Liton.room_kind(room.kind)), [Engine.class("room-kind")]),
								Html.span_s(row.field(|room| Liton.room_unread(room.unread)), [Engine.class("room-unread"), Engine.test_id("room-unread")]),
								Liton.join_controls(model, row.field(|room| room)),
							],
						)
					},
				),
			],
		)

	## Whether you are in a room, and Join or Leave it, which shows at once.
	join_controls : State(ctx, Model.State), Signal(ctx, Rooms.Room) -> Elem(ctx)
	join_controls = |model, room|
		Html.div(
			"room-join",
			[
				Html.span_s(room.map2(model.signal(), |shown, state| if (Model.joining(state, shown.id)) (if (shown.joined) "Joining…" else "Leaving…") else if (shown.joined) "" else "Not joined"), [Engine.class("room-joined")]),
				Html.button_s(room.map(|shown| if (shown.joined) "Leave" else "Join"), [Html.aria_label_s(room.map(|shown| if (shown.joined) "Leave #${shown.name}" else "Join #${shown.name}"))], model.update_by(room.map(|shown| shown.id), Model.toggle_joined)),
			],
		)

	## A room shown: its name and topic, Join or Leave, and its messages,
	## the newest at the bottom, with who is typing. A forum's are its posts.
	## A thread opened shows beside them, or in their place in a narrow pane.
	room_opened : State(PaneCtx, Model.State), Signal(PaneCtx, Str) -> Elem(PaneCtx)
	room_opened = |model, id| {
		opened = id.map2(model.signal(), |pane_id, state| Model.room_pane(state, pane_id))
		room_id = opened.map(|shown| shown.room_id)
		shown = room_id.map2(model.signal(), |opened_id, state| Model.room_of(state, opened_id))
		Html.div_s(
			shown.map2(opened, |room, { root, .. }| Str.join_with(["room", if (room.kind == Forum) "forum" else "", if (root.is_empty()) "" else "threaded"].drop_if(Str.is_empty), " ")),
			[Html.div("room-main", Liton.room_main(model, id, room_id, shown)), Engine.when(opened.map(|{ root, .. }| !root.is_empty()), || Liton.room_thread(model, id, opened), || Engine.text(""))],
		)
	}

	## A room's header, messages and who is typing.
	room_main : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Str), Signal(PaneCtx, Rooms.Room) -> List(Elem(PaneCtx))
	room_main = |model, id, room_id, shown|
		[
			Html.div(
				"room-header",
				[
					Html.span_s(shown.map(|opened| "#${opened.name}"), [Engine.class("room-title"), Engine.test_id("room-title")]),
					Html.span_s(shown.map(|opened| opened.topic ?? ""), [Engine.class("room-topic")]),
					Liton.join_controls(model, shown),
				],
			),
			Html.div(
				"timeline-scroll",
				[
					Html.ul(
						[Engine.class("timeline room-timeline"), Engine.attr("data-part", "room")],
						[Engine.each(id.map2(model.signal(), |pane_id, state| Model.room_lines(state, pane_id)), |line| line.id, |row| Liton.room_message(model, id, row))],
					),
				],
			),
			Engine.when(room_id.map2(model.signal(), |opened, state| !Model.room_loaded(state, opened, "")), || Html.p("Loading…", "missing"), || Engine.text("")),
			Html.p_s(room_id.map2(model.signal(), |opened, state| Model.typing(state, opened, "")), [Engine.class("room-typing"), Engine.attr("role", "status"), Engine.test_id("room-typing")]),
			Liton.room_composer(model, id, Room, shown.map(|room| if (room.kind == Forum) "New post in #${room.name}" else "Message #${room.name}")),
		]

	## The thread a Rooms pane opened: its top-level message, its replies and
	## who is typing in it, and × to close it.
	room_thread : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Model.RoomPane) -> Elem(PaneCtx)
	room_thread = |model, id, opened|
		Html.section(
			"Thread",
			"room-thread-pane",
			[
				Html.div("room-header", [Html.span_s(Engine.const("Thread"), [Engine.class("room-title")]), Liton.icon_button(Engine.const("Close the thread"), "icon dismiss", model.update_by(id, |state, pane_id| Model.open_thread(state, { pane_id, root: "" })))]),
				Html.div(
					"timeline-scroll",
					[
						Html.ul(
							[Engine.class("timeline room-timeline"), Engine.attr("data-part", "thread")],
							[Engine.each(id.map2(model.signal(), |pane_id, state| Model.thread_lines(state, pane_id)), |line| line.id, |row| Liton.room_message(model, id, row))],
						),
					],
				),
				Engine.when(opened.map2(model.signal(), |{ room_id, root, .. }, state| !Model.room_loaded(state, room_id, root)), || Html.p("Loading…", "missing"), || Engine.text("")),
				Html.p_s(opened.map2(model.signal(), |{ room_id, root, .. }, state| Model.typing(state, room_id, root)), [Engine.class("room-typing"), Engine.attr("role", "status"), Engine.test_id("thread-typing")]),
				Liton.room_composer(model, id, Thread, Engine.const("Reply in the thread")),
			],
		)

	## The composer of a Rooms pane's room, or of the thread it opened, as
	## the chat's: Send shows the message at once as sending. A mention being
	## typed offers the room's members it may name.
	room_composer : State(PaneCtx, Model.State), Signal(PaneCtx, Str), [Room, Thread], Signal(PaneCtx, Str) -> Elem(PaneCtx)
	room_composer = |model, id, place, placeholder| {
		key = id.map(|pane_id| if (place == Thread) "${pane_id}/thread" else pane_id)
		Html.form(
			if (place == Thread) "Reply in the thread" else "Send to the room",
			[Engine.class("composer"), Engine.attr("data-part", "composer"), Engine.on("submit", model.update_by(key, Model.send_to_room))],
			[
				Html.div(
					"mention-choices",
					[
						Engine.each(
							key.map2(model.signal(), |draft_key, state| Model.mention_choices(state, draft_key)),
							|name| name,
							|row| Html.button_s(row.key().map(|name| "@${name}"), [], model.lift_row().update_by(row.key().map2(key.lift_row(), |name, draft_key| { key: draft_key, name }), Model.mention)),
						),
					],
				),
				Liton.composer_input(model, key, { name: if (place == Thread) "Your reply" else "Your message", placeholder }, Model.send_to_room),
				Html.div("composer-row", [Html.submit_button("", [Engine.class("send"), Html.aria_label(if (place == Thread) "Send the reply" else "Send to the room")])]),
			],
		)
	}

	## A message: who wrote it, a person or an agent, how long ago, and
	## whether edited; its text as Markdown, unless deleted; its reactions;
	## and its thread's replies.
	room_message : State(PaneCtx, Model.State), Signal(PaneCtx, Str), RowRef(PaneCtx, Model.RoomLine) -> Elem(Row(PaneCtx, Model.RoomLine))
	room_message = |model0, id, row| {
		model = model0.lift_row()
		Html.li(
			[Engine.class_s(row.field(|line| Str.join_with(["room-message", if (line.agent) "agent" else "", if (line.deleted) "deleted" else "", if (line.failed) "failed" else if (line.status.is_empty()) "" else "pending"].drop_if(Str.is_empty), " "))), Engine.attr("data-part", "message")],
			[
				Html.div(
					"room-meta",
					[
						Html.span_s(row.field(|line| line.author), [Engine.class("room-author")]),
						Html.span_s(row.field(|line| if (line.agent) "agent" else ""), [Engine.class("room-agent")]),
						Engine.element("time", [Engine.attr_s("datetime", row.field(|line| line.time)), Engine.attr_s("title", row.field(|line| line.time))], [Engine.text_s(row.field(|line| line.ago))]),
						Html.span_s(row.field(|line| if (line.edited and !line.deleted) "edited" else ""), [Engine.class("room-edited")]),
					],
				),
				Engine.when(
					row.field(|line| line.deleted),
					|| Html.p("This message was deleted.", "room-deleted"),
					|| Liton.markdown(model, row.key().map2(id.lift_row(), |message_id, pane_id| "${pane_id}/${message_id}"), row.field(|line| Markdown.blocks(line.text))),
				),
				Html.div(
					"room-reactions",
					[
						Engine.each(
							row.field(|line| line.reactions),
							|reaction| reaction.emoji,
							|reaction|
								Html.button_s(
									reaction.field(|shown| "${shown.emoji} ${shown.count.to_str()}"),
									[Engine.class_s(reaction.field(|shown| if (shown.pending) "reaction pending" else "reaction")), Html.flag("aria-pressed", reaction.field(|shown| shown.mine)), Html.aria_label_s(reaction.field(|shown| if (shown.mine) "Take back ${shown.emoji}" else "React with ${shown.emoji}"))],
									model.lift_row().update_by(reaction.field(|shown| shown).map2(row.key().lift_row().map2(id.lift_row().lift_row(), |message_id, pane_id| { message_id, pane_id }), |shown, { message_id, pane_id }| { pane_id, message_id, emoji: shown.emoji, mine: shown.mine }), Model.toggle_reaction),
								),
						),
						# The reactions no one has made yet, to make.
						Engine.each(
							row.field(|line| if (line.deleted or !line.status.is_empty()) [] else Liton.reaction_choices.drop_if(|emoji| line.reactions.any(|reaction| reaction.emoji == emoji))),
							|emoji| emoji,
							|choice| Html.button_s(choice.key(), [Engine.class("react"), Html.aria_label_s(choice.key().map(|emoji| "React with ${emoji}"))], model.lift_row().update_by(choice.key().map2(row.key().lift_row().map2(id.lift_row().lift_row(), |message_id, pane_id| { message_id, pane_id }), |emoji, { message_id, pane_id }| { pane_id, message_id, emoji, mine: Bool.False }), Model.toggle_reaction)),
						),
					],
				),
				Engine.when(row.field(|line| !line.status.is_empty()), || Html.span_s(row.field(|line| line.status), [Engine.class("sent-status"), Engine.test_id("room-sent-status")]), || Engine.text("")),
				Engine.when(
					row.field(|line| line.failed),
					||
						Html.div(
							"room-retry",
							[
								Html.button("Retry", [], model.update_by(row.field(|line| { serial: line.serial, again: Bool.True }), Model.resend)),
								Html.button("Discard", [], model.update_by(row.field(|line| { serial: line.serial, again: Bool.False }), Model.resend)),
							],
						),
					|| Engine.text(""),
				),
				Engine.when(
					row.field(|line| line.threaded and line.status.is_empty()),
					||
						Html.div(
							"room-thread",
							[
								Html.button_s(row.field(Liton.replies_text), [Engine.class_s(row.field(|line| if (line.replies == 0) "start-thread" else "")), Engine.test_id("room-replies")], model.update_by(row.key().map2(id.lift_row(), |root, pane_id| { pane_id, root }), Model.open_thread)),
								Html.span_s(row.field(|line| line.last_reply), [Engine.class("room-last-reply")]),
							],
						),
					|| Engine.text(""),
				),
			],
		)
	}

	## The reactions a message offers to make: a +, as a like, and two more.
	reaction_choices : List(Str)
	reaction_choices = ["+", "👀", "🎉"]

	## A thread's replies and who replied, as "2 replies · Scout, Ada", or
	## Reply to start one.
	replies_text : Model.RoomLine -> Str
	replies_text = |line|
		match line.replies {
			0 => "Reply"
			1 => "1 reply · ${line.repliers}"
			count => "${count.to_str()} replies · ${line.repliers}"
		}

	room_kind : Rooms.Kind -> Str
	room_kind = |kind|
		match kind {
			Channel => "channel"
			Forum => "forum"
			Direct => "direct"
			Announce => "announcements"
		}

	## What is unread in a room: messages, then mentions of you, as "3 @1".
	room_unread : [Counted({ messages : U32, mentions : U32 }), Unknown] -> Str
	room_unread = |unread|
		match unread {
			Counted({ messages, mentions }) => Str.join_with([if (messages > 0) messages.to_str() else "", if (mentions > 0) "@${mentions.to_str()}" else ""].drop_if(Str.is_empty), " ")
			Unknown => ""
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

	## A tool call as one muted line, its tool and the first line of its
	## input, which opens on the rest of its input and its output, all but
	## the output's first lines folded away, and is `open` at first or not.
	## It shimmers while running and is red once failed; the state's word is
	## for screen readers.
	tool_card : Signal(ctx, Model.ToolCard), Signal(ctx, Bool) -> Elem(ctx)
	tool_card = |card, open| {
		state = card.map(|shown| Liton.tool_state(shown.state))
		input = card.map(|shown| shown.input.split_first("\n") ?? { before: shown.input, after: "" })
		Engine.element(
			"details",
			[Engine.class_s(state.map(|name| "tool-card ${name}")), Engine.attr("data-part", "tool-card"), Html.boolean("open", open)],
			[
				Engine.element(
					"summary",
					[Engine.class("tool-line")],
					[
						Html.span_s(card.map(|shown| shown.tool), [Engine.class("tool-name")]),
						Html.span_s(input.map(|lines| lines.before), [Engine.class("tool-target")]),
						Html.span_s(state, [Engine.class("tool-state"), Engine.test_id("tool-state")]),
					],
				),
				Html.pre_s(input.map(|lines| lines.after), [Engine.class("tool-input")]),
				Html.pre_s(card.map(|shown| shown.output), [Engine.class("tool-output")]),
				Engine.when(
					card.map(|shown| !shown.folded.is_empty()),
					||
						Engine.element(
							"details",
							[Engine.class("tool-more")],
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

	## A fold's line, which opens it or closes it again. Like a tool call's,
	## it shimmers while one under it runs and is red if one failed.
	fold_line : State(ctx, Model.State), Signal(ctx, Str), Signal(ctx, Model.Fold) -> Elem(ctx)
	fold_line = |model, id, fold|
		Html.button_s(
			fold.map(|shown| shown.summary),
			[
				Engine.attr("type", "button"),
				Engine.class_s(fold.map(|shown| "fold-line ${Liton.tool_state(shown.state)}")),
				Html.flag("aria-expanded", fold.map(|shown| shown.open)),
			],
			model.update_by(fold.map2(id, |shown, pane_id| { pane_id, key: shown.key }), Model.toggle_fold),
		)

	tool_state : [Running, Done, Failed] -> Str
	tool_state = |state|
		match state {
			Running => "running"
			Done => "done"
			Failed => "failed"
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
									|line| Liton.highlighted(Engine.const("line"), line.field(|keyed| keyed.tokens)),
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
			TurnEnded({ started, ended }) => Model.worked(started ?? "", ended)
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
			TurnEnded(_) => "entry turn-end"
		}
}

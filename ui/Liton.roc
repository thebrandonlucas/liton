## liton's UI: a grid of tiles of panes, each a widget bound to a capability
## the daemon advertises, and the effects that keep them current.
import pf.Engine exposing [Elem, Handler, HandlerOf, In, Root, Row, RowRef, Signal, State]
import pf.Html
import cap.Attention
import cap.Capability
import cap.Chat
import cap.Manifest
import cap.Protocol
import cap.Review
import cap.Rooms
import cap.Tickets
import cap.WorkspaceGit
import setup.Setup
import Highlight
import Markdown
import Microphone
import Ports
import Themes
import Model
import Keymap
import Palette
import Commands
import Conversation
import TicketDesk
import ReviewDesk
import Widgets
import Dropdown
import Drag
import Wallpaper
import Spinner

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

	## The surface last opened, `Model.State`'s `surface`.
	surface_key : Str
	surface_key = "liton.surface"

	## "mac" on a Mac, whose keys are written ⌘B: ui/ports.mjs writes it as
	## the page loads, as roc-signals's boot doesn't tell the platform.
	platform_key : Str
	platform_key = "liton.platform"

	## The ticket views saved, which this browser keeps.
	views_key : Str
	views_key = "liton.ticket-views"

	coarse_pointer_query : Str
	coarse_pointer_query = "(pointer: coarse)"

	program : Engine.Program
	program = Engine.program_boot(
		{ storage_keys: [Liton.snapshot_key, Liton.views_key, Liton.glass_key, Liton.surface_key, Wallpaper.url_key, Wallpaper.dim_key, ReviewDesk.viewed_key], session_keys: [Liton.platform_key], media: [Liton.coarse_pointer_query], max_inflight: 32 },
		|boot| Engine.state(Model.restore_views(Wallpaper.restored(Model.went({ ..Liton.restored_surface(Model.initial(Engine.boot_storage(boot, Liton.snapshot_key) ?? ""), Engine.boot_storage(boot, Liton.surface_key)), review_desk: { ..ReviewDesk.initial, viewed: ReviewDesk.restored(Engine.boot_storage(boot, ReviewDesk.viewed_key) ?? "") }, glass: Engine.boot_storage(boot, Liton.glass_key) != Ok("off"), coarse_pointer: Engine.boot_media(boot, Liton.coarse_pointer_query) ?? Bool.False, operating_system: if (Engine.boot_session(boot, Liton.platform_key) == Ok("mac")) Mac else Other, now: boot.now_ms }, boot.url), Engine.boot_storage(boot, Wallpaper.url_key) ?? "", Engine.boot_storage(boot, Wallpaper.dim_key) ?? ""), Engine.boot_storage(boot, Liton.views_key) ?? "[]"), |model| Engine.state(Drag.idle, |drag| Liton.page(model.lift(), drag))),
	).with_ports(Ports.registrations)

	## The surface the browser kept, else the one the model starts with.
	restored_surface : Model.State, Try(Str, _) -> Model.State
	restored_surface = |state, kept|
		match kept {
			Ok(surface) => { ..state, surface }
			Err(_) => state
		}

	## The theme is custom properties on the root (`Themes.style`), which the
	## stylesheet alone uses. Keys run commands as `Keymap.defaults` binds
	## them, and a sequence begun ends after a pause.
	page : State(Ctx, Model.State), State(Ctx, Drag.Gesture) -> Elem(Ctx)
	page = |model, drag| {
		# The layout shown: while a pane is dragged, as if dropped where it is.
		laid = model.signal().map2(drag.signal(), Drag.previewed)
		Engine.element(
			"div",
			[
				Engine.class("liton"),
				Engine.attr_s("style", model.signal().map(|state| Themes.style(Wallpaper.over(Model.theme_shown(state), state), state.glass))),
				Engine.on_document_key({ keymap: Engine.const(Keymap.heard(Keymap.defaults)) }, model.set_value_by(drag.signal(), |state, gesture, key| if (Drag.dragging(gesture) and key.key == "Escape") state else Keymap.pressed(Keymap.defaults, state, Keymap.name(key))).also(drag.set_value(|gesture, key| Drag.key_pressed(gesture, key.key)))),
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
									laid.map(Model.tiles_in_order),
									|tile| tile.id,
									|row|
										Html.button_s(
											row.field(|tile| tile).map2(laid.lift_row(), Liton.tile_tab_label),
											[
												# Its icon is its active pane's widget's (style.css).
												Engine.class_s(row.field(|tile| tile.panes.find_first(|pane| pane.id == tile.active).map_ok(|pane| "widget-${pane.widget}") ?? "")),
												Html.flag("aria-pressed", row.key().map2(model.signal().lift_row(), |key, state| key == state.active_tile)),
												Engine.test_id_s(row.key().map2(model.signal().lift_row(), |key, state| "show-${Model.tile_test_name(state, key)}")),
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
						# `threads-apart` lays the right drawer over the main area on
						# a narrower screen, as a thread opened from it shows there.
						Html.div_attrs(
							[
								Engine.class_s(laid.map(|state| "grid ${if (state.shell == Workbench) "workbench" else "tiling"}${if (Model.panes(state).any(|pane| pane.id == state.focused_pane)) " focusing" else ""}${if (Model.threads_apart(state)) " threads-apart" else ""}")),
								Engine.attr_s("style", laid.map(Liton.grid_style)),
								Engine.test_id("grid"),
							],
							[Engine.each(laid.map(Model.tiles_in_order), |tile| tile.id, |row| Liton.tile_view(model, drag, laid, row))],
						),
						Liton.ghost(model, drag),
						Liton.settings(model),
						Liton.toast(model),
					],
				),
				# Under an open ⋯ menu's pane: a click anywhere else closes it.
				Engine.when(
					model.signal().map(|state| !state.menu.is_empty()),
					|| Html.div_attrs([Engine.class("menu-backdrop"), Engine.on_click(model.update(|state| { ..state, menu: "" }))], []),
					|| Engine.text(""),
				),
				Liton.palette(model),
				Liton.shortcuts(model),
			].concat(Liton.effects(model)).concat(Liton.drag_effects(model, drag)).concat(Microphone.effects(model)).concat(Wallpaper.effects(model)),
		)
	}

	## While a pane is held, the page reports the pointer (`Drag.pointer`):
	## its moves drag the pane, and its release drops it.
	drag_effects : State(Ctx, Model.State), State(Ctx, Drag.Gesture) -> List(Elem(Ctx))
	drag_effects = |model, drag| [
		Engine.watch_latest(
			drag.signal().map(Drag.held),
			|held|
				match held {
					Holding({ pointer, column, row, .. }) => [Drag.pointer.ask({ pointer, column, row })]
					NotHolding => []
				},
			model.on_result(
				|state, held, res|
					match (held, res) {
						(Holding(holding), Ok(at)) => Drag.dropped(state, holding, at)
						_ => state
					},
			).also(
				drag.on_result(
					|gesture, _, res|
						match res {
							Ok(at) => Drag.heard(gesture, at)
							Err(_) => Drag.idle
						},
				),
			),
		),
	]

	## A picture of the pane dragged, its title, following the pointer.
	ghost : State(Ctx, Model.State), State(Ctx, Drag.Gesture) -> Elem(Ctx)
	ghost = |model, drag|
		Engine.when(
			drag.signal().map(Drag.dragging),
			||
				Html.div_attrs(
					[
						Engine.class("drag-ghost"),
						Engine.test_id("drag-ghost"),
						Engine.attr("aria-hidden", "true"),
						Engine.attr_s(
							"style",
							drag.signal().map(
								|gesture|
									match gesture {
										Dragging({ at, .. }) => "transform: translate(${at.x.to_str()}px, ${at.y.to_str()}px)"
										_ => ""
									},
							),
						),
					],
					[
						Engine.text_s(
							model.signal().map2(
								drag.signal(),
								|state, gesture|
									match gesture {
										Dragging({ pane, .. }) => Liton.label(state, Model.pane(state, pane))
										_ => ""
									},
							),
						),
					],
				),
			|| Engine.text(""),
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
		Engine.watch_changes(model.signal().map(|state| state.palette.picked), |_| [Engine.command(Engine.scroll_into_view("palette-picked", {}))], Engine.ignore({})),
		# A file picked in the Review surface's navigator scrolls its view to it.
		Engine.watch_changes(model.signal().map(|state| state.review_desk.scroll), |scroll| scroll.refs.map(|ref| Engine.command(Engine.scroll_into_view(ref, { block: Start }))), Engine.ignore({})),
		Engine.watch(model.signal().map(|state| state.keys_typed), |typed| if (typed.keys.is_empty()) [] else [Engine.timer(1500)], model.on_result(|state, typed, _| Keymap.paused(state, typed.serial))),
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
		Engine.watch_changes(model.signal().map(|state| Json.to_str(state.tickets.saved)), |text| [Engine.command(StorageSet(Liton.views_key, text))], Engine.ignore({})),
		Engine.watch(model.signal().map(|state| state.surface), |surface| [Engine.command(StorageSet(Liton.surface_key, surface))], Engine.ignore({})),
		Engine.watch_changes(model.signal().map(|state| state.review_desk.viewed), |viewed| [Engine.command(StorageSet(ReviewDesk.viewed_key, Json.to_str(viewed)))], Engine.ignore({})),
		Engine.watch_changes(model.signal().map(|state| state.glass), |glass| [Engine.command(StorageSet(Liton.glass_key, if (glass) "on" else "off"))], Engine.ignore({})),
	]

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
	settings_toggle = |model, class| Html.button("", [Engine.class(class), Html.aria_label("Settings"), Engine.attr_s("title", model.signal().map(|state| "Settings (${Keymap.text_of(state.operating_system, Keymap.defaults, "settings")})")), Html.flag("aria-expanded", model.signal().map(|state| state.show_settings))], model.update(Model.toggle_settings))

	## The palette over everything, which a click outside closes: a box to
	## type in, and the entries what is typed matches, each with its group
	## and keys. The arrows, or Ctrl+N and Ctrl+P, pick one, and Enter or a
	## click runs it. Ctrl+K, heard here though a text box, closes it.
	palette : State(Ctx, Model.State) -> Elem(Ctx)
	palette = |model| {
		moves = [Engine.Chord.plain("ArrowDown"), Engine.Chord.plain("ArrowUp"), Engine.Chord.plain("Enter"), Engine.Chord.plain("n").with_ctrl(), Engine.Chord.plain("p").with_ctrl(), Engine.Chord.plain("k").with_ctrl()]
		moved = |state, key|
			match key.key {
				"Enter" => Palette.run_picked(state)
				"k" => Commands.close(state)
				"ArrowUp" | "p" => Palette.move(state, Up)
				_ => Palette.move(state, Down)
			}
		shown = model.signal().map(Palette.shown)
		Engine.when(
			model.signal().map(|state| state.palette.open),
			||
				Html.div(
					"palette-layer",
					[
						Html.div_attrs([Engine.class("palette-backdrop"), Engine.on_click(model.update(Commands.close))], []),
						Html.section_attrs(
							"Palette",
							[Engine.class("palette"), Engine.attr("role", "dialog")],
							[
								# Password managers fill any text box that looks like a login unless
								# told not to, each by its own attribute (Bitwarden, 1Password,
								# LastPass, Dashlane); a search combobox reads as no login.
								Html.text_input(Engine.const("Command or place"), "search", model.signal().map(|state| state.palette.query), [Engine.ref("palette"), Engine.attr("placeholder", "Type a command, session or workspace"), Engine.attr("autocomplete", "off"), Engine.attr("role", "combobox"), Engine.attr("aria-autocomplete", "list"), Engine.attr("spellcheck", "false"), Engine.attr("data-bwignore", "true"), Engine.attr("data-1p-ignore", "true"), Engine.attr("data-lpignore", "true"), Engine.attr("data-form-type", "other"), Engine.on_key({ keymap: Engine.const(Engine.Keymap.prevent(moves)) }, model.set_value(moved))], model.set_value(Palette.typed)),
								Engine.when(shown.map(List.is_empty), || Html.p("Nothing matches.", "palette-empty"), || Engine.text("")),
								Html.ul(
									[Engine.class("palette-entries"), Engine.attr("role", "listbox"), Html.aria_label("Commands and places")],
									[
										Engine.each(
											shown,
											|entry| entry.key,
											|row|
												Html.li(
													[],
													[
														Engine.element(
															"button",
															[
																Engine.attr("type", "button"),
																Engine.attr("role", "option"),
																Engine.class("palette-entry"),
																Html.aria_label_s(row.field(|entry| entry.title)),
																Html.flag("aria-selected", row.field(|entry| entry.picked)),
																Engine.ref_s(row.field(|entry| if (entry.picked) "palette-picked" else "")),
																Engine.on_click(model.lift_row().update_by(row.key(), Palette.run)),
															],
															[
																Html.span_s(row.field(|entry| entry.title), [Engine.class("palette-title")]),
																Html.span_s(row.field(|entry| entry.group), [Engine.class("palette-group")]),
																Engine.element("kbd", [], [Engine.text_s(row.field(|entry| entry.keys))]),
															],
														),
													],
												),
										),
									],
								),
							],
						),
					],
				),
			|| Engine.text(""),
		)
	}

	## The keys and what each runs, as `Keymap.defaults` binds them, which
	## Escape or a click outside closes.
	shortcuts : State(Ctx, Model.State) -> Elem(Ctx)
	shortcuts = |model|
		Engine.when(
			model.signal().map(|state| state.show_shortcuts),
			||
				Html.div(
					"palette-layer",
					[
						Html.div_attrs([Engine.class("palette-backdrop"), Engine.on_click(model.update(Commands.close))], []),
						Html.section_attrs(
							"Keys",
							[Engine.class("palette shortcuts"), Engine.attr("role", "dialog")],
							[
								Html.h2("Keys", ""),
								Liton.key_list(model),
							],
						),
					],
				),
			|| Engine.text(""),
		)

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
		command = if (drawer == Left) "drawer.left" else "drawer.right"
		panes = model.signal().map(|state| "${Str.join_with(state.grid.tiles.keep_if(|tile| Model.slot_of(state, tile.id) == drawer).join_map(|tile| Model.shown_panes(state, tile).map(|pane| Liton.label(state, pane))), " · ")} (${Keymap.text_of(state.operating_system, Keymap.defaults, command)})")
		Engine.element(
			"button",
			[
				Engine.attr("type", "button"),
				Engine.class("icon drawer-toggle drawer-${Model.slot_name(drawer)}"),
				Html.aria_label(if (drawer == Left) "Left drawer" else "Right drawer"),
				Engine.attr_s("title", panes),
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
	## A workspace tile's header has them in its place.
	header_place : Model.State, Model.Tile, Str -> [MainTab, MainTabWithSettings, LeftTab, Elsewhere]
	header_place = |state, tile, pane_id| {
		left_shown = !state.collapsed.contains(Left) and state.grid.tiles.any(|listed| Model.slot_of(state, listed.id) == Left and !listed.panes.is_empty())
		first = tile.id == Model.slot_tile(state, Model.slot_of(state, tile.id))
		match Model.slot_of(state, tile.id) {
			_ if state.shell != Workbench or tile.active != pane_id or !first or Model.workspace_tile(state) == Ok(tile.id) => Elsewhere
			Main => if (left_shown) MainTab else MainTabWithSettings
			Left => LeftTab
			_ => Elsewhere
		}
	}

	## What Settings says the keys do, written as the platform writes them.
	keys_help : Model.Platform -> Str
	keys_help = |system| {
		key = |command| Keymap.text_of(system, Keymap.defaults, command)
		heard = if (system == Mac) "in a text box too" else "outside a text box"
		"${Keymap.text(system, ["Alt+1"])} to ${Keymap.text(system, ["Alt+9"])} show them too, in this order, outside a text box, and ${Keymap.text(system, ["Mod+1"])} to ${Keymap.text(system, ["Mod+9"])}, or G then 1 to 9, go to that workspace. ${key("drawer.left")} and ${key("drawer.right")} show or hide the drawers, ${key("settings")} opens Settings and ${key("palette")} the palette of commands and places, ${heard}; ? outside a text box lists every key, and Escape closes the palette, the keys, a menu or Settings, or else stops the chat's agent."
	}

	## Settings, a page of its own: a rail of its sections, App's, the
	## surface's and the snapshot, beside the section picked, which opens at
	## the surface's. On a phone the rail is a list, and a section picked
	## covers it until its ← goes back.
	settings : State(Ctx, Model.State) -> Elem(Ctx)
	settings = |model| {
		picked = model.signal().map(|state| state.settings_page.section)
		shown = |section, view| Engine.when(picked.map(|id| id == section), view, || Engine.text(""))
		Engine.when(
			model.signal().map(|state| state.show_settings),
			||
				Html.section_attrs(
					"Settings",
					[Engine.class_s(model.signal().map(|state| if (state.settings_page.pushed) "settings pushed" else "settings"))],
					[
						Engine.element(
							"nav",
							[Engine.class("settings-rail"), Html.aria_label("Sections")],
							[
								Html.button("← Back", [Engine.class("settings-close"), Html.aria_label("Close settings")], model.update(Model.toggle_settings)),
								Html.h3("App", "settings-group"),
							]
								.concat(Liton.settings_sections.map(|(section, title)| Liton.section_button(model, section, title)))
								.concat([Html.h3("Host", "settings-group"), Html.button_s(model.signal().map(|state| if (state.daemon.name.is_empty()) "This daemon" else state.daemon.name), [Html.flag("aria-pressed", model.signal().map(|state| state.settings_page.section == "host"))], model.update(|state| Model.show_section(state, "host")))])
								.concat([Html.h3("Surface", "settings-group"), Liton.section_button(model, "surface", "Surface"), Liton.section_button(model, "snapshot", "Snapshot")]),
						),
						Html.div(
							"settings-detail",
							[
								Html.div(
									"settings-header",
									[
										Html.button("←", [Engine.class("back-to-sections"), Html.aria_label("Back to the sections")], model.update(|state| { ..state, settings_page: { ..state.settings_page, pushed: Bool.False } })),
										Html.h2_s(model.signal().map(|state| if (state.settings_page.section == "host") "Host · ${state.daemon.name}" else Liton.section_title(state.settings_page.section)), []),
									],
								),
								shown("appearance", || Liton.appearance(model)),
								shown("keys", || Liton.keys_section(model)),
								shown("voice", || Liton.voice_section(model)),
								shown("about", || Liton.about),
								shown("host", || Liton.host_section(model)),
								shown("surface", || Liton.surface_section(model)),
								shown("snapshot", || Liton.snapshot_section(model)),
							],
						),
					],
				),
			|| Engine.text(""),
		)
	}

	## App's sections in Settings' rail, by id and title.
	settings_sections : List((Str, Str))
	settings_sections = [("appearance", "Appearance"), ("keys", "Keys"), ("voice", "Voice"), ("about", "About")]

	section_title : Str -> Str
	section_title = |section| Liton.settings_sections.concat([("surface", "Surface"), ("snapshot", "Snapshot")]).find_first(|(id, _)| id == section).map_ok(|(_, title)| title) ?? section

	## A section in Settings' rail, pressed while shown.
	section_button : State(Ctx, Model.State), Str, Str -> Elem(Ctx)
	section_button = |model, section, title| Html.button(title, [Html.flag("aria-pressed", model.signal().map(|state| state.settings_page.section == section))], model.update(|state| Model.show_section(state, section)))

	## A card of settings under its title, as Paseo's: rows that touch.
	settings_card : Str, List(Elem(ctx)) -> Elem(ctx)
	settings_card = |title, rows| Html.div("settings-card-group", [Html.h3(title, ""), Html.div("settings-card", rows)])

	## The theme, the glass and the background.
	appearance : State(Ctx, Model.State) -> Elem(Ctx)
	appearance = |model|
		Html.div(
			"settings-section",
			[
				Liton.settings_card(
					"Theme",
					[
						Html.div(
							"choices settings-row",
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
						Html.div(
							"settings-row",
							[
								Engine.element("label", [Engine.class("toggle")], [Html.checkbox(Engine.const("Glass"), model.signal().map(|state| state.glass), [], model.set_value(|state, checked| { ..state, glass: checked })), Engine.text("Glass")]),
								Html.p("Blurs what is behind the tiles. Blurring is work for the graphics card: turn it off on a slow device.", "help"),
							],
						),
					],
				),
				Liton.settings_card("Background", [Html.div("settings-row", [Wallpaper.settings(model)])]),
			],
		)

	## The keys and the commands they run, as `⇧?` lists them.
	keys_section : State(Ctx, Model.State) -> Elem(Ctx)
	keys_section = |model|
		Html.div(
			"settings-section",
			[
				Html.p_s(model.signal().map(|state| Liton.keys_help(state.operating_system)), [Engine.class("help")]),
				Liton.settings_card("Bound", [Liton.key_list(model)]),
			],
		)

	## Each command bound, by its title, with its keys.
	key_list : State(Ctx, Model.State) -> Elem(Ctx)
	key_list = |model|
		Html.ul(
			[Engine.class("palette-entries")],
			[Engine.each(model.signal().map(|state| Keymap.listed(Keymap.defaults, state)), |bound| bound.title, |row| Html.li([Engine.class("shortcut")], [Html.span_s(row.field(|bound| bound.title), [Engine.class("palette-title")]), Engine.element("kbd", [], [Engine.text_s(row.field(|bound| bound.keys))])]))],
		)

	## The voice that speaks replies, while the daemon offers voice.v1.
	voice_section : State(Ctx, Model.State) -> Elem(Ctx)
	voice_section = |model|
		Html.div(
			"settings-section",
			[
				Microphone.settings(model, Liton.choices),
				Engine.when(model.signal().map(|state| state.capabilities.contains(Capability.voice_v1)), || Engine.text(""), || Html.p("No provider of this daemon offers voice.v1.", "help")),
			],
		)

	## The versions of what this UI speaks.
	about : Elem(Ctx)
	about =
		Liton.settings_card(
			"liton",
			[
				Html.div("settings-row", [Html.p("Protocol", ""), Html.p("liton/v1, version ${Manifest.protocol.to_str()}", "help")]),
				Html.div("settings-row", [Html.p("Snapshots", ""), Html.p("version ${Setup.snapshot_version.to_str()}", "help")]),
			],
		)

	## What the daemon offers: its providers, each remote's under its name,
	## with the capabilities each supplies, and its transformers, each with
	## what it derives from what.
	host_section : State(Ctx, Model.State) -> Elem(Ctx)
	host_section = |model| {
		row = |title, detail| Html.div("settings-row", [Html.span_s(title, [Engine.class("settings-row-title")]), Html.p_s(detail, [Engine.class("help")])])
		Html.div(
			"settings-section",
			[
				Liton.settings_card(
					"Providers",
					[Engine.each(model.signal().map(|state| state.providers), |provider| provider.id, |provider| row(provider.field(|shown| "${shown.name} (${shown.id})"), provider.field(|shown| Str.join_with(shown.capabilities.map(Capability.to_str), ", "))))],
				),
				Liton.settings_card(
					"Remotes",
					[
						Engine.each(model.signal().map(Liton.remotes), |remote| remote.name, |remote| row(remote.key(), remote.field(|shown| "${shown.count.to_str()} providers"))),
						Engine.when(model.signal().map(|state| Liton.remotes(state).is_empty()), || Html.div("settings-row", [Html.p("No remotes: every provider runs in this daemon.", "help")]), || Engine.text("")),
					],
				),
				Liton.settings_card(
					"Transformers",
					[Engine.each(model.signal().map(|state| state.transformers), |transformer| transformer.id, |transformer| row(transformer.field(|shown| shown.name), transformer.field(|shown| "${Capability.to_str(shown.offers)} from ${Str.join_with(shown.uses.map(Capability.to_str), ", ")}")))],
				),
			],
		)
	}

	## The remotes whose providers the daemon offers, as their ids name
	## them (`<remote>/<id>`), each with how many.
	remotes : Model.State -> List({ name : Str, count : U64 })
	remotes = |state|
		state.providers.fold(
			[],
			|found, provider|
				match Str.split_on(provider.id, "/") {
					[name, _, ..] => if (found.any(|remote| remote.name == name)) found.map(|remote| if (remote.name == name) { ..remote, count: remote.count + 1 } else remote) else found.append({ name, count: 1 })
					_ => found
				},
		)

	## The surface open: the surfaces to open instead, those the daemon
	## offers what they need; its tiles' panes to swap, move, remove or set
	## the options of; and, once changed, a reset to the surface opened.
	surface_section : State(Ctx, Model.State) -> Elem(Ctx)
	surface_section = |model|
		Html.div(
			"settings-section",
			[
				Liton.settings_card(
					"Open a surface",
					[
						Html.div(
							"choices settings-row",
							[
								Engine.each(
									model.signal().map(Model.surfaces),
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
					],
				),
				Liton.settings_card("Layout", [Engine.each(model.signal().map(Model.tiles_in_order), |tile| tile.id, |row| Liton.settings_tile(model, row))]),
				Engine.when(
					model.signal().map(|state| state.presets.any(|preset| preset.name == state.surface) and !Model.preset_shown(state, state.surface)),
					|| Html.div("choices", [Html.button_s(model.signal().map(|state| "Reset to ${state.surface}"), [], model.update(|state| Model.with_snapshot_text(Model.use_preset(state, state.surface))))]),
					|| Engine.text(""),
				),
			],
		)

	## The layout as a snapshot, to copy and share, or to paste and load.
	snapshot_section : State(Ctx, Model.State) -> Elem(Ctx)
	snapshot_section = |model|
		Html.div(
			"settings-section",
			[
				Html.p("This layout as a snapshot. Copy it to share it, or paste one and load it.", "help"),
				Html.textarea(Engine.const("Snapshot"), model.signal().map(|state| state.snapshot_text), [], model.set_value(|state, text| { ..state, snapshot_text: text })),
				Html.div("choices", [Html.button("Load snapshot", [], model.update(Model.load_snapshot))]),
			],
		)

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
							model.signal().map2(id, |state, pane_id| !Model.swaps(state, pane_id).is_empty()),
							||
								Dropdown.select(
									title.map(|name| "Swap ${name} for"),
									row.field(|shown| shown.widget),
									[],
									[Engine.each(model.signal().map2(pane, |state, shown| Model.swaps(state, shown.id).prepend(Widgets.find(shown.widget))), |widget| widget.id, |choice| Engine.element("option", [Engine.prop_s(Engine.Prop.value, choice.key())], [Engine.text_s(choice.field(|widget| widget.title))]))],
									model.set_value_by(id, |state, pane_id, widget| Model.with_snapshot_text(Model.swap_part(state, pane_id, widget))),
								),
							|| Engine.text(""),
						),
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
	tile_view : State(Ctx, Model.State), State(Ctx, Drag.Gesture), Signal(Ctx, Model.State), RowRef(Ctx, Model.Tile) -> Elem(TileCtx)
	tile_view = |model0, drag0, laid0, row| {
		model = model0.lift_row()
		drag = drag0.lift_row()
		laid = laid0.lift_row()
		id = row.key()
		tile = row.field(|shown| shown)
		panel = id.map2(laid, |tile_id, state| if (Model.slot_tile(state, Model.slot_of(state, tile_id)) == tile_id) Model.slot_of(state, tile_id) else Free)
		tiling = model.signal().map(|state| state.shell == Tiling)
		classes = tile.map2(laid, |shown, state| Liton.tile_class(state, shown))
		over = model.signal().map2(drag.signal(), Drag.over)
		Engine.element(
			"div",
			[
				Engine.class_s(classes.map2(id.map2(over, Liton.tile_drop_class), Liton.joined_classes)),
				Engine.test_id_s(id.map2(laid, |tile_id, state| "slot-${Model.tile_test_name(state, tile_id)}")),
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
				Engine.when(
					id.map2(laid, |tile_id, state| Model.workspace_tile(state) == Ok(tile_id)),
					|| Html.div("workspace-view-header", [Liton.workspace_header(model, drag, tile), Liton.workspace_tabs(model, drag, tile)]),
					|| Liton.tile_tabs(model, drag, laid, id, tile, tiling),
				),
				Engine.each(row.field(|shown| shown.panes), |pane| pane.id, |pane_row| Liton.pane_view(model, drag, laid, tile, pane_row)),
				# Handles on its right and bottom edges move the lines there.
				Engine.each(
					tile.map2(laid, |shown, state| Model.resize_lines(state, shown)),
					|line| if (Liton.across(line)) "right" else "bottom",
					|line_row|
						Html.div_attrs(
							[
								Engine.class_s(line_row.key().map(|edge| "resize-line ${edge}")),
								Engine.attr("role", "separator"),
								Engine.attr_s("aria-orientation", line_row.key().map(|edge| if (edge == "right") "vertical" else "horizontal")),
								Engine.test_id_s(line_row.key().map2(id.lift_row(), |edge, tile_id| "resize-${tile_id}-${edge}")),
								Html.on_pointer_down_capture(drag.lift_row().set_value_by(line_row.field(|line| line), Drag.pressed_line)),
								Html.on_pointer_up(drag.lift_row().set_value(Drag.released)),
							],
							[],
						),
				),
			],
		)
	}

	## A tile's bar of its tabs, each with a × that hides it in a Workbench
	## and closes it in Tiling, and in Tiling its controls.
	tile_tabs : State(TileCtx, Model.State), State(TileCtx, Drag.Gesture), Signal(TileCtx, Model.State), Signal(TileCtx, Str), Signal(TileCtx, Model.Tile), Signal(TileCtx, Bool) -> Elem(TileCtx)
	tile_tabs = |model, drag, laid, id, tile, tiling|
		Html.div(
			"tile-header",
			[
				Engine.each(
					tile.map2(laid, |shown, state| Model.shown_panes(state, shown)),
					|pane| pane.id,
					|tab|
						Engine.element(
							"span",
							[Engine.class_s(tab.key().map2(drag.signal().lift_row(), |pane_id, gesture| Liton.joined_classes("tab", Liton.pane_drag_class(pane_id, gesture)))), Engine.attr_s("data-tab", tab.key())],
							[
								Html.button_s(
									tab.field(|pane| pane).map2(model.signal().lift_row(), |pane, state| Liton.label(state, pane)),
									[Engine.class_s(tab.field(|pane| "tab-select widget-${pane.widget}")), Html.flag("aria-pressed", tab.key().map2(tile.lift_row(), |key, shown| key == shown.active))].concat(Liton.grip(drag.lift_row(), tab.key())),
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
		)

	## The header of the workspace a Workbench shows as tabs: the left
	## drawer's button, its name and project, its ⋯ menu (`Model.row_menu`),
	## and the right drawer's button with its changes; Settings while the
	## left drawer is hidden. Dragging its name moves the workspace's view,
	## as its chat's tab does.
	workspace_header : State(TileCtx, Model.State), State(TileCtx, Drag.Gesture), Signal(TileCtx, Model.Tile) -> Elem(TileCtx)
	workspace_header = |model, drag, tile| {
		chat_pane = tile.map2(model.signal(), |shown, state| Model.tab_rows(state, shown).find_first(|row| row.widget == "chat").map_ok(|row| row.pane) ?? "")
		header = model.signal().map(Model.workspace_header)
		left_shown = model.signal().map(|state| !state.collapsed.contains(Left) and state.grid.tiles.any(|listed| Model.slot_of(state, listed.id) == Left and !listed.panes.is_empty()))
		Html.div(
			"workspace-header",
			[
				Liton.drawer_toggle(model, Left, Engine.const(Model.no_counts)),
				Html.span_s(header.map(|shown| shown.title), [Engine.class("workspace-title"), Engine.test_id("workspace-title")].concat(Liton.grip(drag, chat_pane))),
				Html.span_s(header.map(|shown| shown.project), [Engine.class("workspace-project")]),
				Engine.when(header.map(|shown| !shown.key.is_empty()), || Liton.row_menu(model, header.map(|shown| { pane_id: Model.header_menu, key: shown.key }), Engine.const("Workspace")), || Engine.text("")),
				# FIXME: Paseo's run ▷, open in editor and git split button
				# (Commit, then View PR or Merge PR, or Archive) go here, once a
				# capability offers them: workspace.git.v1 only reads, so it
				# needs Commit and Push commands, and a forge capability (or
				# workspace.git) CreatePullRequest, MergePullRequest and the PR's
				# state.
				Html.div("git-actions", []),
				Liton.drawer_toggle(model, Right, header.map(|shown| shown.counts)),
				Engine.when(left_shown, || Engine.text(""), || Liton.settings_toggle(model, "icon settings-toggle")),
			],
		)
	}

	## The workspace tile's tabs (`Model.tab_rows`): a chat of each of the
	## focused workspace's sessions with its status, then the views it
	## opened and the tile's other panes, which drag as a tile's tabs do,
	## each with a × that closes it, and + with its menu of a new agent in
	## the workspace and the tile's panes hidden (`Model.tab_menu_items`).
	workspace_tabs : State(TileCtx, Model.State), State(TileCtx, Drag.Gesture), Signal(TileCtx, Model.Tile) -> Elem(TileCtx)
	workspace_tabs = |model, drag, tile|
		Html.div_attrs(
			[Engine.class("workspace-tabs"), Engine.attr("role", "tablist"), Html.aria_label_s(Engine.const("Tabs"))],
			[
				Engine.each(
					tile.map2(model.signal(), |shown, state| Model.tab_rows(state, shown)),
					|tab| tab.key,
					|tab| {
						# A tab drags the pane that shows it, as a tile's tab does.
						pane_id = tab.field(|shown| shown.pane)
						button = |dragging|
							Engine.element(
								"button",
								[
									Engine.attr("type", "button"),
									Engine.attr("role", "tab"),
									Engine.class_s(tab.field(|shown| "tab-select widget-${shown.widget}${if (shown.dot.is_empty() or shown.dot == "idle") "" else " with-status"}")),
									Html.flag("aria-selected", tab.field(|shown| shown.shown)),
									Engine.on_click(model.lift_row().update_by(tab.field(|shown| shown.tab), Model.pick_tab)),
								].concat(dragging),
								[
									Html.span_s(Engine.const(""), [Engine.class_s(tab.field(|shown| "status-dot ${shown.dot}")), Engine.attr("aria-hidden", "true")]),
									Html.span_s(tab.field(|shown| shown.title), [Engine.class("tab-title")]),
								],
							)
						Engine.element(
							"span",
							[Engine.class_s(tab.field(|shown| if (shown.shown) "workspace-tab shown" else "workspace-tab")), Engine.attr_s("data-tab", pane_id)],
							[
								Engine.when(pane_id.map(|id| id.is_empty()), || button([]), || button(Liton.grip(drag.lift_row(), pane_id))),
								Engine.when(tab.field(|shown| shown.closes), || Liton.icon_button(tab.field(|shown| "Close ${shown.title}"), "icon tab-close", model.lift_row().update_by(tab.field(|shown| shown.tab), Model.close_picked_tab)), || Engine.text("")),
							],
						)
					},
				),
				Html.div(
					"row-menu tab-menu",
					[
						Engine.element(
							"button",
							[
								Engine.attr("type", "button"),
								Engine.class("icon new-tab"),
								Html.aria_label("New tab"),
								Engine.attr_s("title", model.signal().map(|state| "New tab (${Keymap.text_of(state.operating_system, Keymap.defaults, "tab.new")})")),
								Engine.attr("aria-haspopup", "true"),
								Html.flag("aria-expanded", model.signal().map(|state| state.menu == Model.tab_menu)),
								Engine.on_click(model.update(|state| Model.toggle_menu(state, Model.tab_menu))),
							],
							[],
						),
						Engine.when(
							model.signal().map(|state| state.menu == Model.tab_menu),
							|| Html.div("menu", [Engine.each(model.signal().map(Model.tab_menu_items), |item| item.label, |item| Html.button_s(item.field(|shown| shown.label), [], model.lift_row().update_by(item.field(|shown| shown.pane), Model.pick_tab_menu)))]),
							|| Engine.text(""),
						),
					],
				),
			],
		)

	across : [Across(U64), Down(U64)] -> Bool
	across = |line|
		match line {
			Across(_) => Bool.True
			Down(_) => Bool.False
		}

	## The grid's tracks as CSS: a Workbench's drawers as wide as a drawer is
	## (the right one's `--right-drawer` where the stylesheet narrows it),
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
				Workbench if track + 1 == tracks => if (state.collapsed.contains(Right)) "0px" else "var(--right-drawer, minmax(240px, 380px))"
				_ => "minmax(${widest(track).to_str()}px, ${size.to_str()}fr)"
			}
		"grid-template-columns: ${Str.join_with(state.grid.columns.map_with_index(column), " ")}; grid-template-rows: ${Str.join_with(state.grid.rows.map(|size| "minmax(0, ${size.to_str()}fr)"), " ")}"
	}

	pane_view : State(TileCtx, Model.State), State(TileCtx, Drag.Gesture), Signal(TileCtx, Model.State), Signal(TileCtx, Model.Tile), RowRef(TileCtx, Model.Pane) -> Elem(PaneCtx)
	pane_view = |model0, drag0, laid, tile, row| {
		model = model0.lift_row()
		drag = drag0.lift_row()
		id = row.key()
		title = row.field(|pane| Widgets.find(pane.widget).title)
		shown = row.field(|pane| pane).map2(model.signal(), |pane, state| { pane: pane, state: state })
		place = id.map2(tile.lift_row(), |pane_id, group| { pane_id, group }).map2(model.signal(), |{ pane_id, group }, state| Liton.header_place(state, group, pane_id))
		room = id.map2(model.signal(), |pane_id, state| Model.room_of(state, Model.room_pane(state, pane_id).room_id))
		Engine.element(
			"section",
			[
				Html.aria_label_s(title),
				Engine.class_s(id.map2(tile.lift_row(), |pane_id, group| { pane_id, group }).map2(laid.lift_row(), |{ pane_id, group }, state| Str.join_with(["pane", if (pane_id != group.active or state.hidden.contains(pane_id)) "hidden" else "", if (pane_id == state.focused_pane) "focused" else ""].drop_if(Str.is_empty), " ")).map2(id.map2(drag.signal(), Liton.pane_drag_class), Liton.joined_classes)),
				# A tab of the workspace a Workbench shows has no header of its own.
				Engine.attr_presence("data-tab-view", id.map2(model.signal(), |pane_id, state| if (Model.workspace_view(state, pane_id)) Present("") else Absent)),
				# Clicking anywhere in it focuses it, or what was clicked in it.
				Engine.attr("tabindex", "-1"),
				Engine.on("focus", model.update_by(id.map2(tile.lift_row(), |pane_id, group| { pane: pane_id, tile: group.id }), Model.focus_pane)),
			],
			[
				Html.div_attrs(
					[Engine.class("pane-header"), Engine.attr("data-part", "header"), Engine.test_id_s(id.map(|pane_id| "header-${pane_id}"))],
					[
						Engine.when(place.map(|at| at == MainTab or at == MainTabWithSettings), || Liton.drawer_toggle(model, Left, Engine.const(Model.no_counts)), || Engine.text("")),
						# Dragging its header moves the pane, as its tab does.
						Engine.element(
							"div",
							[Engine.class("pane-grip"), Engine.test_id_s(id.map(|pane_id| "grip-${pane_id}"))].concat(Liton.grip(drag, id)),
							[
								Engine.switch(
									shown.map(|{ pane, state }| Liton.heading_of(state, pane)),
									[AgentHeading, RoomHeading, PaneHeading],
									|heading|
										match heading {
											AgentHeading => Liton.agent_header(shown.map(|{ pane, state }| Liton.agent_of(state, pane)))
											RoomHeading =>
												Html.div(
													"pane-heading",
													[
														Html.span_s(room.map(|opened| "#${opened.name}"), [Engine.class("pane-title room-title"), Engine.test_id("room-title")]),
														Html.span_s(room.map(|opened| opened.topic ?? ""), [Engine.class("pane-context room-topic")]),
													],
												)
											PaneHeading =>
												Html.div(
													"pane-heading",
													[
														Html.span_s(shown.map(|{ pane, state }| Liton.label(state, pane)), [Engine.class("pane-title")]),
														# A view that names its context itself leaves it out here.
														Html.span_s(shown.map(|{ pane, state }| if (!Widgets.find(pane.widget).follows.is_empty() and !["review", "ticket", "board", "room"].contains(pane.widget)) Model.context_title(state, pane) else ""), [Engine.class("pane-context")]),
													],
												)
										},
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
						Engine.when(shown.map(|{ pane, state }| Liton.heading_of(state, pane) == RoomHeading), || Liton.room_controls(model, id, room), || Engine.text("")),
						Engine.when(
							shown.map(|{ pane, state }| pane.widget == "thread" and !Model.room_pane(state, pane.id).root.is_empty()),
							|| Liton.icon_button(Engine.const("Close the thread"), "icon dismiss", model.update_by(id, |state, pane_id| Model.open_thread(state, { pane_id, root: "" }))),
							|| Engine.text(""),
						),
						Engine.when(place.map(|at| at == LeftTab or at == MainTabWithSettings), || Liton.settings_toggle(model, "icon settings-toggle"), || Engine.text("")),
						Liton.pane_menu(model, id, title, shown),
						Engine.when(place.map(|at| at == MainTab or at == MainTabWithSettings), || Liton.drawer_toggle(model, Right, shown.map(|{ pane, state }| Model.workspace_changes(state, pane))), || Engine.text("")),
					],
				),
				Engine.switch(
					shown.map(|{ pane, state }| Model.body(state, pane)),
					[Sessions, Workspaces, Chat, Inbox, Changes, Files, Review, ReviewFiles, ReviewThreads, Tickets, Ticket, Scopes, Board, Properties, Rooms, Room, Thread, Members, Capabilities, Connecting, Unconnected, Missing, MainDiff, NoView, Welcome, NoAgents],
					|body|
						match body {
							Sessions => Liton.tree(model, id, shown.map(|{ pane, state }| Model.session_rows(state, pane)), Menus)
							Workspaces => Html.div("workspaces-pane", [Liton.nav_rows(model, id, shown), Liton.create_form(model, id), Liton.tree(model, id, shown.map(|{ pane, state }| Model.workspace_rows(state, pane)), Menus)])
							Chat => Liton.chat(model, id, shown)
							Inbox => Liton.inbox(model, row.field(|pane| pane))
							Changes => Liton.changes(model, id, row.field(|pane| pane))
							Files => Liton.files_pane(model, id, row.field(|pane| pane))
							Review => Liton.review_view(model, id, row.field(|pane| pane))
							ReviewFiles => Liton.review_files(model, id, row.field(|pane| pane))
							ReviewThreads => Liton.review_threads(model, id, row.field(|pane| pane))
							Tickets => Liton.tickets(model, id)
							Ticket => Liton.ticket_view(model, id)
							Scopes => Liton.scopes(model)
							Board => Liton.board(model, id)
							Properties => Liton.properties(model, id)
							Rooms => Liton.rooms(model)
							Room => Liton.room_view(model, id)
							Thread => Liton.thread_view(model, id)
							Members => Liton.members_view(model, id)
							Capabilities => Liton.capabilities(model)
							MainDiff => Liton.main_diff(model, id)
							Connecting => Html.p("Connecting to the daemon…", "missing")
							Unconnected =>
								Liton.empty_state(
									Engine.const("Nothing is connected"),
									"liton's daemon connects no providers yet. Start it with PASEO_PASSWORD set to connect Paseo, or LITON_PROVIDERS for other providers, and what they offer appears here.",
									[Html.button("See the host's settings", [Engine.class("empty-action")], model.update(Model.show_host))],
								)
							NoView => Html.p("liton can't show this widget yet.", "missing")
							Welcome => Liton.welcome(model)
							NoAgents =>
								Liton.empty_state(
									shown.map(|{ state, .. }| "No agents in ${Model.workspace_header(state).title} yet"),
									"Start one to work in this workspace: it shows here as a tab.",
									[Html.button("Start an agent", [Engine.class("empty-action")], model.update(Model.new_agent_tab))],
								)
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

	## What a pane's header names: a chat's agent; a room shown, in place
	## of a header of its own; or the pane's title.
	heading_of : Model.State, Model.Pane -> [AgentHeading, RoomHeading, PaneHeading]
	heading_of = |state, pane|
		if (pane.widget == "chat" and !Model.session_of(state, pane).is_empty())
			AgentHeading
		else if (pane.widget == "room" and Model.body(state, pane) == Room and !Model.room_pane(state, pane.id).room_id.is_empty())
			RoomHeading
		else
			PaneHeading

	## What lets a tab or header drag pane `id`: its press, and the release
	## or cancel of a press that never moved, a click. The page reports the
	## rest of a drag (`Liton.drag_effects`).
	grip : State(ctx, Drag.Gesture), Signal(ctx, Str) -> List(Engine.Attr(ctx))
	grip = |drag, id| [
		Html.on_pointer_down_capture(drag.set_value_by(id, Drag.pressed)),
		Html.on_pointer_up(drag.set_value(Drag.released)),
		Html.on_pointer_cancel(drag.set_value(Drag.released)),
	]

	## How a tile shows a pane dragged into its tabs. The layout shown as if
	## dropped shows the rest.
	tile_drop_class : Str, Model.Drop -> Str
	tile_drop_class = |tile_id, drop|
		match drop {
			Into({ tile, .. }) if tile == tile_id => "drop-into"
			_ => ""
		}

	## How a tab or pane shows it is the one dragged.
	pane_drag_class : Str, Drag.Gesture -> Str
	pane_drag_class = |pane_id, gesture|
		match gesture {
			Dragging(held) if held.pane == pane_id => "dragged"
			_ => ""
		}

	joined_classes : Str, Str -> Str
	joined_classes = |first, second| Str.join_with([first, second].drop_if(Str.is_empty), " ")

	## A tile's classes: its slot's, `tabbed` while it shows more than one
	## pane, `shown` while a narrow screen shows it, `collapsed` while its
	## drawer is, and `workspace-tile` while it shows a workspace's tabs.
	tile_class : Model.State, Model.Tile -> Str
	tile_class = |state, tile| {
		slot = Model.slot_of(state, tile.id)
		classes = [
			if (slot == Free) "" else "slot slot-${Model.slot_name(slot)}",
			if (Model.shown_panes(state, tile).len() > 1) "tabbed" else "",
			if (tile.id == state.active_tile) "shown" else "",
			if (state.collapsed.contains(slot)) "collapsed" else "",
			if (Model.workspace_tile(state) == Ok(tile.id)) "workspace-tile" else "",
		]
		Str.join_with(classes.drop_if(|class| class.is_empty()).prepend("tile"), " ")
	}

	## A tile's tab on a narrow screen: its shown panes' titles, or while it
	## shows none, its active pane's.
	tile_tab_label : Model.Tile, Model.State -> Str
	tile_tab_label = |tile, state| {
		shown = Model.shown_panes(state, tile)
		if (shown.is_empty()) tile.panes.find_first(|pane| pane.id == tile.active).map_ok(|pane| Liton.label(state, pane)) ?? "" else Str.join_with(shown.map(|pane| Liton.label(state, pane)), " · ")
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
	icon_button : Signal(ctx, Str), Str, HandlerOf(ctx, Engine.Click) -> Elem(ctx)
	icon_button = |name, class, handler| Engine.element("button", [Engine.attr("type", "button"), Engine.class(class), Html.aria_label_s(name), Engine.attr_s("title", name), Engine.on_click(handler)], [])

	## What makes a list's row answer a click anywhere in it, not only on
	## its main control's text, with `activate`, that control's own handler.
	## A click reaches the nearest handler, so the row's other controls, such
	## as + and ⋮, keep theirs; the main control stays the row's one
	## focusable control, named for screen readers.
	row_activates : HandlerOf(ctx, Engine.Click) -> List(Engine.Attr(ctx))
	row_activates = |activate| [Engine.on_click(activate), Engine.attr("data-activates", "row")]

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
						opens = model.update_by(id, |state, session_id| Model.open(state, Session(session_id)))
						Html.li(
							[Engine.class_s(row.field(|item| item).map2(model.signal(), |item, state| Str.join_with(["inbox-item", if (Session(item.session_id) == Model.focused(state, [Session, Workspace])) "focused" else "", if (item.unread) "unread" else "", if (item.state == Working) "working" else ""].drop_if(Str.is_empty), " "))), Engine.attr("data-part", "item")].concat(Liton.row_activates(opens)),
							[
								Html.button_s(title, [], opens),
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
								opens = model.lift_row().update_by(row.key(), |shown, ticket_id| Model.open(shown, Ticket(ticket_id)))
								Html.li(
									[Engine.class_s(row.key().map2(state, |ticket_id, shown| if (Model.focused(shown, [Ticket]) == Ticket(ticket_id)) "ticket-row focused" else "ticket-row")), Engine.attr("data-part", "ticket")].concat(Liton.row_activates(opens)),
									[
										Engine.element(
											"button",
											[Engine.attr("type", "button"), Engine.class("ticket-title"), Html.aria_label_s(row.field(|ticket| "${ticket.key} ${ticket.title}")), Engine.on_click(opens)],
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
				Spinner.or_text(listed.map2(model.signal(), |shown, state| if (state.tickets.listing.sources.is_empty()) Loading else Said(if (shown.is_empty()) "No tickets match." else "")), Pane, [Engine.class("ticket-empty")]),
			],
		)
	}

	## A Ticket pane: the ticket it shows, or where to pick one.
	ticket_view : State(PaneCtx, Model.State), Signal(PaneCtx, Str) -> Elem(PaneCtx)
	ticket_view = |model, id| {
		ticket_id = id.map2(model.signal(), |pane_id, state| Model.ticket_of(state, pane_id))
		Engine.when(ticket_id.map(Str.is_empty), || Html.p("Pick a ticket in Tickets to show it here.", "missing"), || Liton.ticket_detail(model, id, ticket_id))
	}

	## A ticket shown: its key, a link to it where its source keeps it, its
	## title, status, assignees and labels, its fields and sessions
	## (`ticket_fields`, `ticket_sessions`), and its body and comments
	## (`ticket_discussion`).
	ticket_detail : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Str) -> Elem(PaneCtx)
	ticket_detail = |model, id, opened_ticket| {
		shown = opened_ticket.map2(model.signal(), |opened_id, state| TicketDesk.ticket_shown(state.tickets, opened_id) ?? TicketDesk.missing)
		summary = shown.map(|opened| opened.summary)
		Html.div_attrs(
			[Engine.class("ticket"), Engine.attr("data-part", "ticket")],
			[
				Liton.ticket_bar(model, summary),
				Engine.element("h3", [Engine.class("ticket-heading")], [Engine.text_s(summary.map(|listed| if (listed.id.is_empty()) "No such ticket" else listed.title))]),
				Html.div(
					"ticket-meta",
					[
						Html.span_s(summary.map(|listed| listed.status.name), [Engine.class_s(summary.map(|listed| Liton.kind_class(listed.status.kind))), Engine.test_id("ticket-status")]),
						Html.span_s(summary.map(|listed| Str.join_with(listed.assignees.map(|person| person.name), ", ")), [Engine.class("assignees")]),
						Html.span_s(summary.map(|listed| Str.join_with(listed.labels, " · ")), [Engine.class("labels")]),
					],
				),
				Liton.ticket_fields(model, summary),
				Liton.ticket_sessions(model, summary),
			].concat(Liton.ticket_discussion(model, id, opened_ticket)),
		)
	}

	## A ticket's key and a link to it where its source keeps it.
	ticket_bar : State(PaneCtx, Model.State), Signal(PaneCtx, Tickets.Summary) -> Elem(PaneCtx)
	ticket_bar = |model, summary|
		Html.div(
			"ticket-bar",
			[
				Html.span_s(summary.map(|listed| listed.key), [Engine.class("ticket-key")]),
				Engine.element("a", [Engine.attr_s("href", summary.map(|listed| listed.url)), Engine.attr("target", "_blank"), Engine.attr("rel", "noopener noreferrer"), Engine.class("ticket-link")], [Engine.text_s(summary.map2(model.signal(), |listed, state| "Open in ${TicketDesk.source_name(state.tickets, listed.source)}"))]),
			],
		)

	## A ticket's status and its assignees, of its source's people, each
	## changed at once, saving until the daemon has it, each a row of its
	## name and its value.
	ticket_fields : State(PaneCtx, Model.State), Signal(PaneCtx, Tickets.Summary) -> Elem(PaneCtx)
	ticket_fields = |model, summary|
		Html.div_attrs(
			[Engine.class("ticket-fields"), Engine.attr("data-part", "fields")],
			[
				Html.div(
					"ticket-field",
					[
						Html.span_s(Engine.const("Status"), [Engine.class("field-name"), Engine.attr("aria-hidden", "true")]),
						Dropdown.select(Engine.const("Set status"), summary.map(|listed| listed.status.id), [], Liton.choices(summary.map2(model.signal(), |listed, state| (state.tickets.listing.sources.find_first(|source| source.id == listed.source).map_ok(|source| source.statuses) ?? []).map(|status| { value: status.id, label: status.name }))), model.set_value_by(summary.map(|listed| listed.id), |state, ticket_id, status_id| Model.ask_tickets(state, SetStatus({ ticket_id, status_id })))),
						Html.span_s(summary.map2(model.signal(), |listed, state| if (TicketDesk.pending(state.tickets, listed.id)) "Saving…" else ""), [Engine.class("ticket-saving"), Engine.test_id("ticket-saving")]),
					],
				),
				Engine.element(
					"fieldset",
					[Engine.class("ticket-field ticket-people")],
					[
						Engine.element("legend", [Engine.class("field-name")], [Engine.text("Assignees")]),
						Engine.each(
							summary.map2(model.signal(), |listed, state| (state.tickets.listing.sources.find_first(|source| source.id == listed.source).map_ok(|source| source.people) ?? []).map(|person| { ticket_id: listed.id, person, assigned: listed.assignees.contains(person) })),
							|choice| choice.person.id,
							|row| Engine.element("label", [], [Html.checkbox(row.field(|choice| choice.person.name), row.field(|choice| choice.assigned), [], model.lift_row().set_value_by(row.field(|choice| { ticket_id: choice.ticket_id, person_id: choice.person.id }), Model.assign)), Engine.text_s(row.field(|choice| choice.person.name))]),
						),
					],
				),
			],
		)

	## The sessions working on a ticket, each with its status, to open in a
	## chat or unlink, and to link the session focused.
	ticket_sessions : State(PaneCtx, Model.State), Signal(PaneCtx, Tickets.Summary) -> Elem(PaneCtx)
	ticket_sessions = |model, summary|
		Html.div_attrs(
			[Engine.class("ticket-sessions"), Engine.attr("data-part", "sessions")],
			[
				Engine.each(
					summary.map2(model.signal(), |listed, state| TicketDesk.links_shown(state.tickets).keep_if(|link| link.ticket_id == listed.id)),
					|link| link.session_id,
					|row| {
						session = row.key().map2(model.signal().lift_row(), |session_id, state| Model.session(state, session_id))
						title = session.map(|shown| shown.title)
						Html.div(
							"ticket-session",
							[
								Html.span_s(Engine.const(""), [Engine.class_s(session.map(|shown| "status-dot ${Liton.status_dot(shown.status)}")), Engine.attr("aria-hidden", "true")]),
								Html.button_s(title, [Engine.class("session-title"), Html.aria_label_s(title.map(|name| "Open ${name}"))], model.lift_row().update_by(row.key(), |state, session_id| Model.open(state, Session(session_id)))),
								Html.span_s(session.map(|shown| Liton.status_text(shown.status)), [Engine.class("status-word")]),
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
		)

	## A ticket's body and comments as Markdown, once loaded, and a comment
	## to add, shown at once, saving until the daemon has it.
	ticket_discussion : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Str) -> List(Elem(PaneCtx))
	ticket_discussion = |model, id, opened_ticket| {
		shown = opened_ticket.map2(model.signal(), |opened_id, state| TicketDesk.ticket_shown(state.tickets, opened_id) ?? TicketDesk.missing)
		[
			Spinner.or_text(opened_ticket.map2(model.signal(), |opened_id, state| if (TicketDesk.loaded(state.tickets, opened_id)) Said("") else Loading), Pane, [Engine.class("ticket-empty")]),
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
		]
	}

	## A Scopes pane: every ticket, yours, those assigned to nobody and each
	## source's, each with how many tickets it has, the one Board panes show
	## marked.
	scopes : State(PaneCtx, Model.State) -> Elem(PaneCtx)
	scopes = |model|
		Html.ul(
			[Engine.class("scopes"), Engine.attr("data-part", "scope")],
			[
				Engine.each(
					model.signal().map(|state| TicketDesk.scopes(state.tickets)),
					|listed| listed.key,
					|row|
						Html.li(
							[],
							[
								Engine.element(
									"button",
									[Engine.attr("type", "button"), Engine.class("scope"), Html.aria_label_s(row.field(|listed| listed.name)), Html.flag("aria-pressed", row.field(|listed| listed.scope).map2(model.signal().lift_row(), |scope, state| state.tickets.scope == scope)), Engine.on_click(model.lift_row().update_by(row.field(|listed| listed.scope), Model.pick_scope))],
									[Html.span_s(row.field(|listed| listed.name), [Engine.class("scope-name")]), Html.span_s(row.field(|listed| listed.count.to_str()), [Engine.class("count")])],
								),
								Engine.when(
									row.key().map(|key| key.starts_with("view:")),
									|| Html.button("×", [Engine.class("forget"), Html.aria_label_s(row.field(|listed| "Forget ${listed.name}"))], model.lift_row().update_by(row.field(|listed| listed.name), Model.forget_view)),
									|| Engine.text(""),
								),
							],
						),
				),
			],
		)

	## A Board pane: the ticket it opened, else its list.
	board : State(PaneCtx, Model.State), Signal(PaneCtx, Str) -> Elem(PaneCtx)
	board = |model, id| Engine.when(id.map2(model.signal(), |pane_id, state| TicketDesk.board(state.tickets, pane_id).opened), || Liton.board_ticket_opened(model, id), || Liton.board_list(model, id))

	## A ticket a Board opened: the way back to the list, its key, where it
	## is in the list, as "2 / 5", with the tickets before and after it a
	## click away, its title, and its body and comments.
	board_ticket_opened : State(PaneCtx, Model.State), Signal(PaneCtx, Str) -> Elem(PaneCtx)
	board_ticket_opened = |model, id| {
		ticket_id = model.signal().map(Model.ticket_under_cursor)
		summary = ticket_id.map2(model.signal(), |shown_id, state| (TicketDesk.ticket_shown(state.tickets, shown_id) ?? TicketDesk.missing).summary)
		Html.div(
			"board ticket",
			[
				Html.div(
					"board-bar",
					[
						Html.button("← List", [Html.aria_label("Back to the list")], model.update_by(id, Model.back_to_list)),
						Html.span_s(summary.map(|listed| listed.key), [Engine.class("ticket-key")]),
						Html.span_s(id.map2(model.signal(), |pane_id, state| Model.ticket_place(state, pane_id)), [Engine.class("ticket-place"), Engine.test_id("ticket-place")]),
						Html.button("↑", [Html.aria_label("Previous ticket"), Engine.class("step")], model.update(|state| Model.step_ticket(state, Previous))),
						Html.button("↓", [Html.aria_label("Next ticket"), Engine.class("step")], model.update(|state| Model.step_ticket(state, Next))),
					],
				),
				Engine.element("h3", [Engine.class("ticket-heading")], [Engine.text_s(summary.map(|listed| if (listed.id.is_empty()) "No such ticket" else listed.title))]),
			].concat(Liton.ticket_discussion(model, id, ticket_id)),
		)
	}

	## A Board pane's list: the tickets of the scope picked, those its search
	## matches, in groups by the kind of their status, or on a board in
	## columns by status, each with how many it has (`TicketDesk.groups`).
	board_list : State(PaneCtx, Model.State), Signal(PaneCtx, Str) -> Elem(PaneCtx)
	board_list = |model, id| {
		layout = id.map2(model.signal(), |pane_id, state| Model.board_layout(state, pane_id))
		groups = id.map2(model.signal(), |pane_id, state| TicketDesk.groups(state.tickets, pane_id, Model.board_layout(state, pane_id)))
		laid_out = |name, value| Html.button(name, [Engine.class("layout"), Html.aria_label("Show as a ${name.with_ascii_lowercased()}"), Html.flag("aria-pressed", layout.map(|shown| shown == value))], model.update_by(id, |state, pane_id| Model.set_option(state, pane_id, "layout", name)))
		Engine.element(
			"div",
			[Engine.class_s(layout.map(|shown| if (shown == Board) "board columns" else "board"))],
			[
				Html.div(
					"board-bar",
					[
						Html.span_s(model.signal().map(|state| TicketDesk.scope_name(state.tickets, state.tickets.scope)), [Engine.class("board-scope")]),
						Html.text_input(Engine.const("Search tickets"), "search", id.map2(model.signal(), |pane_id, state| TicketDesk.board(state.tickets, pane_id).filter.text), [Engine.attr("placeholder", "Search"), Engine.ref_s(id.map(|pane_id| "search-${pane_id}"))], model.set_value_by(id, |state, pane_id, text| Model.filter_board(state, pane_id, |filter| { ..filter, text }))),
						Html.span_s(id.map2(model.signal(), |pane_id, state| TicketDesk.board(state.tickets, pane_id).selected.len()).map(|count| if (count == 0) "" else "${count.to_str()} selected"), [Engine.class("selected-count"), Engine.test_id("selected-count")]),
						Html.span_s(id.map2(model.signal(), |pane_id, state| TicketDesk.described(state.tickets, { ..TicketDesk.board(state.tickets, pane_id).filter, text: "" })), [Engine.class("board-filter"), Engine.test_id("board-filter")]),
						Engine.when(
							id.map2(model.signal(), |pane_id, state| TicketDesk.board(state.tickets, pane_id).filter != TicketDesk.everything),
							|| Html.div("board-filter-actions", [Html.button("Save view", [], model.update_by(id, Model.save_view)), Html.button("×", [Html.aria_label("Clear the filter")], model.update_by(id, |state, pane_id| Model.filter_board(state, pane_id, |_| TicketDesk.everything)))]),
							|| Engine.text(""),
						),
						laid_out("List", List),
						laid_out("Board", Board),
					],
				),
				# A card held moves over the groups, each a pointer zone once it
				# moves (so a click is in no zone), and
				# dropped on another takes its status (`Model.drop_card`).
				Html.div_attrs(
					[
						Engine.class("board-groups"),
						Html.on_pointer_move_paced(model.set_value(|state, pointer| if (pointer.buttons == 0) Model.drag_card(state, Let) else Model.drag_card(state, Over(Liton.zone_under(pointer))))),
						Html.on_pointer_up(model.set_value_by(id, |state, pane_id, _| Model.drop_card(state, pane_id))),
						Html.on_pointer_cancel(model.update(|state| Model.drag_card(state, Let))),
					],
					[
						Engine.each(
							groups,
							|group| group.key,
							|group_row|
								Engine.element(
									"section",
									[Engine.class_s(group_row.key().map2(model.signal().lift_row(), |key, state| if (state.tickets.dragged.over == key and !state.tickets.dragged.ticket.is_empty()) "board-group drop-over" else "board-group")), Engine.attr("data-part", "group"), Html.aria_label_s(group_row.field(|group| group.title)), Html.zone_s(group_row.key().map2(model.signal().lift_row(), |key, state| if (state.tickets.dragged.moved) key else ""))],
									[
										Html.div("board-group-header", [Html.span_s(group_row.field(|group| group.title), [Engine.class("group-title")]), Html.span_s(group_row.field(|group| group.tickets.len().to_str()), [Engine.class("count"), Engine.test_id_s(group_row.key().map(|key| "group-${key}"))])]),
										Html.ul([Engine.class("board-rows")], [Engine.each(group_row.field(|group| group.tickets), |ticket| ticket.id, |row| Liton.board_ticket(model.lift_row(), id.lift_row(), row))]),
									],
								),
						),
					],
				),
				Spinner.or_text(groups.map2(model.signal(), |shown, state| if (state.tickets.listing.sources.is_empty()) Loading else Said(if (shown.all(|group| group.tickets.is_empty())) "No tickets match." else "")), Pane, [Engine.class("ticket-empty")]),
			],
		)
	}

	## A ticket of a Board: its key and title, which open it, its labels,
	## the session working on it with its status, and its assignees, marked
	## while under the cursor.
	board_ticket : State(ctx, Model.State), Signal(ctx, Str), RowRef(ctx, Tickets.Summary) -> Elem(Row(ctx, Tickets.Summary))
	board_ticket = |model, id, row| {
		state = model.signal().lift_row()
		session = row.key().map2(state, |ticket_id, shown| Liton.ticket_session(shown, ticket_id))
		opens = model.lift_row().update_by(row.key().map2(id.lift_row(), |ticket_id, pane_id| { pane_id, ticket_id }), Model.open_in_board)
		Html.li(
			[Engine.class_s(row.key().map2(id.lift_row(), |ticket_id, pane_id| { ticket_id, pane_id }).map2(state, |{ ticket_id, pane_id }, shown| Str.join_with(["board-ticket", if (Model.focused(shown, [Ticket]) == Ticket(ticket_id)) "focused" else "", if (TicketDesk.board(shown.tickets, pane_id).selected.contains(ticket_id)) "selected" else ""].drop_if(Str.is_empty), " "))), Engine.attr("data-part", "ticket"), Engine.test_id_s(row.key().map(|ticket_id| "ticket-${ticket_id}")), Html.on_pointer_down(model.lift_row().set_value_by(row.key(), |shown, ticket_id, pointer| if (pointer.button == Main and pointer.kind != Touch) Model.drag_card(shown, Hold(ticket_id)) else shown))].concat(Liton.row_activates(opens)),
			[
				Engine.element(
					"button",
					[Engine.attr("type", "button"), Engine.class("ticket-title"), Html.aria_label_s(row.field(|ticket| "${ticket.key} ${ticket.title}")), Engine.on_click(opens)],
					[Html.span_s(row.field(|ticket| ticket.key), [Engine.class("ticket-key")]), Engine.text_s(row.field(|ticket| ticket.title))],
				),
				Html.span_s(row.field(|ticket| Str.join_with(ticket.labels, " · ")), [Engine.class("labels")]),
				Html.span_s(Engine.const(""), [Engine.class_s(session.map(|linked| if (linked.title.is_empty()) "" else "status-dot ${linked.dot}")), Engine.attr("aria-hidden", "true")]),
				Html.span_s(session.map(|linked| linked.title), [Engine.class("session"), Engine.attr_s("title", session.map(|linked| linked.status))]),
				Html.span_s(row.field(|ticket| Str.join_with(ticket.assignees.map(|person| person.name), ", ")), [Engine.class("assignees")]),
			],
		)
	}

	## The pointer zone under a pointer, "" for none.
	zone_under : Engine.Pointer -> Str
	zone_under = |pointer|
		match pointer.at {
			In({ zone, .. }) => zone
			Outside => ""
		}

	## The first session working on a ticket: its title, status and dot, ""
	## for none.
	ticket_session : Model.State, Str -> { title : Str, status : Str, dot : Str }
	ticket_session = |state, ticket_id|
		match TicketDesk.links_shown(state.tickets).find_first(|link| link.ticket_id == ticket_id) {
			Ok(link) => {
				session = Model.session(state, link.session_id)
				{ title: session.title, status: Liton.status_text(session.status), dot: Liton.status_dot(session.status) }
			}
			Err(_) => { title: "", status: "", dot: "" }
		}

	## A session's status as its dot shows it.
	status_dot : Chat.Status -> Str
	status_dot = |status|
		match status {
			Running => "running"
			AwaitingPermission => "waiting"
			Failed(_) => "failed"
			Finished => "done"
			Idle => "idle"
		}

	## A Properties pane: the key, title, status, assignees and labels of the
	## ticket under the cursor, a link to where its source keeps it, and the
	## sessions working on it.
	properties : State(PaneCtx, Model.State), Signal(PaneCtx, Str) -> Elem(PaneCtx)
	properties = |model, id| {
		ticket_id = id.map2(model.signal(), |pane_id, state| Model.ticket_of(state, pane_id))
		summary = ticket_id.map2(model.signal(), |shown_id, state| (TicketDesk.ticket_shown(state.tickets, shown_id) ?? TicketDesk.missing).summary)
		Engine.when(
			ticket_id.map(Str.is_empty),
			|| Html.p("Pick a ticket to see its properties.", "missing"),
			||
				Html.div(
					"ticket properties",
					[
						Liton.ticket_bar(model, summary),
						Html.p_s(summary.map(|listed| listed.title), [Engine.class("properties-title")]),
						Liton.ticket_fields(model, summary),
						Html.div("ticket-field ticket-labels", [Html.span_s(Engine.const("Labels"), [Engine.class("field-name")]), Html.span_s(summary.map(|listed| if (listed.labels.is_empty()) "None" else Str.join_with(listed.labels, " · ")), [Engine.class("labels")])]),
						Liton.ticket_sessions(model, summary),
					],
				),
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
						picks = model.update_by(asked, Model.pick_row)
						Html.li(
							[
								Engine.class_s(row.field(|shown| shown).map2(kind, |shown, name| "tree-row tree-${name}${if (shown.focused) " focused" else ""}${if (shown.folded) " folded" else ""}${if (shown.creatable) " creatable" else ""}${if (shown.pinned) " pinned" else ""}${if (menus == Menus and Liton.has_menu(shown)) " has-menu" else ""}")),
								Engine.attr_s("data-part", kind),
								Engine.attr_s("style", row.field(|shown| "--depth: ${shown.depth.to_str()}")),
							].concat(Liton.row_activates(picks)).concat(if (menus == Menus) [Engine.on_with("contextmenu", { prevent: Bool.True }, model.update_by(asked, |state, at| if (Model.row_menu(state, at.key).is_empty()) state else { ..state, menu: Model.row_menu_key(at) }))] else []),
							[
								Html.span_s(Engine.const(""), [Engine.class_s(row.field(|shown| "status-dot ${shown.dot}")), Engine.attr("aria-hidden", "true"), Engine.attr_s("title", row.field(|shown| shown.status))]),
								if (menus == Menus) Liton.row_title(model, asked, row.field(|shown| shown.title)) else Html.button_s(row.field(|shown| shown.title), [Engine.class("row-title")], picks),
								Html.span_s(row.field(|shown| shown.detail), [Engine.class("branch")]),
								Html.span_s(row.field(|shown| shown.counts.members), [Engine.class("counts")]),
								Html.span_s(row.field(|shown| shown.counts.added), [Engine.class("added")]),
								Html.span_s(row.field(|shown| shown.counts.removed), [Engine.class("removed")]),
								Html.span_s(row.field(|shown| shown.status), [Engine.class_s(row.field(|shown| "status-word ${shown.dot}")), Engine.test_id("row-status")]),
								Html.span_s(row.field(|shown| shown.age), [Engine.class("age"), Engine.test_id("row-age")]),
								Html.span_s(row.field(|shown| shown.second_line), [Engine.class("second-line")]),
								Liton.icon_button(row.field(|shown| if (shown.kind == Group) "New workspace in ${shown.title}" else if (shown.kind == Session) "New agent beside ${shown.title}" else "New agent in ${shown.title}"), "icon new-agent", model.update_by(asked, Model.open_form)),
							].concat(if (menus == Menus) [Liton.row_menu(model, asked, row.field(|shown| shown.title))] else []),
						)
					},
				),
			],
		)

	## What the main area says while no workspace is picked: on a first run,
	## that projects come from the daemon's providers, with what is connected
	## a click away; else to pick a workspace or create one.
	welcome : State(PaneCtx, Model.State) -> Elem(PaneCtx)
	welcome = |model|
		Engine.when(
			model.signal().map(|state| state.workspaces.projects.is_empty()),
			||
				Liton.empty_state(
					Engine.const("No projects yet"),
					"liton shows the projects of the providers its daemon connects. Start the daemon with PASEO_PASSWORD set to connect Paseo, or LITON_PROVIDERS for other providers, and their projects and workspaces appear here.",
					[Html.button("See what's connected", [Engine.class("empty-action")], model.update(|state| Model.add_pane(state, "capabilities")))],
				),
			||
				Liton.empty_state(
					Engine.const("Pick a workspace"),
					"Its agents show here as tabs, its changes and files beside them.",
					[Html.button("Create a workspace", [Engine.class("empty-action")], model.update(Model.new_workspace))],
				),
		)

	## An empty state: what is missing, why, and the actions that fill it.
	empty_state : Signal(ctx, Str), Str, List(Elem(ctx)) -> Elem(ctx)
	empty_state = |title, text, actions|
		Html.div_attrs(
			[Engine.class("empty-state"), Engine.test_id("empty-state")],
			[
				Html.p_s(title, [Engine.class("empty-title")]),
				Html.p(text, "empty-text"),
				Html.div("empty-actions", actions),
			],
		)

	## A Workspaces pane's rows over its list where it lists sessions as
	## tabs, as Paseo's navigator has them: New workspace, and Search, which
	## opens the palette. Paseo's History and Schedules wait on a history of
	## the focus and an automations capability.
	nav_rows : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, { pane : Model.Pane, state : Model.State }) -> Elem(PaneCtx)
	nav_rows = |model, id, shown|
		Engine.when(
			shown.map(|{ pane, .. }| Model.option(pane, "sessions") == "Tabs"),
			||
				Html.div(
					"nav-rows",
					[
						Html.button("New workspace", [Engine.class("nav-row nav-new-workspace"), Engine.test_id("nav-new-workspace")], model.update_by(id, |state, pane_id| Model.open_form(state, { pane_id, key: "" }))),
						Html.button_s(model.signal().map(|state| "Search ${Keymap.text_of(state.operating_system, Keymap.defaults, "palette")}"), [Engine.class("nav-row nav-search"), Html.aria_label_s(Engine.const("Search"))], model.update(Commands.open_palette)),
					],
				),
			|| Engine.text(""),
		)

	## A row's title, which picks it, or while it is being renamed, a field
	## of its name, which Enter saves and Escape leaves.
	row_title : State(ctx, Model.State), Signal(ctx, { pane_id : Str, key : Str }), Signal(ctx, Str) -> Elem(ctx)
	row_title = |model, asked, title|
		Engine.when(
			asked.map2(model.signal(), |at, state| state.renaming.pane == at.pane_id and state.renaming.key == at.key),
			|| Html.form("Rename", [Engine.class("rename-form"), Engine.on("submit", model.update(Model.rename_row)), Engine.on_click(model.update(|state| state))], [Html.text_input(Engine.const("New name"), "text", model.signal().map(|state| state.renaming.text), [Engine.ref("rename"), Engine.class("rename")], model.set_value(|state, text| { ..state, renaming: { ..state.renaming, text } }))]),
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
	## workspace, of a kind its provider offers, with a model, a mode and a
	## thinking level, picked of those it offers, and a first prompt; or a workspace to create of a project, a worktree on a new
	## branch or a checkout. Either shows starting at once. Both are one
	## form, whose class shows the fields of the one open, to keep the
	## module small.
	create_form : State(PaneCtx, Model.State), Signal(PaneCtx, Str) -> Elem(PaneCtx)
	create_form = |model, id| {
		form = id.map2(model.signal(), |pane_id, state| if (state.form.pane == pane_id) state.form else Model.closed_form)
		set = |change| model.set_value(|state, text| { ..state, form: change(state.form, text) })
		field = |name, part, placeholder, value, change| Html.text_input(Engine.const(name), "text", form.map(value), [Engine.attr("placeholder", placeholder), Engine.class(part)], set(change))
		# What the agent picked offers: a drop-down of each, its first
		# option its default, while it offers any.
		offered = form.map2(model.signal(), |shown, state| Model.form_choices(state, shown))
		default_option = |said| Engine.element("option", [Engine.prop(Engine.Prop.value, "")], [Engine.text_s(said)])
		picker = |name, value, listed, default_label, change|
			Engine.when(
				offered.map(|offers| !listed(offers).is_empty()),
				|| Dropdown.select(Engine.const(name), form.map(value), [Engine.class("agent-field")], [default_option(offered.map(default_label))].concat(Liton.choices(offered.map(listed))), set(change)),
				|| Engine.text(""),
			)
		Engine.when(
			form.map(|shown| shown.kind != Closed),
			||
				Html.form(
					"New agent or workspace",
					[Engine.class_s(form.map(|shown| if (shown.kind == Agent) "create-form for-agent" else "create-form for-workspace")), Engine.on("submit", model.update(Model.submit_form))],
					[
						Html.p_s(form.map2(model.signal(), |shown, state| if (shown.kind == Agent) "New agent in ${state.workspaces.workspaces.find_first(|listed| listed.id == shown.place).map_ok(|listed| listed.name) ?? shown.place}" else "New workspace"), [Engine.class("create-title")]),
						Dropdown.select(Engine.const("Agent"), form.map(|shown| shown.agent), [Engine.class("agent-field")], Liton.choices(form.map2(model.signal(), |shown, state| Model.agent_kinds(state, shown.place).map(|agent| { value: agent, label: agent }))), set(Model.pick_agent)),
						Engine.when(
							offered.map(|offers| offers.models.is_empty()),
							|| field("Model", "agent-field", "Model (optional)", |shown| shown.model, |shown, text| { ..shown, model: text }),
							|| Dropdown.select(Engine.const("Model"), form.map(|shown| shown.model), [Engine.class("agent-field")], [default_option(offered.map(|offers| offers.defaults.model))].concat(Liton.choices(offered.map(|offers| offers.models))), model.set_value(|state, text| { ..state, form: Model.pick_model(state, state.form, text) })),
						),
						picker("Mode", |shown| shown.mode, |offers| offers.modes, |offers| offers.defaults.mode, |shown, text| { ..shown, mode: text }),
						picker("Thinking", |shown| shown.thinking, |offers| offers.levels, |offers| offers.defaults.thinking, |shown, text| { ..shown, thinking: text }),
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
			Conversation.timeline(
				model0,
				id,
				{ class: "timeline", part: "timeline", jump: "Jump to latest", earlier: shown.map(|{ pane, state }| Model.has_earlier(state, pane)), loading: shown.map(|{ pane, state }| Model.loading(state, Model.session_of(state, pane))) },
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
									Conversation.sent_state({ status: row.field(|sent| Liton.sent_status(sent)), failed: row.field(|sent| !sent.failed.is_empty()), test_id: "sent-status" }, [{ label: "Retry", handler: model0.lift_row().update_by(row.key(), Model.retry) }]),
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
			).concat([
				Engine.when(
					pending.map(|waiting| waiting.is_ok()),
					|| Liton.permission_card(model0, id.map(|pane_id| "${pane_id}/permission"), pending.map(|waiting| waiting ?? Liton.no_permission), Engine.const("")),
					|| Engine.text(""),
				),
				Conversation.composer(
					model0,
					id,
					{ form: "Send a message", name: "Message", placeholder: Engine.const("Message the agent"), send: Microphone.send, completions: |_, _| [], shift_tab: Runs(Model.cycle_mode) },
					[
						Html.div(
							"composer-chips",
							[
								Liton.setting_chip(model0, id, Mode, "Mode", Html.span_s(Engine.const(""), [Engine.class("model-chip")])),
								Liton.setting_chip(model0, id, Model, "Model", Html.span_s(chip.map(|named| named.name), [Engine.class("model-chip"), Engine.attr_s("title", chip.map(|named| named.title)), Engine.test_id("model-chip")])),
								Liton.setting_chip(model0, id, Thinking, "Thinking", Html.span_s(Engine.const(""), [Engine.class("model-chip")])),
							],
						),
						Liton.context_meter(model0, id),
						Microphone.controls(model0, id),
						# One round button: Send, or Stop while the agent works and
						# nothing is typed, then a ring until it stops.
						Engine.switch(
							shown.map(|{ pane, state }| Liton.composer_action(state, pane)),
							[Send, Stop, Stopping],
							|action|
								match action {
									Send => Conversation.send_button("Send")
									Stop => Html.icon_button("", Engine.const("Stop"), "send stop", model0.update_by(id, Model.stop))
									Stopping => Html.span_s(Engine.const("Stopping…"), [Engine.class("send stopping"), Engine.attr("role", "status"), Engine.test_id("stop-status")])
								},
						),
					],
				),
			]),
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

	## A drop-down in a chat pane's composer, named `name`, that switches the
	## setting `which` of the session the pane shows (`Model.setting`),
	## pending until it is switched; `otherwise` while it offers no choices.
	setting_chip : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Model.Setting, Str, Elem(PaneCtx) -> Elem(PaneCtx)
	setting_chip = |model, id, which, name, otherwise| {
		session_id = id.map2(model.signal(), |pane_id, state| Model.session_of(state, Model.pane(state, pane_id)))
		shown = session_id.map2(model.signal(), |session, state| { setting: Model.setting(state, session, which), pending: Model.configuring(state, session, which) })
		Engine.when(
			shown.map(|chip| !chip.setting.choices.is_empty()),
			|| Dropdown.select(Engine.const(name), shown.map(|chip| chip.setting.value), [Engine.class_s(shown.map(|chip| if (chip.pending) "chip pending" else "chip")), Engine.attr_s("title", shown.map(|chip| if (chip.pending) "${name}: switching to ${chip.setting.label}…" else "${name}: ${chip.setting.label}"))], Liton.choices(shown.map(|chip| chip.setting.choices)), model.set_value_by(session_id, |state, session, value| Model.configure(state, session, which, value))),
			|| otherwise,
		)
	}

	## A ring in a chat pane's composer of how much of its session's context
	## window the last turn filled, while its provider tells what it used,
	## that opens a list of the tokens it read and wrote and what it cost.
	context_meter : State(PaneCtx, Model.State), Signal(PaneCtx, Str) -> Elem(PaneCtx)
	context_meter = |model, id| {
		key = id.map(|pane_id| "${pane_id} context")
		used = id.map2(model.signal(), |pane_id, state| Model.usage_shown(state, Model.session_of(state, Model.pane(state, pane_id))))
		shown = used.map(|told| told ?? { percent: 0, context: "", input: "", cached: "", output: "", cost: "" })
		open = key.map2(model.signal(), |menu_key, state| state.menu == menu_key)
		row = |named, value| Html.div_s(value.map(|said| if (said.is_empty()) "usage-row hidden" else "usage-row"), [Html.span_s(Engine.const(named), []), Html.span_s(value, [])])
		Engine.when(
			used.map(|told| told.is_ok()),
			||
				Html.div(
					"context-meter",
					[
						Engine.element(
							"button",
							[
								Engine.attr("type", "button"),
								Engine.class("context-ring"),
								Engine.attr_s("style", shown.map(|told| "--used: ${told.percent.to_str()}")),
								Html.aria_label_s(shown.map(|told| "Context: ${told.percent.to_str()}% used")),
								Engine.attr_s("title", shown.map(|told| if (told.context.is_empty()) "What the last turn used" else "Context: ${told.context}")),
								Engine.attr("aria-haspopup", "true"),
								Html.flag("aria-expanded", open),
								Engine.on_click(model.update_by(key, Model.toggle_menu)),
							],
							[],
						),
						Engine.when(
							open,
							||
								Engine.element(
									"div",
									[Engine.class("menu usage"), Engine.test_id("context-usage")],
									[
										Html.p_s(Engine.const("Last turn"), [Engine.class("usage-title")]),
										row("Context", shown.map(|told| told.context)),
										row("Input", shown.map(|told| told.input)),
										row("Cached input", shown.map(|told| told.cached)),
										row("Output", shown.map(|told| told.output)),
										row("Cost", shown.map(|told| told.cost)),
									],
								),
							|| Engine.text(""),
						),
					],
				),
			|| Engine.text(""),
		)
	}

	## The composer's chip: the model a session runs, or its agent when the
	## provider doesn't tell the model, and nothing without a session.
	model_chip : Chat.Session -> { name : Str, title : Str }
	model_chip = |session|
		match session.model {
			Ok(model) => { name: model.drop_prefix("${session.agent}-"), title: "${session.agent}, running ${model}" }
			Err(Missing) => { name: session.agent, title: if (session.agent.is_empty()) "" else "${session.agent}: its provider doesn't say which model it runs" }
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
							Loading => Spinner.spinner("Loading", Pane)
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
										Engine.when(files.map(|listed| listed == Loading), || Spinner.spinner("Loading", Pane), || Html.p_s(files.map2(scope, Liton.no_files_text), [Engine.class("missing")])),
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

	## How many files a scope changes, as "3 files".
	file_count : [Files(List(WorkspaceGit.File)), Loading] -> Str
	file_count = |listed|
		match listed {
			Files([_]) => "1 file"
			Files(files) => "${files.len().to_str()} files"
			Loading => ""
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

	## The Review surface's view (docs/research/surfaces.md, Review): every
	## file of the scope its parts show as a card, its diff with the review's
	## threads at their lines and the composer under the lines picked. Polls
	## follow them only while it is on screen (see `Model.subjects`).
	review_view : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Model.Pane) -> Elem(PaneCtx)
	review_view = |model, id, pane| {
		shown = pane.map2(model.signal(), |pane_shown, state| { pane: pane_shown, state })
		cards = shown.map(|{ pane: pane_shown, state }| Model.review_cards(state, pane_shown))
		Html.div(
			"review",
			[
				Engine.switch(
					shown.map(|{ pane: pane_shown, state }| Model.git_shown(state, pane_shown)),
					[NoSession, Loading, Unreadable, NotGit, Shown],
					|showing|
						match showing {
							NoSession => Html.p("Pick a session to review its changes.", "missing")
							Loading => Spinner.spinner("Loading", Pane)
							Unreadable => Html.p("Can't read this workspace right now.", "missing")
							NotGit => Html.p("Not a git workspace.", "missing")
							Shown =>
								Html.div(
									"review-cards",
									[
										Liton.review_bar(model, pane),
										Html.p_s(shown.map(|{ pane: pane_shown, state }| Model.since_round_text(state, pane_shown)), [Engine.class("since-round-note"), Engine.test_id("since-round-note")]),
										Spinner.or_text(cards.map(|listed| if (listed == Loading) Loading else Said(if (listed == Cards([])) "No changes to review." else "")), Pane, [Engine.class("missing")]),
										Engine.each(
											cards.map(
												|listed|
													match listed {
														Cards(found) => found
														Loading => []
													},
											),
											|card| card.path,
											|card| Liton.review_card(model, id, pane, card),
										),
									],
								)
						},
				),
			],
		)
	}

	## The Review view's bar: the branch, how many files are marked viewed,
	## how many comments its threads have, with the previous and next thread,
	## the round and Finish review, which sends the drafts to the agent as
	## the next round, once one is sent, Since round, which shows only the
	## files changed since, and the scope its parts show,
	## uncommitted or against the base, or one of the branch's commits;
	## another shows its files at once.
	review_bar : State(PaneCtx, Model.State), Signal(PaneCtx, Model.Pane) -> Elem(PaneCtx)
	review_bar = |model, pane| {
		git = pane.map2(model.signal(), |shown, state| Model.git_of(state, shown))
		commit = |row| Engine.element("option", [Engine.prop_s(Engine.Prop.value, row.key().map(|sha| "commit:${sha}"))], [Engine.text_s(row.field(|listed| "${listed.short_sha} ${listed.subject}"))])
		Html.div_attrs(
			[Engine.class("review-bar"), Engine.attr("data-part", "header")],
			[
				Html.span_s(git.map(|known| Liton.branch_text(known.status)), [Engine.class("branch")]),
				Html.span_s(pane.map2(model.signal(), |shown, state| Model.viewed_count(state, shown)), [Engine.class("viewed-count"), Engine.test_id("viewed-count")]),
				Html.div(
					"comment-steps",
					[
						Html.button("‹", [Html.aria_label("Previous comment"), Engine.attr("title", "Previous comment")], model.update_by(pane.map(|shown| shown.id), |state, pane_id| Model.step_thread(state, pane_id, Previous))),
						Html.span_s(pane.map2(model.signal(), |shown, state| Model.comment_count(state, shown)), [Engine.class("comment-count"), Engine.test_id("comment-count")]),
						Html.button("›", [Html.aria_label("Next comment"), Engine.attr("title", "Next comment")], model.update_by(pane.map(|shown| shown.id), |state, pane_id| Model.step_thread(state, pane_id, Next))),
					],
				),
				Html.span_s(pane.map2(model.signal(), |shown, state| Liton.round_text(Model.review_round(state, shown))), [Engine.class_s(pane.map2(model.signal(), |shown, state| if (Model.review_round(state, shown) == NoDrafts) "review-round" else "review-round active")), Engine.test_id("review-round")]),
				Html.button(
					"Finish review",
					[Engine.class("finish-review"), Engine.attr("title", "Send the drafts to the agent as one message"), Html.boolean("disabled", pane.map2(model.signal(), |shown, state| Review.drafts(Model.review_of(state, Model.context_of(state, shown))) == 0))],
					model.update_by(pane.map(|shown| shown.id), Model.finish_review),
				),
				Engine.when(
					pane.map2(model.signal(), |shown, state| Model.review_of(state, Model.context_of(state, shown)).round > 0),
					|| Html.button_s(pane.map2(model.signal(), |shown, state| "Since round ${Model.review_of(state, Model.context_of(state, shown)).round.to_str()}"), [Engine.class("since-round"), Html.flag("aria-pressed", model.signal().map(|state| state.review_desk.since_round)), Engine.attr("title", "Show only the files changed since the latest round")], model.update(Model.toggle_since_round)),
					|| Engine.text(""),
				),
				Engine.element(
					"select",
					[Engine.attr("aria-label", "Scope"), Engine.class("scope"), Engine.prop_s(Engine.Prop.value, model.signal().map(Model.review_scope_name)), Engine.on("change", model.set_value(Model.pick_review_scope))],
					[Dropdown.option("Uncommitted", "Uncommitted"), Dropdown.option("AgainstBase", "Against the base"), Engine.each(git.map(|known| known.commits), |listed| listed.sha, commit)],
				),
			],
		)
	}

	## The Review surface's inspector: the review's threads, those open,
	## resolved or all, each focusing its lines in the view, with Reply and
	## Resolve or Reopen; then the review's comments on the whole of it, and
	## one to add.
	review_threads : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Model.Pane) -> Elem(PaneCtx)
	review_threads = |model, id, pane| {
		listing = model.signal().map(|state| state.review_desk.listing)
		show = |title, picked| Html.button(title, [Html.flag("aria-pressed", listing.map(|shown| shown == picked))], model.update(|state| Model.list_threads(state, picked)))
		key = id.map(|pane_id| "${pane_id}/review")
		Html.div(
			"review-threads",
			[
				Html.div_attrs([Engine.class("choices"), Engine.attr("role", "group"), Engine.attr("aria-label", "Threads listed")], [show("Open", Open), show("Resolved", Resolved), show("All", All)]),
				Html.p_s(pane.map2(model.signal(), |shown, state| if (Model.thread_items(state, shown).is_empty()) "No threads here yet. Pick lines in the view to comment on them." else ""), [Engine.class("missing")]),
				Html.ul([Engine.class("thread-list"), Engine.attr("data-part", "threads")], [Engine.each(pane.map2(model.signal(), |shown, state| Model.thread_items(state, shown)), |item| item.id, |item| Liton.thread_item(model, id, item))]),
				Html.h3("Review conversation", "conversation-title"),
				Html.div_attrs([Engine.class("conversation"), Engine.attr("data-part", "conversation")], [Engine.each(pane.map2(model.signal(), |shown, state| Model.overall_comments(state, shown)), |note| note.comment, |note| Liton.comment(model.lift_row(), note.field(|shown| shown).map2(id.lift_row(), |shown, pane_id| { pane_id, note: shown })))]),
				Html.form(
					"Add to the review conversation",
					[Engine.class("review-overall"), Engine.on("submit", model.update_by(id, Model.comment_overall))],
					[
						Html.textarea(Engine.const("Comment on the whole review"), key.map2(model.signal(), |draft_key, state| Model.draft(state, draft_key)), [Engine.attr("rows", "2"), Engine.attr("placeholder", "On the whole review, in Markdown")], model.set_value_by(key, Model.set_draft)),
						Html.submit_button("Add", []),
					],
				),
			],
		)
	}

	## A thread of the Review surface's inspector: where it is, which
	## focuses it in the view, its state, its first line and how many
	## comments it has, and Reply and Resolve or Reopen. Top-level for the
	## reason `scope_picker` is.
	thread_item : State(PaneCtx, Model.State), Signal(PaneCtx, Str), RowRef(PaneCtx, Model.ThreadItem) -> Elem(Row(PaneCtx, Model.ThreadItem))
	thread_item = |model0, id, item| {
		model = model0.lift_row()
		shown = item.field(|listed| listed)
		acting = |action| shown.map2(id.lift_row(), |listed, pane_id| { pane_id, thread: listed.id, action })
		focuses = model.update_by(acting(Focus), Model.act_on_thread)
		Html.li(
			[Engine.class_s(shown.map(|listed| "thread-item ${listed.state}${if (listed.focused) " focused" else ""}")), Engine.attr("data-part", "thread")].concat(Liton.row_activates(focuses)),
			[
				Html.button_s(shown.map(|listed| listed.place), [Engine.class("thread-place")], focuses),
				Html.span_s(shown.map(|listed| listed.state), [Engine.class_s(shown.map(|listed| "status-word ${listed.state}")), Engine.test_id_s(shown.map(|listed| "thread-state-${listed.id}"))]),
				Html.span_s(shown.map(|listed| if (listed.comments == 1) "1 comment" else "${listed.comments.to_str()} comments"), [Engine.class("thread-comments")]),
				Html.p_s(shown.map(|listed| listed.text), [Engine.class("thread-text")]),
				Html.div(
					"thread-actions",
					[
						Html.button("Reply", [Html.aria_label_s(shown.map(|listed| "Reply to ${listed.place}"))], model.update_by(acting(Reply), Model.act_on_thread)),
						Html.button_s(shown.map(|listed| if (listed.resolved) "Reopen" else "Resolve"), [Html.aria_label_s(shown.map(|listed| "${if (listed.resolved) "Reopen" else "Resolve"} ${listed.place}"))], model.update_by(acting(Resolve), Model.act_on_thread)),
					],
				),
			],
		)
	}

	## What a Review view's bar says of its round (`Model.review_round`).
	round_text : [Drafts({ round : U32, drafts : U64 }), Sending(U32), Waiting(U32), Answered(U32), NoDrafts] -> Str
	round_text = |round|
		match round {
			Drafts({ round: number, drafts }) => "Round ${number.to_str()} · ${if (drafts == 1) "1 draft" else "${drafts.to_str()} drafts"}"
			Sending(number) => "Sending round ${number.to_str()}…"
			Waiting(number) => "Round ${number.to_str()} sent · waiting for the agent"
			Answered(number) => "Round ${number.to_str()} sent · the agent has answered"
			NoDrafts => "No drafts yet"
		}

	## The Review surface's navigator: its changed files as a tree, as
	## Changes lists them, each with how many threads are open on it; the
	## file the view has in view is marked, and picking one scrolls the view
	## to it.
	review_files : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Model.Pane) -> Elem(PaneCtx)
	review_files = |model, id, pane| {
		files = pane.map2(model.signal(), |shown, state| Model.review_files(state, shown))
		Html.div(
			"review-files",
			[
				Html.div(
					"choices",
					[
						Html.span_s(files.map(Liton.file_count), [Engine.class("file-count")]),
						Html.span_s(files.map(|listed| Liton.total_lines(listed).added), [Engine.class("added")]),
						Html.span_s(files.map(|listed| Liton.total_lines(listed).removed), [Engine.class("removed")]),
					],
				),
				Spinner.or_text(files.map(|listed| if (listed == Loading) Loading else Said(if (listed == Files([])) "No changes." else "")), Pane, [Engine.class("missing")]),
				Html.ul([Engine.class("git-files git-tree"), Engine.attr("data-part", "files")], [Engine.each(pane.map2(model.signal(), |shown, state| Model.review_tree(state, shown)), |row| if (row.folder) "folder:${row.path}" else row.path, |row| Liton.review_file_row(model, id, row))]),
			],
		)
	}

	## A row of the Review surface's navigator, as `changed_row` draws
	## Changes', with how many threads are open on the file, marked once
	## the file is viewed. Top-level for
	## the reason `scope_picker` is.
	review_file_row : State(PaneCtx, Model.State), Signal(PaneCtx, Str), RowRef(PaneCtx, Model.ReviewRow) -> Elem(Row(PaneCtx, Model.ReviewRow))
	review_file_row = |model, id, row| {
		shown = row.field(|listed| listed)
		asked = shown.map2(id.lift_row(), |listed, pane_id| { pane_id, path: listed.path, folder: listed.folder })
		picks = model.lift_row().update_by(asked, Model.pick_review_file)
		Html.li(
			[Engine.class_s(shown.map(|listed| if (listed.viewed) "git-file viewed" else if (!listed.folder) "git-file" else if (listed.folded) "git-file git-folder folded" else "git-file git-folder")), Engine.attr("data-part", "file"), Engine.attr_s("style", shown.map(|listed| "--depth: ${listed.depth.to_str()}"))].concat(Liton.row_activates(picks)),
			[
				Html.button_s(
					shown.map(|listed| listed.path.split_last("/").map_ok(|parts| parts.after) ?? listed.path),
					[
						Html.aria_label_s(shown.map(|listed| if (listed.folder) listed.path else Liton.file_label(listed.file))),
						Engine.attr_presence("aria-current", shown.map(|listed| if (listed.focused) Present("true") else Absent)),
						Engine.attr_presence("aria-expanded", shown.map(|listed| if (listed.folder) Present(if (listed.folded) "false" else "true") else Absent)),
					],
					picks,
				),
				Html.span_s(shown.map(|listed| if (listed.folder) "" else Liton.change_text(listed.file.change)), [Engine.class_s(shown.map(|listed| "change ${Liton.change_text(listed.file.change)}"))]),
				Html.span_s(shown.map(|listed| if (listed.threads == 0) "" else listed.threads.to_str()), [Engine.class("thread-count"), Engine.attr("title", "Open threads"), Engine.test_id("thread-count")]),
				Html.span_s(shown.map(|listed| Liton.file_lines(listed.file)), [Engine.class("lines")]),
			],
		)
	}

	## A file of a Review pane as a card: its path, how it changed and by
	## how many lines, and Viewed, which marks it viewed and folds its diff,
	## over its diff. Its coming on screen and leaving it
	## tells the file in view (`Model.card_seen`). Top-level for the reason
	## `scope_picker` is.
	review_card : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Model.Pane), RowRef(PaneCtx, Model.ReviewCard) -> Elem(Row(PaneCtx, Model.ReviewCard))
	review_card = |model, id, pane, card| {
		file = card.field(|shown| shown.file)
		Html.div_attrs(
			[Engine.class_s(card.field(|shown| if (shown.viewed) "review-card viewed" else "review-card")), Engine.attr("data-part", "file"), Engine.attr("role", "group"), Html.aria_label_s(card.key()), Engine.ref_s(card.key().map2(id.lift_row(), |path, pane_id| ReviewDesk.card_ref(pane_id, path))), Engine.on_seen({}, model.lift_row().set_value_by(card.key().map2(id.lift_row(), |path, pane_id| { pane_id, path }), |state, at, seen| Model.card_seen(state, at, seen.intersecting)))],
			[
				Html.div(
					"review-card-header",
					[
						Html.span_s(card.key(), [Engine.class("file-path")]),
						Html.span_s(file.map(|shown| Liton.change_text(shown.change)), [Engine.class_s(file.map(|shown| "badge change ${Liton.change_text(shown.change)}"))]),
						Html.span_s(file.map(Liton.file_lines), [Engine.class("lines")]),
						Html.button("Viewed", [Engine.class("viewed-toggle"), Html.aria_label_s(card.key().map(|path| "Viewed ${path}")), Html.flag("aria-pressed", card.field(|shown| shown.viewed)), Engine.attr("title", "Mark the file viewed, which folds it")], model.lift_row().update_by(card.key().map2(id.lift_row(), |path, pane_id| { pane_id, path }), Model.toggle_viewed)),
					],
				),
				Spinner.or_text(card.field(|shown| shown.note), Inline, [Engine.class("missing")]),
				Html.div("review-diff", [Liton.code_view(model.lift_row(), id.lift_row(), pane.lift_row().map(|shown| if (Model.option(shown, "diff_layout") == "Split") "code-view split" else "code-view unified"), card.field(|shown| shown.rows))]),
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
				Spinner.or_text(shown.map(|{ pane: pane_shown, state }| Model.tree_status(state, pane_shown)), Pane, [Engine.class("missing")]),
				Liton.tree(model, id, shown.map(|{ pane: pane_shown, state }| Model.file_rows(state, pane_shown)), NoMenus),
				Html.div_attrs(
					[Engine.class("file-view"), Engine.attr("data-part", "file")],
					[
						Html.p_s(id.map2(model.signal(), |pane_id, state| Model.file_pane(state, pane_id).file), [Engine.class("file-path")]),
						Spinner.or_text(shown.map(|{ pane: pane_shown, state }| Model.file_status(state, pane_shown)), Inline, [Engine.class("missing"), Engine.test_id("file-status")]),
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
	code_view : State(ctx, Model.State), Signal(ctx, Str), Signal(ctx, Str), Signal(ctx, List(Model.CodeRow)) -> Elem(ctx)
	code_view = |model0, id, class, rows|
		Html.div_attrs(
			[Engine.class_s(class)],
			[
				Engine.each(
					rows,
					|row| row.key,
					|row| {
						model = model0.lift_row()
						asked = |pick| row.field(|shown| (shown.path, pick(shown))).map2(id.lift_row(), |(path, picked), pane_id| { pane_id, path, picked })
						# A row of an each is one element, a hunk's header named to be
						# scrolled to.
						Html.div_attrs(
							[
								Engine.class("code-item"),
								Engine.ref_s(row.field(|shown| shown).map2(id.lift_row(), |shown, pane_id| if (shown.right_class == "hunk-header") Model.hunk_ref(pane_id, shown.path, shown.key) else "")),
								Engine.test_id_s(row.field(|shown| if (shown.right_class == "hunk-header") "hunk-${shown.path}/${shown.key}" else "")),
							],
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
	## Markdown: Comment, or Ctrl+Enter or Cmd+Enter, keeps it as a draft at
	## once, Cancel closes it.
	comment_composer : State(ctx, Model.State) -> Elem(ctx)
	comment_composer = |model|
		Html.form(
			"Comment",
			[Engine.class("comment-composer"), Engine.attr("data-part", "composer"), Engine.on("submit", model.update(Model.submit_comment))],
			[
				Html.p_s(model.signal().map(|state| Liton.composing(state.composer)), [Engine.class("composer-title")]),
				Html.textarea(Engine.const("Your comment"), model.signal().map(|state| state.composer.text), [Engine.attr("rows", "3"), Engine.attr("placeholder", "Comment, in Markdown"), Engine.ref("comment"), Engine.on_key({ keymap: Engine.const(Engine.Keymap.prevent(Engine.Chord.plain("Enter").primary())) }, model.set_value(|state, _| Commands.run_first(state, ["review.submit"])))], model.set_value(|state, text| { ..state, composer: { ..state.composer, text } })),
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
		named = noted.map(|{ pane_id, note: shown }| Model.comment_ref(pane_id, shown.comment))
		# One handler for every button, to keep the module small.
		acting = |action| noted.map(|{ pane_id, note: shown }| { pane_id, note: shown, action })
		flags = |shown| Str.join_with(["comment", if (shown.draft) "draft" else "", if (shown.last) "last" else "", if (shown.resolved) "resolved" else "", if (shown.focused) "focused" else ""].drop_if(Str.is_empty), " ")
		Html.div_attrs(
			[Engine.class_s(note.map(flags)), Engine.attr("data-part", "comment"), Engine.ref_s(named), Engine.test_id_s(note.map(|shown| "comment-${shown.comment}"))],
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
	git_file : Signal(ctx, WorkspaceGit.File), Signal(ctx, Bool), HandlerOf(ctx, Engine.Click) -> Elem(ctx)
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
		picks = model.lift_row().update_by(asked, Model.pick_changed)
		Html.li(
			[Engine.class_s(shown.map(|changed| if (!changed.folder) "git-file" else if (changed.folded) "git-file git-folder folded" else "git-file git-folder")), Engine.attr("data-part", "file"), Engine.attr_s("style", shown.map(|changed| "--depth: ${changed.depth.to_str()}"))].concat(Liton.row_activates(picks)),
			[
				Html.button_s(
					shown.map(|changed| changed.path.split_last("/").map_ok(|parts| parts.after) ?? changed.path),
					[
						Html.aria_label_s(shown.map(|changed| if (changed.folder) changed.path else Liton.file_label(changed.file))),
						Engine.attr_presence("aria-pressed", shown.map2(picked, |changed, is_picked| if (changed.folder) Absent else Present(if (is_picked) "true" else "false"))),
						Engine.attr_presence("aria-expanded", shown.map(|changed| if (changed.folder) Present(if (changed.folded) "false" else "true") else Absent)),
					],
					picks,
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
					Loading => Spinner.spinner("Loading", Pane)
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

	## A Rooms pane: a search, which narrows the rooms at once, over the
	## rooms the daemon lists under a heading of their kind
	## (`Model.room_rows`), the one focused marked, each one's name, which
	## focuses it, a dot while it has unread messages, how many mention you,
	## and Join or Leave; and while unread rooms are scrolled out of view, a
	## pill counting them, which scrolls to the first.
	rooms : State(PaneCtx, Model.State) -> Elem(PaneCtx)
	rooms = |model0|
		Html.div(
			"rooms-nav",
			[
				Html.text_input(Engine.const("Search rooms"), "search", model0.signal().map(|state| state.room_search), [Engine.class("room-search"), Engine.ref("rooms-search"), Engine.attr("placeholder", "Search rooms"), Engine.attr("autocomplete", "off")], model0.set_value(|state, typed| { ..state, room_search: typed })),
				Html.ul([Engine.class("room-list"), Engine.attr("data-part", "list")], [Engine.each(model0.signal().map(Model.room_rows), |row| row.key, |row| Liton.room_row(model0, row))]),
				Engine.when(model0.signal().map(|state| Model.room_rows(state).is_empty() and !state.rooms.is_empty()), || Html.p("No rooms match.", "missing"), || Engine.text("")),
				# The unread rooms scrolled out of view, which it scrolls to.
				Engine.when(
					model0.signal().map(|state| !Model.unread_out_of_view(state).is_empty()),
					|| Html.button_s(model0.signal().map(|state| "${Model.unread_out_of_view(state).len().to_str()} unread"), [Engine.class("unread-pill"), Html.aria_label("Show the unread rooms")], model0.update(Model.show_unread)),
					|| Engine.text(""),
				),
			],
		)

	## A heading of a kind of rooms, or a room's row.
	room_row : State(PaneCtx, Model.State), RowRef(PaneCtx, Model.RoomRow) -> Elem(Row(PaneCtx, Model.RoomRow))
	room_row = |model0, row| {
		model = model0.lift_row()
		room = row.field(|shown| shown.room)
		heading = row.field(|shown| shown.heading)
		opens = model.update_by(row.field(|shown| shown), |state, shown| if (shown.heading.is_empty()) Model.open(state, Room(shown.key)) else state)
		# One element, as a row of `each` must be.
		Html.li(
			[Engine.class_s(row.field(|shown| shown).map2(model.signal(), |shown, state| if (!shown.heading.is_empty()) "room-group" else Liton.joined_classes(Liton.room_row_class(shown.room), if (Model.focused(state, [Room]) == Room(shown.key)) "focused" else ""))), Engine.attr("data-part", "room")].concat(Liton.row_activates(opens)),
			[
				Engine.when(
					heading.map(|title| !title.is_empty()),
					|| Engine.text_s(heading),
					||
						Html.div(
							"room-line",
							[
								Html.button_s(room.map(Liton.room_name), [Engine.class("room-name"), Engine.ref_s(row.key().map(|room_id| "room-${room_id}")), Engine.on_seen({}, model.set_value_by(row.key(), |state, room_id, seen| Model.room_seen(state, room_id, seen.intersecting)))], opens),
								Html.span_s(room.map(|shown| Liton.room_unread(shown.kind, shown.unread)), [Engine.class("room-unread"), Engine.test_id("room-unread")]),
								Liton.join_controls(model, room),
							],
						),
				),
			],
		)
	}

	## A room's name as listed: a direct conversation's as it is, the
	## others' after #.
	room_name : Rooms.Room -> Str
	room_name = |room| if (room.kind == Direct) room.name else "#${room.name}"

	## A room's row: unread while it has messages you haven't read, and
	## muted while you aren't in it.
	room_row_class : Rooms.Room -> Str
	room_row_class = |room| {
		unread =
			match room.unread {
				Counted({ messages, .. }) => messages > 0
				Unknown => Bool.False
			}
		Str.join_with(["room-row", if (unread) "unread" else "", if (room.joined) "" else "not-joined"].drop_if(Str.is_empty), " ")
	}

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
	## A thread opened shows in the Thread pane, or without one, beside
	## them, or in their place in a narrow pane.
	room_opened : State(PaneCtx, Model.State), Signal(PaneCtx, Str) -> Elem(PaneCtx)
	room_opened = |model, id| {
		opened = id.map2(model.signal(), |pane_id, state| Model.room_pane(state, pane_id))
		room_id = opened.map(|shown| shown.room_id)
		shown = room_id.map2(model.signal(), |opened_id, state| Model.room_of(state, opened_id))
		beside = opened.map2(model.signal(), |{ root, .. }, state| !root.is_empty() and !Model.threads_apart(state))
		Html.div_s(
			shown.map2(beside, |room, threaded| Str.join_with(["room", if (room.kind == Forum) "forum" else "", if (threaded) "threaded" else ""].drop_if(Str.is_empty), " ")),
			[Html.div("room-main", Liton.room_main(model, id, room_id, shown)), Engine.when(beside, || Liton.room_thread(model, id, opened, "Thread"), || Engine.text(""))],
		)
	}

	## A Thread pane: the thread open in the room it follows, or where to
	## open one.
	thread_view : State(PaneCtx, Model.State), Signal(PaneCtx, Str) -> Elem(PaneCtx)
	thread_view = |model, id| {
		opened = id.map2(model.signal(), |pane_id, state| Model.room_pane(state, pane_id))
		Engine.when(opened.map(|{ root, .. }| root.is_empty()), || Html.p("Open a message's thread to show it here.", "missing"), || Liton.room_thread(model, id, opened, ""))
	}

	## A room's controls, in its pane's header beside its name and topic:
	## its members, which show the Members pane, and its ⋯ menu.
	room_controls : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Rooms.Room) -> Elem(PaneCtx)
	room_controls = |model, id, shown|
		Html.div(
			"room-controls",
			[
				Engine.when(
					model.signal().map(|state| Model.panes(state).any(|pane| pane.widget == "members")),
					|| Html.button_s(shown.map2(model.signal(), |opened, state| Liton.members_text(Model.room_members_of(state, opened.id).len())), [Engine.class("room-members"), Html.flag("aria-pressed", model.signal().map(|state| Model.panes(state).any(|pane| pane.widget == "members" and Model.pane_visible(state, pane.id))))], model.update(Model.toggle_members)),
					|| Engine.text(""),
				),
				Liton.room_menu(model, id, shown),
			],
		)

	## A room's messages, who is typing and the agents working; and Join,
	## if you aren't in it, over its composer. Its pane's header names it.
	room_main : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Str), Signal(PaneCtx, Rooms.Room) -> List(Elem(PaneCtx))
	room_main = |model, id, room_id, shown| {
		messages = Engine.each(id.map2(model.signal(), |pane_id, state| Model.room_lines(state, pane_id)), |line| line.id, |row| Liton.room_message(model, id, row))
		Conversation.timeline(model, id, { class: "timeline room-timeline", part: "room", jump: "Jump to latest", earlier: Engine.const(Bool.False), loading: room_id.map2(model.signal(), |opened, state| !Model.room_loaded(state, opened, "")) }, [messages])
			.concat([
				Html.p_s(room_id.map2(model.signal(), |opened, state| Model.typing(state, opened, "")), [Engine.class("room-typing"), Engine.attr("role", "status"), Engine.test_id("room-typing")]),
				# The agents working in the room or its threads.
				Html.div(
					"agents-working",
					[
						Engine.each(room_id.map2(model.signal(), |opened, state| Model.agents_working(state, opened)), |name| name, |name| Liton.avatar(name.key().map(|agent_name| { initial: Model.initial_of(agent_name), agent: Bool.True }))),
						Html.span_s(room_id.map2(model.signal(), |opened, state| Liton.working_text(Model.agents_working(state, opened))), [Engine.attr("role", "status"), Engine.test_id("agents-working")]),
					],
				),
				# A room you aren't in, read before you join it.
				Engine.when(
					shown.map(|room| !room.joined),
					|| Html.div("room-preview", [Html.span_s(shown.map(|room| "You haven't joined ${Liton.room_name(room)}."), []), Liton.join_controls(model, shown)]),
					|| Engine.text(""),
				),
				Liton.room_composer(model, id, Room, shown.map(|room| if (room.kind == Forum) "New post in #${room.name}" else "Message #${room.name}")),
			])
	}

	## A Members pane: the people and agents in the room it follows, each
	## with an avatar, an agent's marked, how present, their role and whose
	## agent each is.
	members_view : State(PaneCtx, Model.State), Signal(PaneCtx, Str) -> Elem(PaneCtx)
	members_view = |model, id| {
		room_id = id.map2(model.signal(), |pane_id, state| Model.room_pane(state, pane_id).room_id)
		Engine.when(
			room_id.map(Str.is_empty),
			|| Html.p("Pick a room in Rooms to see who is in it.", "missing"),
			||
				Html.ul(
					[Engine.class("member-list"), Engine.attr("data-part", "list")],
					[
						Engine.each(
							room_id.map2(model.signal(), |shown, state| Model.room_people(state, shown)),
							|person| person.id,
							|row|
								Html.li(
									[Engine.class_s(row.field(|person| if (person.agent) "member agent" else "member")), Engine.attr("data-part", "member")],
									[
										Liton.avatar(row.field(|person| { initial: person.initial, agent: person.agent })),
										Html.span_s(row.field(|person| person.name), [Engine.class("member-name")]),
										Html.span_s(row.field(|person| person.detail), [Engine.class("member-detail")]),
										Html.span_s(row.field(|person| person.presence), [Engine.class_s(row.field(|person| "presence ${person.presence}"))]),
									],
								),
						),
					],
				),
		)
	}

	## A person's round avatar, their initial, or an agent's square one
	## with a robot's badge, which a screen reader names.
	avatar : Signal(ctx, { initial : Str, agent : Bool }) -> Elem(ctx)
	avatar = |shown| Html.span_s(shown.map(|{ initial, .. }| initial), [Engine.class_s(shown.map(|{ agent, .. }| if (agent) "avatar agent" else "avatar")), Engine.attr("aria-hidden", "true")])

	## The thread a Room or Thread pane opened: its top-level message, its
	## replies and who is typing in it, and in a Room pane × to close it,
	## under `title`.
	room_thread : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Model.RoomPane), Str -> Elem(PaneCtx)
	room_thread = |model, id, opened, title| {
		# A Thread pane's header has its title and × in its place.
		header = if (title.is_empty()) [] else [Html.div("room-header", [Html.span_s(Engine.const(title), [Engine.class("room-title")]), Liton.icon_button(Engine.const("Close the thread"), "icon dismiss", model.update_by(id, |state, pane_id| Model.open_thread(state, { pane_id, root: "" })))])]
		replies = Engine.each(id.map2(model.signal(), |pane_id, state| Model.thread_lines(state, pane_id)), |line| line.id, |row| Liton.room_message(model, id, row))
		Html.section(
			if (title.is_empty()) "Thread messages" else title,
			"room-thread-pane",
			header
				.concat(Conversation.timeline(model, id.map(|pane_id| "${pane_id}/thread"), { class: "timeline room-timeline", part: "thread", jump: "Jump to latest reply", earlier: Engine.const(Bool.False), loading: opened.map2(model.signal(), |{ room_id, root, .. }, state| !Model.room_loaded(state, room_id, root)) }, [replies]))
				.concat([
					Html.p_s(opened.map2(model.signal(), |{ room_id, root, .. }, state| Model.typing(state, room_id, root)), [Engine.class("room-typing"), Engine.attr("role", "status"), Engine.test_id("thread-typing")]),
					Liton.room_composer(model, id, Thread, Engine.const("Reply in the thread")),
				]),
		)
	}

	## The composer of a Rooms pane's room, or of the thread it opened, as
	## the chat's: Send shows the message at once as sending. A mention being
	## typed offers the room's members it may name.
	room_composer : State(PaneCtx, Model.State), Signal(PaneCtx, Str), [Room, Thread], Signal(PaneCtx, Str) -> Elem(PaneCtx)
	room_composer = |model, id, place, placeholder| {
		key = id.map(|pane_id| if (place == Thread) "${pane_id}/thread" else pane_id)
		Conversation.composer(
			model,
			key,
			{ form: if (place == Thread) "Reply in the thread" else "Send to the room", name: if (place == Thread) "Your reply" else "Your message", placeholder, send: Model.send_to_room, completions: Model.mention_choices, shift_tab: Ignored },
			[Conversation.send_button(if (place == Thread) "Send the reply" else "Send to the room")],
		)
	}

	## A message: its author's avatar, who wrote it, a person or an agent,
	## how long ago, and whether edited, all but under a message they wrote
	## just before (`Model.RoomLine`'s `continued`); its text as Markdown,
	## unless deleted; its reactions; its actions, as the pointer is over
	## it; and its thread's replies.
	room_message : State(PaneCtx, Model.State), Signal(PaneCtx, Str), RowRef(PaneCtx, Model.RoomLine) -> Elem(Row(PaneCtx, Model.RoomLine))
	room_message = |model0, id, row| {
		model = model0.lift_row()
		Html.li(
			[Engine.class_s(row.field(|line| Str.join_with(["room-message", if (line.agent) "agent" else "", if (line.continued) "continued" else "", if (line.deleted) "deleted" else "", if (line.failed) "failed" else if (line.status.is_empty()) "" else "pending"].drop_if(Str.is_empty), " "))), Engine.attr("data-part", "message")],
			[
				Liton.avatar(row.field(|line| { initial: line.initial, agent: line.agent })),
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
					|| Liton.markdown(model, row.key().map2(id.lift_row(), |message_id, pane_id| "${pane_id}/${message_id}"), row.field(|line| line.text).map2(id.lift_row().map2(model.signal(), Model.mention_classes), |text, names| Markdown.mentions(Markdown.blocks(text), names))),
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
					],
				),
				# Over the message as the pointer is, or a key focuses in it:
				# the reactions no one has made yet, Reply in its thread, and
				# Copy link. Absolute, so hidden it leaves no gap.
				Engine.when(
					row.field(|line| !line.deleted and line.status.is_empty()),
					||
						Html.div(
							"message-actions",
							[
								Engine.each(
									row.field(|line| Liton.reaction_choices.drop_if(|emoji| line.reactions.any(|reaction| reaction.emoji == emoji))),
									|emoji| emoji,
									|choice| Html.button_s(choice.key(), [Engine.class("react"), Html.aria_label_s(choice.key().map(|emoji| "React with ${emoji}"))], model.lift_row().update_by(choice.key().map2(row.key().lift_row().map2(id.lift_row().lift_row(), |message_id, pane_id| { message_id, pane_id }), |emoji, { message_id, pane_id }| { pane_id, message_id, emoji, mine: Bool.False }), Model.toggle_reaction)),
								),
								Engine.when(row.field(|line| line.threaded), || Html.button("Reply", [Engine.class("reply"), Html.aria_label("Reply in the thread")], model.update_by(row.key().map2(id.lift_row(), |root, pane_id| { pane_id, root }), Model.open_thread)), || Engine.text("")),
								Html.button_s(row.key().map2(model.signal(), |message_id, state| if (state.copied == "link:${message_id}") "Copied" else "Copy link"), [Engine.class("copy-link"), Html.aria_label("Copy link")], model.update_by(row.key().map2(id.lift_row(), |message_id, pane_id| { message_id, pane_id }), Model.copy_link)),
							],
						),
					|| Engine.text(""),
				),
				Conversation.sent_state(
					{ status: row.field(|line| line.status), failed: row.field(|line| line.failed), test_id: "room-sent-status" },
					[
						{ label: "Retry", handler: model.update_by(row.field(|line| { serial: line.serial, again: Bool.True }), Model.resend) },
						{ label: "Discard", handler: model.update_by(row.field(|line| { serial: line.serial, again: Bool.False }), Model.resend) },
					],
				),
				Engine.when(
					row.field(|line| line.threaded and line.status.is_empty() and (line.replies > 0 or !line.working.is_empty())),
					||
						Html.div(
							"room-thread",
							[
								Engine.each(row.field(|line| line.participants), |person| person.name, |person| Liton.avatar(person.field(|shown| { initial: shown.initial, agent: shown.agent }))),
								Html.button_s(row.field(Liton.replies_text), [Engine.test_id("room-replies")], model.update_by(row.key().map2(id.lift_row(), |root, pane_id| { pane_id, root }), Model.open_thread)),
								Html.span_s(row.field(|line| if (line.working.is_empty()) "" else "working"), [Engine.class("working-badge"), Engine.attr_s("title", row.field(|line| "${line.working} working in the thread")), Engine.test_id("thread-working")]),
								Html.span_s(row.field(|line| line.last_reply), [Engine.class("room-last-reply")]),
							],
						),
					|| Engine.text(""),
				),
			],
		)
	}

	## "Scout is working", "Scout and Patch are working", or "" for none.
	working_text : List(Str) -> Str
	working_text = |names|
		match names {
			[] => ""
			[one] => "${one} is working"
			_ => "${Str.join_with(names.drop_last(1), ", ")} and ${names.last() ?? ""} are working"
		}

	## A room's ⋯ menu: Copy link, which copies the room as its context
	## names it, and Leave or Join, each closing it.
	room_menu : State(PaneCtx, Model.State), Signal(PaneCtx, Str), Signal(PaneCtx, Rooms.Room) -> Elem(PaneCtx)
	room_menu = |model, id, room| {
		# Named after its pane, which keeps it open as it is focused.
		key = id.map(|pane_id| "${pane_id} room")
		Html.div(
			"pane-menu room-menu",
			[
				Engine.element(
					"button",
					[Engine.attr("type", "button"), Engine.class("icon menu-toggle"), Html.aria_label("Room actions"), Engine.attr("title", "Room actions"), Engine.attr("aria-haspopup", "true"), Html.flag("aria-expanded", key.map2(model.signal(), |menu, state| state.menu == menu)), Engine.on_click(model.update_by(key, Model.toggle_menu))],
					[],
				),
				Engine.when(
					key.map2(model.signal(), |menu, state| state.menu == menu),
					||
						Html.div(
							"menu",
							[
								Html.button_s(room.map(|shown| "Copy link to ${Liton.room_name(shown)}"), [], model.update_by(room.map(|shown| shown.id), |state, room_id| { ..Model.copy_room_link(state, room_id), menu: "" })),
								Html.button_s(room.map(|shown| if (shown.joined) "Leave ${Liton.room_name(shown)}" else "Join ${Liton.room_name(shown)}"), [], model.update_by(room.map(|shown| shown.id), |state, room_id| { ..Model.toggle_joined(state, room_id), menu: "" })),
							],
						),
					|| Engine.text(""),
				),
			],
		)
	}

	members_text : U64 -> Str
	members_text = |count| if (count == 1) "1 member" else "${count.to_str()} members"

	## The reactions a message offers to make: a +, as a like, and two more.
	reaction_choices : List(Str)
	reaction_choices = ["+", "👀", "🎉"]

	## A thread's replies and who replied, as "2 replies · Scout, Ada", or
	## "Thread" while an agent works on its first.
	replies_text : Model.RoomLine -> Str
	replies_text = |line|
		match line.replies {
			0 => "Thread"
			1 => "1 reply · ${line.repliers}"
			count => "${count.to_str()} replies · ${line.repliers}"
		}

	## What a room's row counts: the mentions of you, as "@1", or in a
	## direct conversation, the messages unread.
	room_unread : Rooms.Kind, [Counted({ messages : U32, mentions : U32 }), Unknown] -> Str
	room_unread = |kind, unread|
		match unread {
			Counted({ mentions, .. }) if mentions > 0 => "@${mentions.to_str()}"
			Counted({ messages, .. }) if kind == Direct and messages > 0 => messages.to_str()
			_ => ""
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

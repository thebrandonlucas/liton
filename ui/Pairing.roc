## Pairing this browser with the daemon, which answers only paired devices
## (docs/protocol.md, Authentication), and Settings' Devices, the devices
## paired. The token is an HttpOnly cookie the daemon sets, which the page's
## requests carry and its code never sees.
import pf.Engine exposing [Elem, State]
import pf.Html
import Model

Pairing := [].{

	## The state with the page's address and the code its URL's `#pair=`
	## gives, tried once the daemon says this browser isn't paired.
	restored : Model.State, Str -> Model.State
	restored = |state, url| {
		{ before: page, after: hash } = url.split_first("#") ?? { before: url, after: "" }
		code = hash.split_on("&").find_first(|part| part.starts_with("pair=")).map_ok(|part| part.drop_prefix("pair=")) ?? ""
		{ ..state, pairing: { ..state.pairing, page, code, from_url: !code.is_empty() } }
	}

	## The daemon refused a request as this browser isn't paired: the pair
	## screen shows, and the URL's code, if any, is tried at once.
	refused : Model.State -> Model.State
	refused = |state| {
		unpaired = { ..state, pairing: { ..state.pairing, unpaired: Bool.True, devices: [], revoking: [] } }
		if (state.pairing.from_url and !state.pairing.sending) Pairing.send({ ..unpaired, pairing: { ..unpaired.pairing, from_url: Bool.False } }) else unpaired
	}

	## Sends the code typed, shown as pairing at once.
	send : Model.State -> Model.State
	send = |state| {
		code = state.pairing.code.trim()
		if code.is_empty() {
			{ ..state, pairing: { ..state.pairing, failed: "Type the pairing code first." } }
		} else if state.pairing.sending {
			state
		} else {
			{ ..state, pairing: { ..state.pairing, sent: { serial: state.pairing.sent.serial + 1, code, name: Pairing.device_name(state) }, sending: Bool.True, failed: "" } }
		}
	}

	## The daemon's answer to the pairing numbered `serial`: paired, the
	## manifest is asked for again; else why not.
	answered : Model.State, U64, Try(Str, Engine.HttpError) -> Model.State
	answered = |state, serial, res| {
		pairing = state.pairing
		if serial != pairing.sent.serial {
			state
		} else {
			match res {
				Ok(_) => { ..state, pairing: { ..pairing, unpaired: Bool.False, sending: Bool.False, code: "", failed: "", paired: pairing.paired + 1 } }
				Err(Status(401)) => { ..state, pairing: { ..pairing, sending: Bool.False, failed: "That code is wrong, used or expired. Make a new one." } }
				Err(Status(429)) => { ..state, pairing: { ..pairing, sending: Bool.False, failed: "Too many tries. Wait a minute, then try again." } }
				Err(_) => { ..state, pairing: { ..pairing, sending: Bool.False, failed: "The daemon didn't answer. Try again." } }
			}
		}
	}

	## What this browser is called among the devices.
	device_name : Model.State -> Str
	device_name = |state|
		if (state.coarse_pointer) "Phone or tablet" else if (state.operating_system == Mac) "Browser on a Mac" else "Browser"

	## The devices the daemon listed, or the pair screen if it refuses.
	listed : Model.State, Try(Str, Engine.HttpError) -> Model.State
	listed = |state, res| {
		decoded : Try({ devices : List(Model.Device) }, _)
		decoded = Json.parse(res ?? "")
		match (res, decoded) {
			(Err(Status(401)), _) => Pairing.refused(state)
			(_, Ok({ devices })) => { ..state, pairing: { ..state.pairing, devices } }
			_ => state
		}
	}

	## Asks for a code for another device, shown as being made at once.
	make_code : Model.State -> Model.State
	make_code = |state| { ..state, pairing: { ..state.pairing, offer: { serial: state.pairing.offer.serial + 1, asking: Bool.True, code: "" } } }

	## The code the daemon made for another device.
	code_made : Model.State, U64, Try(Str, Engine.HttpError) -> Model.State
	code_made = |state, serial, res| {
		decoded : Try({ code : Str }, _)
		decoded = Json.parse(res ?? "")
		offer = state.pairing.offer
		match decoded {
			_ if serial != offer.serial => state
			Ok({ code }) => { ..state, pairing: { ..state.pairing, offer: { ..offer, asking: Bool.False, code } } }
			Err(_) => { ..state, pairing: { ..state.pairing, offer: { ..offer, asking: Bool.False } }, notice: "The daemon didn't make a pairing code." }
		}
	}

	## Revokes device `id`, shown as revoking at once.
	revoke : Model.State, Str -> Model.State
	revoke = |state, id|
		if (state.pairing.revoking.contains(id)) state else { ..state, pairing: { ..state.pairing, revoking: state.pairing.revoking.append(id), revoke: { serial: state.pairing.revoke.serial + 1, id } } }

	## The daemon's answer to revoking `id`: gone from the list, and this
	## browser signed out if it was this one; else back, with why.
	revoked : Model.State, Str, Try(Str, Engine.HttpError) -> Model.State
	revoked = |state, id, res| {
		pairing = { ..state.pairing, revoking: state.pairing.revoking.drop_if(|revoking| revoking == id) }
		current = state.pairing.devices.any(|device| device.id == id and device.current)
		match res {
			Ok(_) if current => Pairing.refused({ ..state, pairing, show_settings: Bool.False })
			Ok(_) => { ..state, pairing: { ..pairing, devices: pairing.devices.drop_if(|device| device.id == id) } }
			Err(Status(401)) => Pairing.refused({ ..state, pairing })
			Err(_) => { ..state, pairing, notice: "Couldn't revoke ${state.pairing.devices.find_first(|device| device.id == id).map_ok(|device| device.name) ?? "the device"}: the daemon didn't answer." }
		}
	}

	## How long ago `at` was, in words.
	since : Model.State, I64 -> Str
	since = |state, at| {
		minutes = (state.now - at) // 60_000
		if (state.now == 0) "" else if (minutes < 1) "just now" else if (minutes < 60) "${minutes.to_str()} min ago" else if (minutes < 1440) "${(minutes // 60).to_str()} h ago" else "${(minutes // 1440).to_str()} days ago"
	}

	## What the browser shows in place of the UI while it isn't paired: a
	## box for a pairing code, and where to get one.
	screen : State(ctx, Model.State) -> Elem(ctx)
	screen = |model|
		Engine.when(
			model.signal().map(|state| state.pairing.unpaired),
			||
				Html.div(
					"pair-screen",
					[
						Html.form(
							"Pair this browser",
							[Engine.class("pair-card"), Engine.on("submit", model.update(Pairing.send))],
							[
								Html.h2("Pair this browser", ""),
								Html.p("This liton daemon answers only the devices paired with it. Run liton pair on the daemon's machine, or open Settings → Devices in a browser already paired, for a pairing code.", "help"),
								Html.text_input(Engine.const("Pairing code"), "text", model.signal().map(|state| state.pairing.code), [Engine.attr("placeholder", "ABCD-EFGH"), Engine.attr("autocomplete", "one-time-code"), Engine.attr("autocapitalize", "characters"), Engine.attr("spellcheck", "false"), Engine.class("pair-code")], model.set_value(|state, code| { ..state, pairing: { ..state.pairing, code } })),
								Html.action_button(model.signal().map(|state| if (state.pairing.sending) "Pairing…" else "Pair"), model.signal().map(|state| state.pairing.sending), [Engine.attr("type", "submit"), Engine.class("primary")], model.update(Pairing.send)),
								Html.p_s(model.signal().map(|state| state.pairing.failed), [Engine.class("pair-failed"), Engine.attr("role", "alert"), Engine.test_id("pair-failed")]),
							],
						),
					],
				),
			|| Engine.text(""),
		)

	## Settings' Devices: a code for another device, and the devices paired,
	## each to revoke.
	section : State(ctx, Model.State) -> Elem(ctx)
	section = |model| {
		offer = model.signal().map(|state| state.pairing.offer)
		Html.div(
			"settings-section",
			[
				Html.div(
					"settings-card-group",
					[
						Html.h3("Pair another device", ""),
						Html.div(
							"settings-card",
							[
								Html.div(
									"settings-row",
									[
										Html.action_button(offer.map(|asked| if (asked.asking) "Making a code…" else if (asked.code.is_empty()) "Pair another device" else "Make another code"), offer.map(|asked| asked.asking), [], model.update(Pairing.make_code)),
										Html.p("A code pairs one device, once, within 10 minutes: enter it on that device's pair screen, or open the link there.", "help"),
									],
								),
								Engine.when(
									offer.map(|asked| !asked.code.is_empty()),
									||
										Html.div(
											"settings-row pair-offer",
											[
												Html.span_s(offer.map(|asked| asked.code), [Engine.class("pair-offered-code"), Engine.test_id("pair-offered-code")]),
												Html.p_s(model.signal().map(|state| Pairing.link(state)), [Engine.class("help pair-link"), Engine.test_id("pair-link")]),
											],
										),
									|| Engine.text(""),
								),
							],
						),
					],
				),
				Html.div(
					"settings-card-group",
					[
						Html.h3("Paired", ""),
						Html.div(
							"settings-card",
							[
								Engine.each(
									model.signal().map(|state| state.pairing.devices),
									|device| device.id,
									|row|
										Html.div(
											"settings-row device-row",
											[
												Html.div(
													"device-text",
													[
														Html.span_s(row.field(|device| if (device.current) "${device.name} · this browser" else device.name), [Engine.class("settings-row-title")]),
														Html.p_s(row.field(|device| device).map2(model.signal().lift_row(), |device, state| "Paired ${Pairing.since(state, device.created_at)}, last seen ${Pairing.since(state, device.seen_at)}"), [Engine.class("help")]),
													],
												),
												Html.action_button(
													row.key().map2(model.signal().lift_row(), |id, state| if (state.pairing.revoking.contains(id)) "Revoking…" else "Revoke"),
													row.key().map2(model.signal().lift_row(), |id, state| state.pairing.revoking.contains(id)),
													[Html.aria_label_s(row.field(|device| "Revoke ${device.name}"))],
													model.lift_row().update_by(row.key(), Pairing.revoke),
												),
											],
										),
								),
								Engine.when(model.signal().map(|state| state.pairing.devices.is_empty()), || Html.div("settings-row", [Html.p("No device is paired: this daemon answers this browser without pairing, as it listens on this machine alone.", "help")]), || Engine.text("")),
							],
						),
					],
				),
			],
		)
	}

	## The link that pairs a device with the code made, on this page.
	link : Model.State -> Str
	link = |state| "${state.pairing.page}#pair=${state.pairing.offer.code}"

	## The requests: the pairing sent, the devices while Settings shows
	## them, a code for another device, and each revocation.
	effects : State(ctx, Model.State) -> List(Elem(ctx))
	effects = |model| [
		Engine.watch_changes(
			model.signal().map(|state| state.pairing.sent),
			|{ code, name, .. }| [Engine.http_body({ method: "POST", url: "/liton/v1/pair", headers: [("Content-Type", "application/json")], body: Json.to_str({ code, name }), timeout: Ms(10000) })],
			model.on_result(|state, { serial, .. }, res| Pairing.answered(state, serial, res)),
		),
		Engine.watch(
			model.signal().map(|state| if (state.show_settings and state.settings_page.section == "devices" and !state.pairing.unpaired) Listing(state.pairing.listings) else NotListing),
			|listing|
				match listing {
					Listing(_) => [Engine.http_body({ url: "/liton/v1/devices", timeout: Ms(5000) })]
					NotListing => []
				},
			model.on_result(|state, _, res| Pairing.listed(state, res)),
		),
		Engine.watch_changes(
			model.signal().map(|state| state.pairing.offer.serial),
			|_| [Engine.http_body({ method: "POST", url: "/liton/v1/devices/code", headers: [("Content-Type", "application/json")], body: "{}", timeout: Ms(5000) })],
			model.on_result(|state, serial, res| Pairing.code_made(state, serial, res)),
		),
		Engine.watch_changes(
			model.signal().map(|state| state.pairing.revoke),
			|{ id, .. }| [
				Engine.http_body({
					method: "POST",
					url: "/liton/v1/devices/revoke",
					headers: [("Content-Type", "application/json")],
					body: Json.to_str(
						{
							id
						},
					),
					timeout: Ms(5000),
				}),
			],
			model.on_result(|state, { id, .. }, res| Pairing.revoked(state, id, res)),
		),
	]
}

## Signing this browser in with a passkey, or pairing it with a code, as
## the daemon answers only devices signed in (docs/protocol.md,
## Authentication), and Settings' Passkeys & devices, the person's own. The token is an HttpOnly cookie the daemon sets, which the page's
## requests carry and its code never sees.
import pf.Engine exposing [Elem, State]
import pf.Html
import Model
import Ports

Pairing := [].{

	## The state with the code the URL's `#pair=` gives, or the invite its
	## `#invite=` does, tried once the daemon says this browser isn't paired,
	## and the page's address, which an invite's link names.
	restored : Model.State, Str -> Model.State
	restored = |state, url| {
		hash = url.split_first("#").map_ok(|{ after, .. }| after) ?? ""
		given = |name| hash.split_on("&").find_first(|part| part.starts_with("${name}=")).map_ok(|part| part.drop_prefix("${name}=")) ?? ""
		code = given("pair")
		page = url.split_first("#").map_ok(|{ before, .. }| before) ?? url
		{ ..state, pairing: { ..state.pairing, code, from_url: !code.is_empty(), invite: given("invite") }, people: { ..state.people, page } }
	}

	## The daemon refused a request as this browser isn't paired: the sign-in
	## screen shows, and the URL's invite or pairing code, if any, asks the
	## daemon at once for the passkey it grants.
	refused : Model.State -> Model.State
	refused = |state| {
		unpaired = { ..state, pairing: { ..state.pairing, unpaired: Bool.True, devices: [], revoking: [], passkeys: [], deleting: [] } }
		busy = state.pairing.sending or state.pairing.ceremony.busy
		if state.pairing.invite != "" and !busy {
			Pairing.started({ ..unpaired, pairing: { ..unpaired.pairing, invite: "" } }, Invite(state.pairing.invite))
		} else if state.pairing.from_url and !busy {
			Pairing.started({ ..unpaired, pairing: { ..unpaired.pairing, from_url: Bool.False } }, Pair(state.pairing.code.trim()))
		} else {
			unpaired
		}
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

	## Starts making or using a passkey for `purpose`, shown as busy at once:
	## the daemon's challenge first.
	started : Model.State, Model.Purpose -> Model.State
	started = |state, purpose| {
		ceremony = state.pairing.ceremony
		(route, body) =
			match purpose {
				SignIn => ("login/begin", "{}")
				Register => ("passkeys/register/begin", "{}")
				Pair(code) => (
					"passkeys/register/begin",
					Json.to_str(
						{
							code
						},
					),
				)
				Invite(secret) => (
					"invite",
					Json.to_str(
						{
							secret
						},
					),
				)
			}
		serial = ceremony.serial + 1
		{ ..state, pairing: { ..state.pairing, ceremony: { ..ceremony, serial, purpose, options: "", unnamed: Bool.False, invited: "", busy: Bool.True, failed: "", begin: { serial: ceremony.begin.serial + 1, ceremony: serial, route: "/liton/v1/${route}", body } } } }
	}

	## The daemon's challenge for the passkey numbered `serial`: signing in,
	## or one more for the person signed in, the browser is asked at once; a
	## code's or an invite's waits on a click, and the owner's name if they
	## have none. Passkeys refused for want of the box's name, a code pairs
	## this browser as it did before passkeys.
	challenged : Model.State, U64, Try(Str, Engine.HttpError) -> Model.State
	challenged = |state, serial, res| {
		ceremony = state.pairing.ceremony
		said : Try({ unnamed : Try(Bool, [Missing]), invite : Try({ name : Str }, [Missing]) }, _)
		said = Json.parse(res ?? "")
		if serial != ceremony.serial {
			return state
		}
		match (res, ceremony.purpose) {
			(Ok(options), purpose) => {
				ready = { ..state, pairing: { ..state.pairing, ceremony: { ..ceremony, options, busy: Bool.False, unnamed: said.map_ok(|answer| answer.unnamed == Ok(Bool.True)) ?? Bool.False, invited: said.map_ok(|answer| answer.invite.map_ok(|invite| invite.name) ?? "") ?? "" } } }
				match purpose {
					SignIn | Register => Pairing.ask(ready)
					_ => ready
				}
			}
			(Err(Status(503)), Pair(code)) => Pairing.send({ ..state, pairing: { ..state.pairing, code, ceremony: { ..ceremony, busy: Bool.False } } })
			(Err(error), purpose) => Pairing.ceremony_failed(state, Pairing.refusal(purpose, error))
		}
	}

	## The passkey being made or used, failed with `why`.
	ceremony_failed : Model.State, Str -> Model.State
	ceremony_failed = |state, why| { ..state, pairing: { ..state.pairing, ceremony: { ..state.pairing.ceremony, busy: Bool.False, failed: why } } }

	## Why the daemon refused a passkey for `purpose`, for a person.
	refusal : Model.Purpose, Engine.HttpError -> Str
	refusal = |purpose, error|
		match (error, purpose) {
			(Status(503), _) => "Passkeys aren't set up on this box: its operator sets LITON_RP_ID."
			(Status(403), _) => "Passkeys work at the box's own name: open liton there."
			(Status(401), Pair(_)) => "That pairing code is wrong, used or expired. Make a new one."
			(Status(401), Invite(_)) => "That invite is wrong, used or expired. Ask for a new one."
			(Status(401), SignIn) => "This passkey isn't one of this box's people's. Ask for an invite."
			(Status(401), Register) => "Sign in again, then make the passkey."
			(Status(409), _) => "This passkey is made already."
			(Status(429), _) => "Too many tries. Wait a minute, then try again."
			(Status(400), _) => "The daemon refused this passkey."
			_ => "The daemon didn't answer. Try again."
		}

	## The click that signs in, or makes the passkey a code or invite grants,
	## once its challenge came, else asks for it again.
	clicked : Model.State, Model.Purpose -> Model.State
	clicked = |state, purpose| {
		ceremony = state.pairing.ceremony
		if ceremony.busy {
			state
		} else if ceremony.purpose == purpose and ceremony.options != "" {
			Pairing.ask(state)
		} else {
			Pairing.started(state, purpose)
		}
	}

	## Asks the browser to make the passkey, or use one to sign in, as the
	## challenge says, shown as busy at once.
	ask : Model.State -> Model.State
	ask = |state| {
		ceremony = state.pairing.ceremony
		asking = { serial: ceremony.ask.serial + 1, ceremony: ceremony.serial, create: ceremony.purpose != SignIn, options: ceremony.options, name: Pairing.device_name(state), person_name: ceremony.person_name.trim() }
		{ ..state, pairing: { ..state.pairing, ceremony: { ..ceremony, busy: Bool.True, failed: "", ask: asking } } }
	}

	## The browser's passkey for the ceremony numbered `serial`, sent to the
	## daemon; or that it made or used none.
	browser_answered : Model.State, U64, Try(Str, _) -> Model.State
	browser_answered = |state, serial, res| {
		ceremony = state.pairing.ceremony
		route = if (ceremony.purpose == SignIn) "/liton/v1/login/finish" else "/liton/v1/passkeys/register/finish"
		match res {
			_ if serial != ceremony.serial => state
			Ok(body) => { ..state, pairing: { ..state.pairing, ceremony: { ..ceremony, finish: { serial: ceremony.finish.serial + 1, ceremony: serial, route, body } } } }
			Err(_) => Pairing.ceremony_failed(state, "This browser made or used no passkey. Try again.")
		}
	}

	## The daemon's answer to the passkey of the ceremony numbered `serial`:
	## signed in, the manifest is asked for again; one more made, the
	## passkeys are listed again; else why not.
	finished : Model.State, U64, Try(Str, Engine.HttpError) -> Model.State
	finished = |state, serial, res| {
		ceremony = state.pairing.ceremony
		done = { ..ceremony, busy: Bool.False, options: "", failed: "" }
		match res {
			_ if serial != ceremony.serial => state
			Ok(_) if ceremony.purpose == Register => { ..state, pairing: { ..state.pairing, ceremony: done, listings: state.pairing.listings + 1 }, notice: "This browser has a passkey now." }
			Ok(_) => { ..state, pairing: { ..state.pairing, ceremony: done, unpaired: Bool.False, code: "", paired: state.pairing.paired + 1 } }
			Err(error) => Pairing.ceremony_failed({ ..state, pairing: { ..state.pairing, ceremony: { ..ceremony, options: "" } } }, Pairing.refusal(ceremony.purpose, error))
		}
	}

	## The passkeys the daemon listed, or the sign-in screen if it refuses.
	passkeys_listed : Model.State, Try(Str, Engine.HttpError) -> Model.State
	passkeys_listed = |state, res| {
		decoded : Try({ passkeys : List(Model.Passkey), rp_id : Str }, _)
		decoded = Json.parse(res ?? "")
		match (res, decoded) {
			(Err(Status(401)), _) => Pairing.refused(state)
			(_, Ok({ passkeys, rp_id })) => { ..state, pairing: { ..state.pairing, passkeys, rp_id } }
			_ => state
		}
	}

	## Deletes passkey `id`, shown as deleting at once.
	delete : Model.State, Str -> Model.State
	delete = |state, id|
		if (state.pairing.deleting.contains(id)) state else { ..state, pairing: { ..state.pairing, deleting: state.pairing.deleting.append(id), delete: { serial: state.pairing.delete.serial + 1, id } } }

	## The daemon's answer to deleting passkey `id`: gone, and this browser
	## signed out if it signed in with it; else back, with why.
	deleted : Model.State, Str, Try(Str, Engine.HttpError) -> Model.State
	deleted = |state, id, res| {
		pairing = { ..state.pairing, deleting: state.pairing.deleting.drop_if(|deleting| deleting == id) }
		current = state.pairing.passkeys.any(|passkey| passkey.id == id and passkey.current)
		match res {
			Ok(_) if current => Pairing.refused({ ..state, pairing, show_settings: Bool.False })
			Ok(_) => { ..state, pairing: { ..pairing, passkeys: pairing.passkeys.drop_if(|passkey| passkey.id == id), listings: pairing.listings + 1 } }
			Err(Status(401)) => Pairing.refused({ ..state, pairing })
			Err(_) => { ..state, pairing, notice: "Couldn't delete ${state.pairing.passkeys.find_first(|passkey| passkey.id == id).map_ok(|passkey| passkey.name) ?? "the passkey"}: the daemon didn't answer." }
		}
	}

	## Signs this browser out, shown signed out at once.
	sign_out : Model.State -> Model.State
	sign_out = |state| Pairing.refused({ ..state, show_settings: Bool.False, pairing: { ..state.pairing, logout: state.pairing.logout + 1 } })

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
	make_code = |state| { ..state, pairing: { ..state.pairing, offer: { serial: state.pairing.offer.serial + 1, asking: Bool.True, code: "", link: "" } } }

	## The code the daemon made for another device.
	code_made : Model.State, U64, Try(Str, Engine.HttpError) -> Model.State
	code_made = |state, serial, res| {
		decoded : Try({ code : Str, link : Str }, _)
		decoded = Json.parse(res ?? "")
		offer = state.pairing.offer
		match decoded {
			_ if serial != offer.serial => state
			Ok({ code, link }) => { ..state, pairing: { ..state.pairing, offer: { ..offer, asking: Bool.False, code, link } } }
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

	## What the browser shows in place of the UI while it isn't signed in:
	## signing in with a passkey, or making the one a link's pairing code or
	## invite grants, with the owner's name if they have none; and a box for
	## a pairing code, which pairs this browser as it is.
	screen : State(ctx, Model.State) -> Elem(ctx)
	screen = |model| {
		ceremony = model.signal().map(|state| state.pairing.ceremony)
		granted = ceremony.map(|shown| shown.purpose != SignIn and shown.purpose != Register)
		Engine.when(
			model.signal().map(|state| state.pairing.unpaired),
			||
				Html.div(
					"pair-screen",
					[
						Html.form(
							"Sign in",
							[Engine.class("pair-card"), Engine.on("submit", model.update(|state| Pairing.clicked(state, Pairing.wanted(state.pairing.ceremony))))],
							[
								Html.h2_s(
									ceremony.map(
										|shown| match shown.purpose {
											Pair(_) => "Make your passkey"
											Invite(_) if shown.invited != "" => "Join as ${shown.invited}"
											Invite(_) => "Join liton"
											_ => "Sign in"
										},
									),
									[],
								),
								Html.p_s(granted.map(|making| if (making) "A passkey signs you in on this device, with its fingerprint, face or PIN, and on your others where it syncs." else "Sign in with a passkey of this box, from this device, or your phone by its QR code."), [Engine.class("help")]),
								Engine.when(ceremony.map(|shown| shown.unnamed), || Html.text_input(Engine.const("Your name"), "text", ceremony.map(|shown| shown.person_name), [Engine.attr("autocomplete", "name")], model.set_value(|state, person_name| { ..state, pairing: { ..state.pairing, ceremony: { ..state.pairing.ceremony, person_name } } })), || Engine.text("")),
								Html.action_button(
									ceremony.map(
										|shown| match (shown.busy, shown.purpose) {
											(Bool.True, SignIn) => "Signing in…"
											(Bool.True, _) => "Making a passkey…"
											(Bool.False, SignIn) | (Bool.False, Register) => "Sign in with a passkey"
											_ => "Make a passkey"
										},
									),
									ceremony.map(|shown| shown.busy),
									[Engine.attr("type", "submit"), Engine.class("primary")],
									model.update(|state| Pairing.clicked(state, Pairing.wanted(state.pairing.ceremony))),
								),
								Html.p_s(ceremony.map(|shown| shown.failed), [Engine.class("pair-failed"), Engine.attr("role", "alert"), Engine.test_id("passkey-failed")]),
							],
						),
						Html.form(
							"Pair this browser",
							[Engine.class("pair-card"), Engine.on("submit", model.update(Pairing.send))],
							[
								Html.h2("Pair this browser", ""),
								Html.p("Or pair it with a code: run liton pair on the daemon's machine, or Add a device in Settings → Passkeys & devices on one signed in.", "help"),
								Html.text_input(Engine.const("Pairing code"), "text", model.signal().map(|state| state.pairing.code), [Engine.attr("placeholder", "ABCD-EFGH"), Engine.attr("autocomplete", "one-time-code"), Engine.attr("autocapitalize", "characters"), Engine.attr("spellcheck", "false"), Engine.class("pair-code")], model.set_value(|state, code| { ..state, pairing: { ..state.pairing, code } })),
								Html.action_button(model.signal().map(|state| if (state.pairing.sending) "Pairing…" else "Pair"), model.signal().map(|state| state.pairing.sending), [Engine.attr("type", "submit")], model.update(Pairing.send)),
								Html.p_s(model.signal().map(|state| state.pairing.failed), [Engine.class("pair-failed"), Engine.attr("role", "alert"), Engine.test_id("pair-failed")]),
							],
						),
					],
				),
			|| Engine.text(""),
		)
	}

	## A notice of each device signed in as this person since this browser
	## was, within a day, until they say it was them, or sign it out.
	sign_ins : State(ctx, Model.State) -> Elem(ctx)
	sign_ins = |model|
		Html.div(
			"sign-in-notices",
			[
				Engine.each(
					model.signal().map(|state| state.sign_ins.drop_if(|sign_in| state.sign_ins_seen.contains(sign_in.id))),
					|sign_in| sign_in.id,
					|row|
						Html.div(
							"sign-in-notice",
							[
								Html.p_s(row.field(|sign_in| "New sign-in: ${sign_in.name}. Not you?"), [Engine.attr("role", "status")]),
								Html.button_s(row.field(|sign_in| "Sign out ${sign_in.name}"), [], model.lift_row().update_by(row.key(), |state, id| Pairing.revoke({ ..state, sign_ins_seen: state.sign_ins_seen.append(id) }, id))),
								Html.button_s(row.field(|_| "It was me"), [Html.aria_label_s(row.field(|sign_in| "It was me on ${sign_in.name}"))], model.lift_row().update_by(row.key(), |state, id| { ..state, sign_ins_seen: state.sign_ins_seen.append(id) })),
							],
						),
				),
			],
		)

	## What the sign-in screen's button is for: the passkey a code or an
	## invite grants, else signing in.
	wanted : Model.Ceremony -> Model.Purpose
	wanted = |ceremony|
		match ceremony.purpose {
			Pair(_) | Invite(_) => ceremony.purpose
			_ => SignIn
		}

	## Settings' Passkeys & devices: the passkeys of the person signed in,
	## each to delete, and one to make on this device; a code for another
	## device; and their devices, each to sign out, this one too.
	section : State(ctx, Model.State) -> Elem(ctx)
	section = |model| {
		offer = model.signal().map(|state| state.pairing.offer)
		ceremony = model.signal().map(|state| state.pairing.ceremony)
		Html.div(
			"settings-section",
			[
				Html.div(
					"settings-card-group",
					[
						Html.h3("Passkeys", ""),
						Html.div(
							"settings-card",
							[
								Engine.each(
									model.signal().map(|state| state.pairing.passkeys),
									|passkey| passkey.id,
									|row|
										Html.div(
											"settings-row device-row",
											[
												Html.div(
													"device-text",
													[
														Html.span_s(row.field(|passkey| if (passkey.current) "${passkey.name} · this browser" else passkey.name), [Engine.class("settings-row-title")]),
														Html.p_s(row.field(|passkey| passkey).map2(model.signal().lift_row(), |passkey, state| Str.join_with((if (state.now == 0) [] else ["made ${Pairing.since(state, passkey.created_at)}"]).concat(if (passkey.used_at == 0 or state.now == 0) [] else ["last used ${Pairing.since(state, passkey.used_at)}"]).concat(if (passkey.backed_up) ["synced"] else []).concat(if (passkey.rp_id != state.pairing.rp_id) ["for ${passkey.rp_id}"] else []), ", ")), [Engine.class("help")]),
													],
												),
												Html.action_button(
													row.key().map2(model.signal().lift_row(), |id, state| if (state.pairing.deleting.contains(id)) "Deleting…" else "Delete"),
													row.key().map2(model.signal().lift_row(), |id, state| state.pairing.deleting.contains(id)),
													[Html.aria_label_s(row.field(|passkey| "Delete the passkey ${passkey.name}"))],
													model.lift_row().update_by(row.key(), Pairing.delete),
												),
											],
										),
								),
								Html.div(
									"settings-row",
									[
										Html.action_button(ceremony.map(|shown| if (shown.busy and shown.purpose == Register) "Making a passkey…" else "Make a passkey on this device"), ceremony.map(|shown| shown.busy), [], model.update(|state| Pairing.started(state, Register))),
										Html.p_s(ceremony.map(|shown| if (shown.purpose == Register) shown.failed else ""), [Engine.class("help"), Engine.attr("role", "alert"), Engine.test_id("passkey-failed")]),
									],
								),
							],
						),
					],
				),
				Html.div(
					"settings-card-group",
					[
						Html.h3("Add a device", ""),
						Html.div(
							"settings-card",
							[
								Html.div(
									"settings-row",
									[
										Html.action_button(offer.map(|asked| if (asked.asking) "Making a code…" else if (asked.code.is_empty()) "Add a device" else "Make another code"), offer.map(|asked| asked.asking), [], model.update(Pairing.make_code)),
										Html.p("A code adds one device of yours, once, within 10 minutes: open the link there to make a passkey on it, or enter the code on its sign-in screen.", "help"),
									],
								),
								Engine.when(
									offer.map(|asked| !asked.code.is_empty()),
									||
										Html.div(
											"settings-row pair-offer",
											[
												Html.span_s(offer.map(|asked| asked.code), [Engine.class("pair-offered-code"), Engine.test_id("pair-offered-code")]),
												Html.p_s(offer.map(|asked| asked.link), [Engine.class("help pair-link"), Engine.test_id("pair-link")]),
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
						Html.h3("Devices", ""),
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
														Html.p_s(row.field(|device| device).map2(model.signal().lift_row(), |device, state| "Signed in ${Pairing.since(state, device.created_at)}, last seen ${Pairing.since(state, device.seen_at)}"), [Engine.class("help")]),
													],
												),
												Html.action_button(
													row.key().map2(model.signal().lift_row(), |id, state| if (state.pairing.revoking.contains(id)) "Signing out…" else "Sign out"),
													row.key().map2(model.signal().lift_row(), |id, state| state.pairing.revoking.contains(id)),
													[Html.aria_label_s(row.field(|device| "Sign out ${device.name}"))],
													model.lift_row().update_by(row.key(), Pairing.revoke),
												),
											],
										),
								),
								Engine.when(model.signal().map(|state| state.pairing.devices.is_empty()), || Html.div("settings-row", [Html.p("No device is signed in: this daemon answers this browser without signing in, as it listens on this machine alone.", "help")]), || Html.div("settings-row", [Html.button("Sign out of this browser", [], model.update(Pairing.sign_out))])),
							],
						),
					],
				),
			],
		)
	}

	## The requests: a passkey's challenge, the browser asked for the passkey
	## and its answer sent; the devices and passkeys while Settings shows
	## them, a code for another device, each revocation and deletion, and
	## signing out.
	effects : State(ctx, Model.State) -> List(Elem(ctx))
	effects = |model| [
		Engine.watch_changes(
			model.signal().map(|state| state.pairing.ceremony.begin),
			|{ route, body, .. }| [Engine.http_body({ method: "POST", url: route, headers: [("Content-Type", "application/json")], body, timeout: Ms(10000) })],
			model.on_result(|state, { ceremony, .. }, res| Pairing.challenged(state, ceremony, res)),
		),
		Engine.watch_changes(
			model.signal().map(|state| state.pairing.ceremony.ask),
			|{ create, options, name, person_name, .. }| [Ports.passkey.ask({ create, options, name, person_name })],
			model.on_result(|state, { ceremony, .. }, res| Pairing.browser_answered(state, ceremony, res)),
		),
		Engine.watch_changes(
			model.signal().map(|state| state.pairing.ceremony.finish),
			|{ route, body, .. }| [Engine.http_body({ method: "POST", url: route, headers: [("Content-Type", "application/json")], body, timeout: Ms(10000) })],
			model.on_result(|state, { ceremony, .. }, res| Pairing.finished(state, ceremony, res)),
		),
		Engine.watch(
			model.signal().map(|state| if (state.show_settings and state.settings_page.section == "devices" and !state.pairing.unpaired) Listing(state.pairing.listings) else NotListing),
			|listing|
				match listing {
					Listing(_) => [Engine.http_body({ url: "/liton/v1/passkeys", timeout: Ms(5000) })]
					NotListing => []
				},
			model.on_result(|state, _, res| Pairing.passkeys_listed(state, res)),
		),
		Engine.watch_changes(
			model.signal().map(|state| state.pairing.delete),
			|{ id, .. }| [Engine.http_body({ method: "POST", url: "/liton/v1/passkeys/delete", headers: [("Content-Type", "application/json")], body: Json.to_str({ id: id }), timeout: Ms(5000) })],
			model.on_result(|state, { id, .. }, res| Pairing.deleted(state, id, res)),
		),
		Engine.watch_changes(
			model.signal().map(|state| state.pairing.logout),
			|_| [Engine.http_body({ method: "POST", url: "/liton/v1/logout", headers: [("Content-Type", "application/json")], body: "{}", timeout: Ms(5000) })],
			Engine.ignore({}),
		),
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
					body: Json.to_str({ id: id }),
					timeout: Ms(5000),
				}),
			],
			model.on_result(|state, { id, .. }, res| Pairing.revoked(state, id, res)),
		),
	]
}

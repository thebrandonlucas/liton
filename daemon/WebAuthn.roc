import Sha256

## Passkeys (WebAuthn Level 3), as the daemon registers and signs people in
## with them: whether a browser's client data and authenticator data answer
## the challenge the daemon set, on its own site, with a person present and
## verified. There is no CBOR: the browser sends the public key as SPKI
## (`getPublicKey()`), and attestation is `none`. Signatures are checked by
## liton-verify, given `signed_message` and the raw key as hex.
WebAuthn := [].{

	## What authenticator data says: the SHA-256 of the site's id, its flags
	## (UP, UV, BE, BS) and the signature counter.
	AuthData : { rp_id_hash : List(U8), user_present : Bool, user_verified : Bool, backup_eligible : Bool, backed_up : Bool, sign_count : U32 }

	## What the client data and authenticator data must say: `type`,
	## `webauthn.create` to register or `webauthn.get` to sign in, the
	## challenge as base64url, the page's origin and the site's id, such as
	## `localhost` or `box.example.ts.net`.
	Expected : { type : Str, challenge : Str, origin : Str, rp_id : Str }

	## The symbols of base64url.
	base64url_symbols : List(U8)
	base64url_symbols = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".to_utf8()

	## `bytes` as base64url, without padding.
	base64url : List(U8) -> Str
	base64url = |bytes| {
		var $symbols = []
		var $start = 0
		while $start < bytes.len() {
			group = bytes.sublist({ start: $start, len: 3 })
			at = |index| (group.get(index) ?? 0).to_u32()
			value = at(0) * 65536 + at(1) * 256 + at(2)
			$symbols = $symbols.concat([262144, 4096, 64, 1].map(|power| WebAuthn.base64url_symbols.get(((value // power) % 64).to_u64()) ?? 'A').take_first(group.len() + 1))
			$start = $start + 3
		}
		Str.from_utf8_lossy($symbols)
	}

	## The bytes base64url `text`, without padding, holds.
	from_base64url : Str -> Try(List(U8), [Invalid])
	from_base64url = |text| {
		values = text.to_utf8().map(|symbol| WebAuthn.base64url_symbols.find_first_index(|known| known == symbol) ?? 64)
		if (values.contains(64) or values.len() % 4 == 1) Err(Invalid) else {
			var $bytes = []
			var $start = 0
			while $start < values.len() {
				group = values.sublist({ start: $start, len: 4 })
				at = |index| group.get(index) ?? 0
				value = at(0) * 262144 + at(1) * 4096 + at(2) * 64 + at(3)
				$bytes = $bytes.concat([65536, 256, 1].map(|power| ((value // power) % 256).to_u8_wrap()).take_first(group.len() - 1))
				$start = $start + 4
			}
			Ok($bytes)
		}
	}

	## `bytes` as lowercase hex.
	hex : List(U8) -> Str
	hex = |bytes| {
		digits = "0123456789abcdef".to_utf8()
		Str.from_utf8_lossy(bytes.fold([], |so_far, byte| so_far.append(digits.get((byte // 16).to_u64()) ?? '0').append(digits.get((byte % 16).to_u64()) ?? '0')))
	}

	## What authenticator data says: the site id's hash in its first 32
	## bytes, the flags in the next and the counter, big-endian, in 4 more.
	auth_data : List(U8) -> Try(AuthData, [Invalid])
	auth_data = |bytes| {
		at = |index| bytes.get(index) ?? 0
		flag = |bit| at(32).bitwise_and(bit) != 0
		if (bytes.len() < 37) Err(Invalid) else Ok({ rp_id_hash: bytes.take_first(32), user_present: flag(0x01), user_verified: flag(0x04), backup_eligible: flag(0x08), backed_up: flag(0x10), sign_count: [33, 34, 35, 36].fold(0, |so_far, index| so_far * 256 + at(index).to_u32()) })
	}

	## The raw public key in `spki` for algorithm `alg`: for ES256 (-7) the
	## uncompressed P-256 point, 04‖x‖y, and for EdDSA (-8) the 32 bytes of
	## the Ed25519 key, after the fixed DER that begins each.
	public_key : I64, List(U8) -> Try(List(U8), [Unsupported])
	public_key = |alg, spki| {
		(prefix, key_length) =
			match alg {
				-7 => ([0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00], 65)
				-8 => ([0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00], 32)
				_ => ([], 0)
			}
		key = spki.drop_first(prefix.len())
		if (key_length > 0 and spki.starts_with(prefix) and key.len() == key_length) Ok(key) else Err(Unsupported)
	}

	## The authenticator data, if the client data and it say what `expected`
	## does, with a person present and verified; else why not, for a person.
	checked : Expected, List(U8), List(U8) -> Try(AuthData, Str)
	checked = |expected, client_data_json, authenticator_data| {
		client_data : Try({ type : Str, challenge : Str, origin : Str }, _)
		client_data = Json.parse(Str.from_utf8_lossy(client_data_json))
		match (client_data, WebAuthn.auth_data(authenticator_data)) {
			(Err(_), _) => Err("the browser's answer could not be read")
			(_, Err(_)) => Err("the passkey's answer could not be read")
			(Ok(said), _) if said.type != expected.type => Err("the passkey answered another request")
			(Ok(said), _) if said.challenge != expected.challenge => Err("the passkey answered an old request; try again")
			(Ok(said), _) if said.origin != expected.origin => Err("the passkey was used on ${said.origin}, not ${expected.origin}")
			(_, Ok(data)) if data.rp_id_hash != Sha256.digest_bytes(expected.rp_id.to_utf8()) => Err("this passkey is for another site")
			(_, Ok(data)) if !data.user_present => Err("the passkey didn't confirm someone was there")
			(_, Ok(data)) if !data.user_verified => Err("the passkey didn't check who you are with a PIN, fingerprint or face")
			(_, Ok(data)) => Ok(data)
		}
	}

	## Whether a signature counter of `given` follows `stored`: it grew, or
	## both are 0, as a synced passkey's are.
	counted : U32, U32 -> Bool
	counted = |stored, given| given > stored or (stored == 0 and given == 0)

	## What a passkey signs: its authenticator data, then the SHA-256 of the
	## client data.
	signed_message : List(U8), List(U8) -> List(U8)
	signed_message = |authenticator_data, client_data_json| authenticator_data.concat(Sha256.digest_bytes(client_data_json))
}

# Recorded from Chrome 156's virtual authenticator (ctap2, internal, user
# verified) on http://localhost:43979: an ES256 passkey registered with the
# challenge 0..31 and used with 32..63, and an EdDSA one used likewise.
# Node's crypto verifies both signatures over `signed_message`.
recorded = {
	origin: "http://localhost:43979",
	registration_challenge: "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8",
	login_challenge: "ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8",
	es256_registration_client_data: "eyJ0eXBlIjoid2ViYXV0aG4uY3JlYXRlIiwiY2hhbGxlbmdlIjoiQUFFQ0F3UUZCZ2NJQ1FvTERBME9EeEFSRWhNVUZSWVhHQmthR3h3ZEhoOCIsIm9yaWdpbiI6Imh0dHA6Ly9sb2NhbGhvc3Q6NDM5NzkiLCJjcm9zc09yaWdpbiI6ZmFsc2V9",
	es256_registration_authenticator_data: "SZYN5YgOjGh0NBcPZHZgW4_krrmihjLHmVzzuoMdl2NFAAAAAQECAwQFBgcIAQIDBAUGBwgAIF8MpVgH_FWQWm5D2EXyy7tq4r7T9S80Oj98zDmpiySbpQECAyYgASFYIArGDYn4R5dFYDn-2nqdlL8XpVoLYHpZhfAsKt1lJD5eIlgg5VlUdl3rb8hWnetWiwNs9iUDLAmr5jBVwr-aX5uE-rw",
	es256_public_key: "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAECsYNifhHl0VgOf7aep2UvxelWgtgelmF8Cwq3WUkPl7lWVR2XetvyFad61aLA2z2JQMsCavmMFXCv5pfm4T6vA",
	es256_login_client_data: "eyJ0eXBlIjoid2ViYXV0aG4uZ2V0IiwiY2hhbGxlbmdlIjoiSUNFaUl5UWxKaWNvS1NvckxDMHVMekF4TWpNME5UWTNPRGs2T3p3OVBqOCIsIm9yaWdpbiI6Imh0dHA6Ly9sb2NhbGhvc3Q6NDM5NzkiLCJjcm9zc09yaWdpbiI6ZmFsc2V9",
	es256_login_authenticator_data: "SZYN5YgOjGh0NBcPZHZgW4_krrmihjLHmVzzuoMdl2MFAAAAAg",
	eddsa_public_key: "MCowBQYDK2VwAyEAkE5IOtnhPUBn335roJpPZmQCO0GyZ9fTn0MvtkPhdOM",
	eddsa_login_client_data: "eyJ0eXBlIjoid2ViYXV0aG4uZ2V0IiwiY2hhbGxlbmdlIjoiSUNFaUl5UWxKaWNvS1NvckxDMHVMekF4TWpNME5UWTNPRGs2T3p3OVBqOCIsIm9yaWdpbiI6Imh0dHA6Ly9sb2NhbGhvc3Q6NDM5NzkiLCJjcm9zc09yaWdpbiI6ZmFsc2UsIm90aGVyX2tleXNfY2FuX2JlX2FkZGVkX2hlcmUiOiJkbyBub3QgY29tcGFyZSBjbGllbnREYXRhSlNPTiBhZ2FpbnN0IGEgdGVtcGxhdGUuIFNlZSBodHRwczovL2dvby5nbC95YWJQZXgifQ",
	eddsa_login_authenticator_data: "SZYN5YgOjGh0NBcPZHZgW4_krrmihjLHmVzzuoMdl2MFAAAAAg",
}

decoded = |text| WebAuthn.from_base64url(text) ?? []

registering = { type: "webauthn.create", challenge: recorded.registration_challenge, origin: recorded.origin, rp_id: "localhost" }

signing_in = { type: "webauthn.get", challenge: recorded.login_challenge, origin: recorded.origin, rp_id: "localhost" }

login_client_data = decoded(recorded.es256_login_client_data)

login_authenticator_data = decoded(recorded.es256_login_authenticator_data)

expect {
	counting = List.repeat(0, 64).map_with_index(|_, at| at.to_u8_wrap())
	WebAuthn.base64url(counting.take_first(32)) == recorded.registration_challenge and WebAuthn.from_base64url(recorded.login_challenge) == Ok(counting.drop_first(32))
}
expect WebAuthn.base64url([0xfb, 0xff]) == "-_8" and WebAuthn.from_base64url("-_8") == Ok([0xfb, 0xff]) and WebAuthn.from_base64url("-_8=") == Err(Invalid) and WebAuthn.from_base64url("A") == Err(Invalid)
expect WebAuthn.hex([0x00, 0x0f, 0xab, 0xff]) == "000fabff"
expect WebAuthn.checked(registering, decoded(recorded.es256_registration_client_data), decoded(recorded.es256_registration_authenticator_data)) == Ok({ rp_id_hash: Sha256.digest_bytes("localhost".to_utf8()), user_present: Bool.True, user_verified: Bool.True, backup_eligible: Bool.False, backed_up: Bool.False, sign_count: 1 })
expect WebAuthn.checked(signing_in, login_client_data, login_authenticator_data).map_ok(|data| data.sign_count) == Ok(2)
expect WebAuthn.checked(signing_in, decoded(recorded.eddsa_login_client_data), decoded(recorded.eddsa_login_authenticator_data)).is_ok()
expect WebAuthn.checked({ ..signing_in, challenge: recorded.registration_challenge }, login_client_data, login_authenticator_data) == Err("the passkey answered an old request; try again")
expect WebAuthn.checked({ ..signing_in, origin: "https://box.example.ts.net" }, login_client_data, login_authenticator_data) == Err("the passkey was used on http://localhost:43979, not https://box.example.ts.net")
expect WebAuthn.checked(registering, login_client_data, login_authenticator_data) == Err("the passkey answered another request")
expect WebAuthn.checked({ ..signing_in, rp_id: "box.example.ts.net" }, login_client_data, login_authenticator_data) == Err("this passkey is for another site")
expect WebAuthn.checked(signing_in, login_client_data, login_authenticator_data.set(32, 0x01) ?? []) == Err("the passkey didn't check who you are with a PIN, fingerprint or face")
expect WebAuthn.checked(signing_in, login_client_data, login_authenticator_data.set(32, 0x04) ?? []) == Err("the passkey didn't confirm someone was there")
expect WebAuthn.auth_data(login_authenticator_data.set(32, 0x1d) ?? []).map_ok(|data| (data.backup_eligible, data.backed_up)) == Ok((Bool.True, Bool.True)) and WebAuthn.auth_data([0x49]) == Err(Invalid)
expect WebAuthn.counted(1, 2) and !WebAuthn.counted(2, 2) and !WebAuthn.counted(2, 1) and WebAuthn.counted(0, 0) and !WebAuthn.counted(1, 0)
expect WebAuthn.public_key(-7, decoded(recorded.es256_public_key)).map_ok(WebAuthn.hex) == Ok("040ac60d89f84797456039feda7a9d94bf17a55a0b607a5985f02c2add65243e5ee55954765deb6fc8569deb568b036cf625032c09abe63055c2bf9a5f9b84fabc")
expect WebAuthn.public_key(-8, decoded(recorded.eddsa_public_key)).map_ok(WebAuthn.hex) == Ok("904e483ad9e13d4067df7e6ba09a4f6664023b41b267d7d39f432fb643e174e3")
expect WebAuthn.public_key(-8, decoded(recorded.es256_public_key)) == Err(Unsupported) and WebAuthn.public_key(-257, decoded(recorded.es256_public_key)) == Err(Unsupported) and WebAuthn.public_key(-7, decoded(recorded.es256_public_key).drop_last(1)) == Err(Unsupported)
expect WebAuthn.hex(WebAuthn.signed_message(login_authenticator_data, login_client_data)) == "49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d97630500000002175215810274e114cd6a1b54c847068d1ac2797344c704d71cbde423bda34f93"
expect WebAuthn.hex(WebAuthn.signed_message(decoded(recorded.eddsa_login_authenticator_data), decoded(recorded.eddsa_login_client_data))) == "49960de5880e8c687434170f6476605b8fe4aeb9a28632c7995cf3ba831d976305000000029e7b35a8f879040a7e1e19e5f4006e0ec9aafd216fea23204c26db3df2226045"

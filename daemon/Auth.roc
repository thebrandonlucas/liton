## How the daemon tells a paired device's request from any other: pure
## parts of client authentication (docs/protocol.md, Authentication).
##
## A device pairs with a pairing code and gets a token, `<id>.<secret>`: its
## id names the device, and its secret, 256 random bits as hex, proves it.
## The daemon keeps only the secret's SHA-256.
Auth := [].{

	## When a request must come from a paired device: `Required` always,
	## `Off` never, and `Loopback` unless the daemon listens on loopback alone
	## and the request was forwarded by no proxy.
	Mode : [Required, Loopback, Off]

	## The mode LITON_AUTH names: `on` (or nothing), `required` or `off`, for
	## a daemon listening on `host`. `on` requires a token unless the daemon
	## listens only on loopback, where only this machine reaches it.
	mode : Str, Str -> Try(Mode, Str)
	mode = |named, host|
		match named.trim().with_ascii_lowercased() {
			"" | "on" => Ok(if (["127.0.0.1", "::1", "[::1]", "localhost"].contains(host)) Loopback else Required)
			"required" => Ok(Required)
			"off" => Ok(Off)
			other => Err("LITON_AUTH is on, required or off, not ${other}")
		}

	## The name of the cookie a browser keeps its token in.
	cookie_name : Str
	cookie_name = "liton_token"

	## Whether a request must show a token: under `Loopback`, one a proxy
	## forwarded must, as the proxy may be reached from anywhere.
	required : Mode, List({ name : Str, value : Str }) -> Bool
	required = |given, headers|
		match given {
			Required => Bool.True
			Off => Bool.False
			Loopback => headers.any(|field| ["Forwarded", "X-Forwarded-For", "X-Forwarded-Host", "X-Forwarded-Proto", "X-Real-IP"].any(|name| field.name.caseless_ascii_equals(name)))
		}

	## The token a request shows: its `Authorization: Bearer` one, else its
	## cookie's.
	credential : List({ name : Str, value : Str }) -> Try({ id : Str, secret : Str }, [Missing])
	credential = |headers| {
		values = |name| headers.keep_if(|field| field.name.caseless_ascii_equals(name)).map(|field| field.value.trim())
		bearer = values("Authorization").keep_if(|value| value.with_ascii_lowercased().starts_with("bearer ")).map(|value| Str.from_utf8_lossy(value.to_utf8().drop_first(7)).trim())
		cookies = values("Cookie").fold([], |so_far, value| so_far.concat(value.split_on(";"))).map(|pair| pair.trim()).keep_if(|pair| pair.starts_with("${Auth.cookie_name}=")).map(|pair| pair.drop_prefix("${Auth.cookie_name}="))
		match bearer.concat(cookies).first() {
			Ok(token) =>
				match token.split_first(".") {
					Ok({ before, after }) => Ok({ id: before, secret: after })
					Err(_) => Err(Missing)
				}
			Err(_) => Err(Missing)
		}
	}

	## Whether `given` and `kept` are equal, in a time that depends on their
	## lengths alone, so how long a refusal takes tells nothing of `kept`.
	same : Str, Str -> Bool
	same = |given, kept| {
		(a, b) = (given.to_utf8(), kept.to_utf8())
		a.len() == b.len() and a.map2(b, |x, y| x.bitwise_xor(y)).fold(0, |so_far, byte| so_far.bitwise_or(byte)) == 0
	}

	## The Set-Cookie value holding `token`, kept 400 days, sent to this
	## daemon alone and by no other site's page, and only over HTTPS when
	## the request came over it.
	cookie : Str, Bool -> Str
	cookie = |token, over_https| "${Auth.cookie_name}=${token}; Path=/; Max-Age=34560000; HttpOnly; SameSite=Strict${if (over_https) "; Secure" else ""}"

	## The Set-Cookie value that removes the token.
	cleared_cookie : Str
	cleared_cookie = "${Auth.cookie_name}=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict"

	## Whether the request came over HTTPS, as a proxy before the daemon says.
	secure : List({ name : Str, value : Str }) -> Bool
	secure = |headers|
		headers.any(
			|field|
				(field.name.caseless_ascii_equals("X-Forwarded-Proto") and field.value.trim().caseless_ascii_equals("https"))
					or (field.name.caseless_ascii_equals("Forwarded") and field.value.with_ascii_lowercased().contains("proto=https")),
		)

	## The symbols of a pairing code: 32, so a random byte picks one evenly,
	## without I, O, 0 or 1, which read alike.
	code_symbols : List(U8)
	code_symbols = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".to_utf8()

	## A pairing code of `random` bytes, written as `ABCD-EFGH`.
	code : List(U8) -> Str
	code = |random| {
		symbols = random.map(|byte| Auth.code_symbols.get((byte % 32).to_u64()) ?? 'A')
		Str.from_utf8_lossy(symbols.sublist({ start: 0, len: 4 }).append('-').concat(symbols.sublist({ start: 4, len: 4 })))
	}

	## A code as typed, in the form `code` writes: upper case, the dash put
	## back wherever it was left out or spaces were typed instead.
	typed_code : Str -> Str
	typed_code = |typed| {
		symbols = typed.to_utf8().map(|byte| if (byte >= 'a' and byte <= 'z') byte - 32 else byte).keep_if(|byte| byte != '-' and byte != ' ')
		if (symbols.len() == 8) Str.from_utf8_lossy(symbols.sublist({ start: 0, len: 4 }).append('-').concat(symbols.sublist({ start: 4, len: 4 }))) else Str.from_utf8_lossy(symbols)
	}
}

expect Auth.mode("", "127.0.0.1") == Ok(Loopback) and Auth.mode("on", "0.0.0.0") == Ok(Required) and Auth.mode("required", "127.0.0.1") == Ok(Required) and Auth.mode("OFF", "0.0.0.0") == Ok(Off) and Auth.mode("maybe", "::1").is_err()
expect Auth.required(Loopback, [{ name: "Host", value: "x" }]) == Bool.False and Auth.required(Loopback, [{ name: "x-forwarded-for", value: "1.2.3.4" }]) and Auth.required(Off, [{ name: "Forwarded", value: "for=x" }]) == Bool.False
expect Auth.credential([{ name: "authorization", value: "Bearer abc.def" }]) == Ok({ id: "abc", secret: "def" })
expect Auth.credential([{ name: "Cookie", value: "theme=dark; liton_token=abc.def" }]) == Ok({ id: "abc", secret: "def" })
expect Auth.credential([{ name: "Cookie", value: "liton_tokens=abc.def" }]) == Err(Missing) and Auth.credential([{ name: "Authorization", value: "Basic abc.def" }]) == Err(Missing)
expect Auth.same("abc", "abc") and !Auth.same("abc", "abd") and !Auth.same("abc", "abcd")
expect Auth.secure([{ name: "X-Forwarded-Proto", value: "https" }]) and !Auth.secure([{ name: "X-Forwarded-Proto", value: "http" }])
expect Auth.code([0, 1, 2, 3, 31, 32, 255, 8]) == "ABCD-9A9J"
expect Auth.typed_code("abcd efgh") == "ABCD-EFGH" and Auth.typed_code("ABCD-EFGH") == "ABCD-EFGH"

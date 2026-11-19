## SHA-256 (FIPS 180-4), what the daemon keeps of each device's token in
## place of the token. basic-webserver offers no hash, and Roc's U32 has no
## shifts, so a shift right by n is a division by 2^n.
Sha256 := [].{

	## The digest of `bytes`, as 64 lowercase hex digits.
	hex : List(U8) -> Str
	hex = |bytes| Str.join_with(Sha256.digest(bytes).map(Sha256.word_hex), "")

	## The digest of `bytes`, as eight words.
	digest : List(U8) -> List(U32)
	digest = |bytes| {
		length = bytes.len()
		bits = length * 8
		message = bytes.append(0x80).concat(List.repeat(0, (119 - length % 64) % 64)).concat([72057594037927936, 281474976710656, 1099511627776, 4294967296, 16777216, 65536, 256, 1].map(|power| (bits // power).to_u8_wrap()))
		var $hash = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
		var $start = 0
		while $start < message.len() {
			$hash = Sha256.compressed($hash, message.sublist({ start: $start, len: 64 }))
			$start = $start + 64
		}
		$hash
	}

	## `hash` after one 64-byte block of the padded message.
	compressed : List(U32), List(U8) -> List(U32)
	compressed = |hash, block| {
		byte = |index| (block.get(index) ?? 0).to_u32()
		var $words = []
		var $t = 0
		while $t < 64 {
			word =
				if $t < 16 {
					byte(4 * $t) * 16777216 + byte(4 * $t + 1) * 65536 + byte(4 * $t + 2) * 256 + byte(4 * $t + 3)
				} else {
					before = |back| $words.get($t - back) ?? 0
					sigma0 = Sha256.rotr(before(15), 128).bitwise_xor(Sha256.rotr(before(15), 262144)).bitwise_xor(before(15) // 8)
					sigma1 = Sha256.rotr(before(2), 131072).bitwise_xor(Sha256.rotr(before(2), 524288)).bitwise_xor(before(2) // 1024)
					before(16).plus_wrap(sigma0).plus_wrap(before(7)).plus_wrap(sigma1)
				}
			$words = $words.append(word)
			$t = $t + 1
		}
		var $working = hash
		var $round = 0
		while $round < 64 {
			at = |index| $working.get(index) ?? 0
			(a, b, c, d, e, f, g, h) = (at(0), at(1), at(2), at(3), at(4), at(5), at(6), at(7))
			sum1 = Sha256.rotr(e, 64).bitwise_xor(Sha256.rotr(e, 2048)).bitwise_xor(Sha256.rotr(e, 33554432))
			choice = e.bitwise_and(f).bitwise_xor(e.bitwise_not().bitwise_and(g))
			temp1 = h.plus_wrap(sum1).plus_wrap(choice).plus_wrap(Sha256.rounds.get($round) ?? 0).plus_wrap($words.get($round) ?? 0)
			sum0 = Sha256.rotr(a, 4).bitwise_xor(Sha256.rotr(a, 8192)).bitwise_xor(Sha256.rotr(a, 4194304))
			majority = a.bitwise_and(b).bitwise_xor(a.bitwise_and(c)).bitwise_xor(b.bitwise_and(c))
			temp2 = sum0.plus_wrap(majority)
			$working = [temp1.plus_wrap(temp2), a, b, c, d.plus_wrap(temp1), e, f, g]
			$round = $round + 1
		}
		hash.map2($working, |before, after| before.plus_wrap(after))
	}

	## `word` rotated right by n bits, given 2^n: `word` beside itself,
	## divided by 2^n, then its lower half.
	rotr : U32, U64 -> U32
	rotr = |word, power| ((word.to_u64() * 4294967297) // power).to_u32_wrap()

	## `word` as eight hex digits.
	word_hex : U32 -> Str
	word_hex = |word| {
		digits = "0123456789abcdef".to_utf8()
		nibbles = [268435456, 16777216, 1048576, 65536, 4096, 256, 16, 1].map(|power| digits.get(((word // power) % 16).to_u64()) ?? '0')
		Str.from_utf8_lossy(nibbles)
	}

	## The round constants.
	rounds : List(U32)
	rounds = [
		0x428a2f98,
		0x71374491,
		0xb5c0fbcf,
		0xe9b5dba5,
		0x3956c25b,
		0x59f111f1,
		0x923f82a4,
		0xab1c5ed5,
		0xd807aa98,
		0x12835b01,
		0x243185be,
		0x550c7dc3,
		0x72be5d74,
		0x80deb1fe,
		0x9bdc06a7,
		0xc19bf174,
		0xe49b69c1,
		0xefbe4786,
		0x0fc19dc6,
		0x240ca1cc,
		0x2de92c6f,
		0x4a7484aa,
		0x5cb0a9dc,
		0x76f988da,
		0x983e5152,
		0xa831c66d,
		0xb00327c8,
		0xbf597fc7,
		0xc6e00bf3,
		0xd5a79147,
		0x06ca6351,
		0x14292967,
		0x27b70a85,
		0x2e1b2138,
		0x4d2c6dfc,
		0x53380d13,
		0x650a7354,
		0x766a0abb,
		0x81c2c92e,
		0x92722c85,
		0xa2bfe8a1,
		0xa81a664b,
		0xc24b8b70,
		0xc76c51a3,
		0xd192e819,
		0xd6990624,
		0xf40e3585,
		0x106aa070,
		0x19a4c116,
		0x1e376c08,
		0x2748774c,
		0x34b0bcb5,
		0x391c0cb3,
		0x4ed8aa4a,
		0x5b9cca4f,
		0x682e6ff3,
		0x748f82ee,
		0x78a5636f,
		0x84c87814,
		0x8cc70208,
		0x90befffa,
		0xa4506ceb,
		0xbef9a3f7,
		0xc67178f2,
	]
}

expect Sha256.hex([]) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
expect Sha256.hex("abc".to_utf8()) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
expect Sha256.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".to_utf8()) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"

// Checks a passkey's signature for the daemon, which runs it once per login:
//
//     liton-verify <alg> <public-key-hex> <message-hex> <signature-hex>
//
// alg is the COSE algorithm: -7, ES256, ECDSA on P-256 over the message's
// SHA-256, its key an uncompressed SEC1 point and its signature DER, as
// authenticators produce them, or -8, EdDSA, Ed25519. Exits 0 when the
// signature is valid, 1 when it isn't, malformed key or signature included,
// and 2 on a usage error.
const std = @import("std");

const Ecdsa = std.crypto.sign.ecdsa.EcdsaP256Sha256;
const Ed25519 = std.crypto.sign.Ed25519;

const Algorithm = enum { es256, ed25519 };

const Arguments = struct {
    algorithm: Algorithm,
    public_key: []u8,
    message: []u8,
    signature: []u8,
};

fn parseArguments(allocator: std.mem.Allocator, args: []const [:0]const u8) error{ Usage, OutOfMemory }!Arguments {
    if (args.len != 4) return error.Usage;
    const algorithm: Algorithm = if (std.mem.eql(u8, args[0], "-7")) .es256 else if (std.mem.eql(u8, args[0], "-8")) .ed25519 else return error.Usage;
    var decoded: [3][]u8 = undefined;
    for (args[1..], &decoded) |hex, *bytes| {
        bytes.* = try allocator.alloc(u8, hex.len / 2);
        _ = std.fmt.hexToBytes(bytes.*, hex) catch return error.Usage;
    }
    return .{ .algorithm = algorithm, .public_key = decoded[0], .message = decoded[1], .signature = decoded[2] };
}

fn isValid(arguments: Arguments) bool {
    switch (arguments.algorithm) {
        .es256 => {
            if (arguments.public_key.len != Ecdsa.PublicKey.uncompressed_sec1_encoded_length) return false;
            const public_key = Ecdsa.PublicKey.fromSec1(arguments.public_key) catch return false;
            const signature = Ecdsa.Signature.fromDer(arguments.signature) catch return false;
            signature.verify(arguments.message, public_key) catch return false;
        },
        .ed25519 => {
            if (arguments.public_key.len != Ed25519.PublicKey.encoded_length or arguments.signature.len != Ed25519.Signature.encoded_length) return false;
            const public_key = Ed25519.PublicKey.fromBytes(arguments.public_key[0..Ed25519.PublicKey.encoded_length].*) catch return false;
            const signature = Ed25519.Signature.fromBytes(arguments.signature[0..Ed25519.Signature.encoded_length].*);
            signature.verifyStrict(arguments.message, public_key) catch return false;
        },
    }
    return true;
}

pub fn main(init: std.process.Init.Minimal) u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const args = init.args.toSlice(arena.allocator()) catch return 2;
    const arguments = parseArguments(arena.allocator(), args[1..]) catch {
        std.debug.print("usage: liton-verify <-7|-8> <public-key-hex> <message-hex> <signature-hex>\n", .{});
        return 2;
    };
    return if (isValid(arguments)) 0 else 1;
}

// A test vector's bytes, from well-formed hex.
fn hexBytes(comptime hex: []const u8) [hex.len / 2]u8 {
    var decoded: [hex.len / 2]u8 = undefined;
    _ = std.fmt.hexToBytes(&decoded, hex) catch unreachable;
    return decoded;
}

// Expects the signature valid, and invalid with a bit of the message, the
// signature or the key flipped.
fn expectValidOnlyIntact(algorithm: Algorithm, public_key: []u8, message: []u8, signature: []u8) !void {
    const arguments: Arguments = .{ .algorithm = algorithm, .public_key = public_key, .message = message, .signature = signature };
    try std.testing.expect(isValid(arguments));
    for ([_][]u8{ message, signature, public_key }) |field| {
        if (field.len == 0) continue;
        field[field.len - 1] ^= 1;
        try std.testing.expect(!isValid(arguments));
        field[field.len - 1] ^= 1;
    }
}

test "ES256 verifies RFC 6979 A.2.5's P-256 SHA-256 signatures" {
    var public_key = hexBytes("04" ++
        "60FED4BA255A9D31C961EB74C6356D68C049B8923B61FA6CE669622E60F29FB6" ++
        "7903FE1008B8BC99A41AE9E95628BC64F2F1B20C2D7E9F5177A3C294D4462299");
    var sample = "sample".*;
    const sample_signature = Ecdsa.Signature.fromBytes(hexBytes(
        "EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716" ++
            "F7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8",
    ));
    var sample_der: [Ecdsa.Signature.der_encoded_length_max]u8 = undefined;
    try expectValidOnlyIntact(.es256, &public_key, &sample, sample_signature.toDer(&sample_der));
    var test_message = "test".*;
    var test_der: [Ecdsa.Signature.der_encoded_length_max]u8 = undefined;
    try expectValidOnlyIntact(.es256, &public_key, &test_message, Ecdsa.Signature.fromBytes(hexBytes(
        "F1ABB023518351CD71D881567B1EA663ED3EFCF6C5132B354F28D3B0B7D38367" ++
            "019F4113742A2B14BD25926B49C649155F267E60D3814B4C0CC84250E46F0083",
    )).toDer(&test_der));
    // The raw (r, s) pair, not DER, is malformed.
    var raw = sample_signature.toBytes();
    try std.testing.expect(!isValid(.{ .algorithm = .es256, .public_key = &public_key, .message = &sample, .signature = &raw }));
}

test "EdDSA verifies RFC 8032 7.1's Ed25519 TEST 1, 2 and 3" {
    var test_1_key = hexBytes("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a");
    var test_1_signature = hexBytes("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b");
    try expectValidOnlyIntact(.ed25519, &test_1_key, &.{}, &test_1_signature);
    var test_2_key = hexBytes("3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c");
    var test_2_message = hexBytes("72");
    var test_2_signature = hexBytes("92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00");
    try expectValidOnlyIntact(.ed25519, &test_2_key, &test_2_message, &test_2_signature);
    var test_3_key = hexBytes("fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025");
    var test_3_message = hexBytes("af82");
    var test_3_signature = hexBytes("6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a");
    try expectValidOnlyIntact(.ed25519, &test_3_key, &test_3_message, &test_3_signature);
    // Another key's, and a signature cut short.
    try std.testing.expect(!isValid(.{ .algorithm = .ed25519, .public_key = &test_3_key, .message = &test_2_message, .signature = &test_2_signature }));
    try std.testing.expect(!isValid(.{ .algorithm = .ed25519, .public_key = &test_2_key, .message = &test_2_message, .signature = test_2_signature[0..63] }));
}

test "parseArguments decodes hex, and rejects a wrong count, an unknown alg and malformed hex" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const arguments = try parseArguments(arena.allocator(), &.{ "-8", "00fF", "", "aB" });
    try std.testing.expectEqual(.ed25519, arguments.algorithm);
    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0xff }, arguments.public_key);
    try std.testing.expectEqualSlices(u8, &.{}, arguments.message);
    try std.testing.expectEqualSlices(u8, &.{0xab}, arguments.signature);
    try std.testing.expectEqual(.es256, (try parseArguments(arena.allocator(), &.{ "-7", "", "", "" })).algorithm);
    for ([_][]const [:0]const u8{
        &.{ "-7", "00", "00" },
        &.{ "-7", "00", "00", "00", "00" },
        &.{ "-257", "00", "00", "00" },
        &.{ "7", "00", "00", "00" },
        &.{ "-7", "0g", "00", "00" },
        &.{ "-7", "00", "000", "00" },
    }) |args| try std.testing.expectError(error.Usage, parseArguments(arena.allocator(), args));
}

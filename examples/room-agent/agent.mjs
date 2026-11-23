// An agent's own key in the relay's rooms, for an agent written in any
// language: one key per agent, made here, which only the agent holds.
//
//   node agent.mjs join <invite link> <directory>
//     makes a key, redeems the invite with it (an operator's or admin's
//     `liton invite --role agent --rooms dispatch dispatch-bot`), signs the
//     agent's profile, named as the invite and marked a bot, and writes
//     <directory>/key, the secret key, and <directory>/token, the device's
//     token, readable by their owner alone. Encrypt both as agenix secrets
//     and remove them; the agent reads them where they are mounted.
//   node agent.mjs send <room> <text> [<root>]
//     posts <text> in <room>, or replies in the thread of <root>, signed
//     with LITON_KEY_FILE's key, as the device of LITON_TOKEN_FILE's token,
//     to the daemon at LITON_URL.
//
// It hears its mentions with `LITON_TOKEN=… liton watch rooms.v1 inbox`. A
// leaked key is revoked by removing the agent in Settings → People, which
// takes its role, rooms and device away, then joining a new invite.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { createHash } from "node:crypto";
import { join } from "node:path";
import { etc, schnorr, utils } from "../../ui/secp256k1.mjs";

// A JSON string escaping only what NIP-01 says to.
const escapes = { "\n": "\\n", '"': '\\"', "\\": "\\\\", "\r": "\\r", "\t": "\\t", "\b": "\\b", "\f": "\\f" };
const quoted = (text) => `"${text.replace(/[\n"\\\r\t\b\f]/g, (character) => escapes[character])}"`;

// The event of `kind`, `tags` and `content` by `secret`, made now, with its id and signature.
const signed = async (secret, { kind, tags, content }) => {
  const pubkey = etc.bytesToHex(schnorr.getPublicKey(secret));
  const created_at = Math.floor(Date.now() / 1000);
  const serialized = `[0,${quoted(pubkey)},${created_at},${kind},[${tags.map((tag) => `[${tag.map(quoted).join(",")}]`).join(",")}],${quoted(content)}]`;
  const id = createHash("sha256").update(serialized).digest("hex");
  const sig = etc.bytesToHex(await schnorr.signAsync(etc.hexToBytes(id), secret));
  return { id, pubkey, created_at, kind, tags, content, sig };
};

// The JSON `url` answers `body` with, sent with `token`, or exits saying why not.
const posted = async (url, body, token) => {
  const response = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify(body) });
  const text = await response.text();
  if (!response.ok) failed(`${url} answered ${response.status}: ${text}`);
  return JSON.parse(text);
};

const failed = (why) => {
  console.error(why);
  process.exit(1);
};

const [command, ...rest] = process.argv.slice(2);
if (command === "join" && rest.length === 2) {
  const [link, directory] = rest;
  const invite = new URL(link);
  const secret = new URLSearchParams(invite.hash.slice(1)).get("invite") ?? failed(`${link} is no invite's link`);
  const daemon = invite.origin;
  const key = utils.randomSecretKey();
  const pubkey = etc.bytesToHex(schnorr.getPublicKey(key));
  const { person, token } = await posted(`${daemon}/liton/v1/invite`, { secret, pubkey, token: true });
  const profile = await signed(key, { kind: 0, tags: [], content: JSON.stringify({ name: person.name, bot: true }) });
  const [, , taken, why] = await posted(`${daemon}/liton/v1/nostr/event`, profile, token);
  if (!taken) failed(`the daemon took no profile: ${why}`);
  mkdirSync(directory, { recursive: true });
  writeFileSync(join(directory, "key"), etc.bytesToHex(key), { mode: 0o600, flag: "wx" });
  writeFileSync(join(directory, "token"), token, { mode: 0o600, flag: "wx" });
  console.log(`${person.name} joined ${daemon} as ${person.role}, key ${pubkey}`);
} else if (command === "send" && (rest.length === 2 || rest.length === 3)) {
  const [room, text, root] = rest;
  const read = (name) => readFileSync(process.env[name] ?? failed(`${name} names no file`), "utf8").trim();
  const key = etc.hexToBytes(read("LITON_KEY_FILE"));
  const token = read("LITON_TOKEN_FILE");
  const daemon = (process.env.LITON_URL ?? "http://127.0.0.1:8095").replace(/\/$/, "");
  const event = await signed(key, { kind: 9, tags: [["h", room], ...(root ? [["e", root, "", "root"]] : [])], content: text });
  const place = root ? { Reply: { root, parent: root } } : "TopLevel";
  const answer = await posted(`${daemon}/liton/v1/call`, { capability: "rooms.v1", request: { Send: { room_id: room, text, place, mentions: [] } }, signed: event }, token);
  console.log(JSON.stringify(answer));
  if (!answer.Ok?.Sent) process.exit(1);
} else {
  failed("usage: node agent.mjs join <invite link> <directory> | send <room> <text> [<root>]");
}

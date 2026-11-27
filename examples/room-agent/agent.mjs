// An agent in the box's rooms, for an agent written in any language: it
// joins once with an invite and then speaks with the token that gives it.
//
//   node agent.mjs join <invite link> <file>
//     redeems the invite (an operator's or admin's
//     `liton invite --role agent --rooms dispatch dispatch-bot`) for a token
//     and writes it to <file>, readable by its owner alone. Encrypt it as an
//     agenix secret and remove it; the agent reads it where it is mounted.
//   node agent.mjs send <room> <text> [<root>]
//     posts <text> in <room>, or replies in the thread of <root>, with
//     LITON_TOKEN_FILE's token, to the daemon at LITON_URL.
//
// It hears its mentions with `LITON_TOKEN=… liton watch rooms.v1 inbox`. A
// leaked token is revoked by removing the agent in Settings → People, which
// takes its role, rooms and devices away, then joining a new invite.
import { readFileSync, writeFileSync } from "node:fs";

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
  const [link, file] = rest;
  const invite = new URL(link);
  const secret = new URLSearchParams(invite.hash.slice(1)).get("invite") ?? failed(`${link} is no invite's link`);
  const { person, token } = await posted(`${invite.origin}/liton/v1/invite`, { secret, token: true });
  writeFileSync(file, token, { mode: 0o600, flag: "wx" });
  console.log(`${person.name} joined ${invite.origin} as ${person.role}, person ${person.id}`);
} else if (command === "send" && (rest.length === 2 || rest.length === 3)) {
  const [room, text, root] = rest;
  const token = readFileSync(process.env.LITON_TOKEN_FILE ?? failed("LITON_TOKEN_FILE names no file"), "utf8").trim();
  const daemon = (process.env.LITON_URL ?? "http://127.0.0.1:8095").replace(/\/$/, "");
  const place = root ? { Reply: { root, parent: root } } : "TopLevel";
  const answer = await posted(`${daemon}/liton/v1/call`, { capability: "rooms.v1", request: { Send: { room_id: room, text, place, mentions: [] } } }, token);
  console.log(JSON.stringify(answer));
  if (!answer.Ok?.Sent) process.exit(1);
} else {
  failed("usage: node agent.mjs join <invite link> <file> | send <room> <text> [<root>]");
}

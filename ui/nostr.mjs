// This browser's Nostr key, which signs the events of the rooms that take
// them (ui/Ports.roc): its secret is made on first use and kept in
// IndexedDB, and never leaves the page. An event's id is the SHA-256 of
// NIP-01's serialization, and its signature BIP-340's Schnorr signature of
// the id (ui/secp256k1.mjs). It loads on first use only.
import { etc, schnorr, utils } from "./secp256k1.mjs";

// The secret, read in the same transaction that adds one where there is
// none, so two tabs opened at once keep the same key.
let secret;
const secret_key = () =>
  (secret ??= new Promise((resolve, reject) => {
    const opening = indexedDB.open("liton", 1);
    opening.onupgradeneeded = () => opening.result.createObjectStore("keys");
    opening.onerror = () => reject(opening.error);
    opening.onsuccess = () => {
      const transaction = opening.result.transaction("keys", "readwrite");
      const keys = transaction.objectStore("keys");
      let key;
      keys.get("nostr").onsuccess = (read) => {
        key = read.target.result;
        if (!key) keys.add((key = utils.randomSecretKey()), "nostr");
      };
      transaction.oncomplete = () => resolve(key);
      transaction.onerror = () => reject(transaction.error);
    };
  }));

// A JSON string escaping only what NIP-01 says to.
const escapes = { "\n": "\\n", '"': '\\"', "\\": "\\\\", "\r": "\\r", "\t": "\\t", "\b": "\\b", "\f": "\\f" };
const quoted = (text) => `"${text.replace(/[\n"\\\r\t\b\f]/g, (character) => escapes[character])}"`;

export const key = async () => etc.bytesToHex(schnorr.getPublicKey(await secret_key()));

// The event of `kind`, `tags` and `content`, made now, with its id and signature.
export const sign = async ({ kind, tags, content }) => {
  const secret = await secret_key();
  const pubkey = etc.bytesToHex(schnorr.getPublicKey(secret));
  const created_at = Math.floor(Date.now() / 1000);
  const serialized = `[0,${quoted(pubkey)},${created_at},${kind},[${tags.map((tag) => `[${tag.map(quoted).join(",")}]`).join(",")}],${quoted(content)}]`;
  const id = etc.bytesToHex(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(serialized))));
  const sig = etc.bytesToHex(await schnorr.signAsync(etc.hexToBytes(id), secret));
  return { id, pubkey, created_at, kind, tags, content, sig };
};

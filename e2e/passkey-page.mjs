// What a page does with a passkey in the e2e suites, as the UI's will, in
// headless Chrome with a virtual authenticator (WebAuthn.addVirtualAuthenticator):
// `liton` in the page gives each route's answer as { status, body }, the
// browser's passkey asked for between begin and finish, its bytes base64url.
export const helpers = `
  const b64 = (buffer) => btoa(String.fromCharCode(...new Uint8Array(buffer))).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
  const bytes = (text) => Uint8Array.from(atob(text.replaceAll("-", "+").replaceAll("_", "/")), (c) => c.charCodeAt(0));
  const post = async (route, body) => {
    const r = await fetch("/liton/v1/" + route, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
    const text = await r.text();
    return { status: r.status, body: r.ok ? JSON.parse(text) : text };
  };
  window.liton = {
    post,
    register: async (name, code, person_name) => {
      const begun = await post("passkeys/register/begin", code ? { code } : {});
      return begun.status === 200 ? window.liton.made(begun.body, name, person_name) : begun;
    },
    // An invite's link redeemed: a passkey made for whom it is for.
    redeem: async (secret, name) => {
      const begun = await post("invite", { secret });
      return begun.status === 200 ? window.liton.made(begun.body, name) : begun;
    },
    // A passkey made as the options o ask, sent to register/finish.
    made: async (o, name, person_name) => {
      const made = await navigator.credentials.create({ publicKey: {
        challenge: bytes(o.challenge), rp: { id: o.rp_id, name: o.rp_id },
        user: { id: bytes(o.user_id), name: o.user_name, displayName: o.display_name },
        pubKeyCredParams: [{ type: "public-key", alg: -7 }, { type: "public-key", alg: -8 }],
        authenticatorSelection: { residentKey: "required", userVerification: "required" }, attestation: "none",
        excludeCredentials: o.exclude.map((id) => ({ type: "public-key", id: bytes(id) })) } });
      return post("passkeys/register/finish", { challenge: o.challenge, id: b64(made.rawId), public_key: b64(made.response.getPublicKey()), alg: made.response.getPublicKeyAlgorithm(), authenticator_data: b64(made.response.getAuthenticatorData()), client_data: b64(made.response.clientDataJSON), name, person_name });
    },
    answer: async () => {
      const begun = await post("login/begin", {});
      const got = await navigator.credentials.get({ publicKey: { challenge: bytes(begun.body.challenge), rpId: begun.body.rp_id, userVerification: "required", allowCredentials: [] } });
      return { challenge: begun.body.challenge, id: b64(got.rawId), authenticator_data: b64(got.response.authenticatorData), client_data: b64(got.response.clientDataJSON), signature: b64(got.response.signature), name: "Browser" };
    },
    // An answer with its signature counter one higher, which it didn't sign.
    tampered: (answer) => {
      const data = bytes(answer.authenticator_data);
      data[36] = data[36] + 1;
      return { ...answer, authenticator_data: b64(data) };
    },
    sign_in: async () => {
      const answer = await window.liton.answer();
      return { answer, finished: await post("login/finish", answer) };
    },
  };`;

// A page of `daemon` in `context` (a browser or a browser context of its
// own), with an authenticator of its own and `liton` defined.
export const opened = async (context, daemon) => {
  const page = await context.newPage();
  await page.send("WebAuthn.enable", {});
  await page.send("WebAuthn.addVirtualAuthenticator", { options: { protocol: "ctap2", transport: "internal", hasResidentKey: true, hasUserVerification: true, isUserVerified: true } });
  await page.goto(`${daemon}/ui/index.html`);
  await page.evaluate(helpers);
  return page;
};

(test "Liton — a link's #pair= code asks the daemon at once for the passkey it grants, then the owner's name, as they have none, and makes the passkey, shown as making it at once"
  (setup
    (initial-location "/ui/index.html#pair=ABCD-EFGH"))
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 401 :body "this device isn't paired with the daemon")
    (run-effect 1)
    (expect-visible (text "Make your passkey"))
    (stub-http "begin" :url "/liton/v1/passkeys/register/begin" :status 200 :body "{\"challenge\":\"c1\",\"unnamed\":true}")
    (run-effect 3)
    (fill (label "Your name") "Ada")
    (click (role button :name "Make a passkey"))
    (expect-visible (role button :name "Making a passkey…"))
    (expect-port-call 4 "liton/passkey" "{\"create\":true,\"name\":\"Browser\",\"options\":\"{\\\"challenge\\\":\\\"c1\\\",\\\"unnamed\\\":true}\",\"person_name\":\"Ada\"}")
    (answer-port 4 reply "\"{}\"")
    (stub-http "finish" :url "/liton/v1/passkeys/register/finish" :status 200 :body "{\"passkey\":{\"id\":\"k1\",\"name\":\"Browser\"},\"device\":{\"id\":\"d1\",\"name\":\"Browser\"},\"person\":{\"id\":\"p1\",\"name\":\"Ada\",\"role\":\"operator\"}}")
    (run-effect 5)
    (expect-absent (text "Make your passkey"))
  )
)

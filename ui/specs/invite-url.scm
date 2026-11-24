(test "Liton — a link's #invite= asks the daemon at once for the passkey it grants, says whom it is for, and makes the passkey, shown as making it at once"
  (setup
    (initial-location "/ui/index.html#invite=8f9d8d876406214368a07e758eabcb58"))
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 401 :body "this device isn't paired with the daemon")
    (run-effect 1)
    (stub-http "join" :url "/liton/v1/invite" :status 200 :body "{\"challenge\":\"c1\",\"invite\":{\"name\":\"Dana\",\"role\":\"staff\"}}")
    (run-effect 3)
    (expect-visible (text "Join as Dana"))
    (click (role button :name "Make a passkey"))
    (expect-visible (role button :name "Making a passkey…"))
    (answer-port 4 reply "\"{}\"")
    (stub-http "finish" :url "/liton/v1/passkeys/register/finish" :status 200 :body "{\"passkey\":{\"id\":\"k1\",\"name\":\"Browser\"},\"device\":{\"id\":\"d1\",\"name\":\"Browser\"},\"person\":{\"id\":\"p1\",\"name\":\"Dana\",\"role\":\"staff\"}}")
    (run-effect 5)
    (expect-absent (text "Join as Dana"))
  )
)

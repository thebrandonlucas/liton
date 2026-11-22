(test "Liton — a link's #invite= joins this browser with its own key when the daemon says it isn't paired, shown as pairing, and signs the invite's name as its profile"
  (setup
    (initial-location "/ui/index.html#invite=8f9d8d876406214368a07e758eabcb58"))
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 401 :body "this device isn't paired with the daemon")
    (run-effect 1)
    (expect-visible (text "Pair this browser"))
    (expect-visible (role button :name "Pairing…"))
    (expect-port-call 3 "liton/nostr/key" "{}")
    (answer-port 3 reply "\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"")
    ; The key bound to no device yet, as this browser isn't paired.
    (stub-http "bind" :url "/liton/v1/devices/key" :status 401 :body "this device isn't paired with the daemon")
    (run-effect 4)
    (stub-http "join" :url "/liton/v1/invite" :status 200 :body "{\"device\":{\"id\":\"d1\",\"name\":\"Browser\"},\"person\":{\"name\":\"Dana\",\"role\":\"staff\"}}")
    (run-effect 5)
    (expect-absent (text "Pair this browser"))
    (expect-port-call 7 "liton/nostr/sign" "{\"content\":\"{\\\"name\\\":\\\"Dana\\\"}\",\"kind\":0,\"tags\":[]}")
  )
)

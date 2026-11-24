(test "Liton — a link's #invite= joins this browser when the daemon says it isn't paired, shown as pairing"
  (setup
    (initial-location "/ui/index.html#invite=8f9d8d876406214368a07e758eabcb58"))
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 401 :body "this device isn't paired with the daemon")
    (run-effect 1)
    (expect-visible (text "Pair this browser"))
    (expect-visible (role button :name "Pairing…"))
    (stub-http "join" :url "/liton/v1/invite" :status 200 :body "{\"device\":{\"id\":\"d1\",\"name\":\"Browser\"},\"person\":{\"id\":\"p1\",\"name\":\"Dana\",\"role\":\"staff\"}}")
    (run-effect 3)
    (expect-absent (text "Pair this browser"))
  )
)

(test "Liton — a daemon that connects no providers says so in the main area once its manifest arrives, with its host's settings a click away, in place of waiting to connect"
  (steps
    (expect-visible (text "Connecting to the daemon…"))
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"home\"},\"providers\":[],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (expect-absent (text "Connecting to the daemon…"))
    (expect-text (test-id "empty-state") "Nothing is connectedliton's daemon connects no providers yet. Start it with PASEO_PASSWORD set to connect Paseo, or LITON_PROVIDERS for other providers, and what they offer appears here.See the host's settings")
    (click (role button :name "See the host's settings"))
    (expect-visible (text "Host · home"))
  )
)

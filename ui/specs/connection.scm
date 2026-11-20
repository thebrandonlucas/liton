(test "Liton — the strip says which daemon this is and whether it answers; its menu lists each provider with how it is doing and what it offers, and goes to Settings' Host"
  (steps
    (expect-attr (test-id "connection") aria-label "Connection: liton, connecting")
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"home\",\"name\":\"home\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1},{\"name\":\"workspaces\",\"version\":1}],\"id\":\"paseo\",\"name\":\"Paseo\"},{\"capabilities\":[{\"name\":\"rooms\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock agents\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (expect-attr (test-id "connection") aria-label "Connection: home, connected")
    (click (test-id "connection"))
    (expect-visible (text "Paseo"))
    (expect-visible (text "Mock agents"))
    (expect-visible (text "offers rooms.v1"))
    (click (role button :name "Host settings"))
    (expect-visible (role heading :name "Host · home"))
    (expect-absent (text "offers rooms.v1"))
    ; A poll unanswered says the daemon is unreachable.
    (stub-http-reject "poll" :kind network :detail "refused")
    (run-effect 2)
    (expect-attr (test-id "connection") aria-label "Connection: home, unreachable")
  )
)

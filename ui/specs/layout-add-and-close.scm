(test "Liton — the toolbar adds a pane in a column of its own, and × closes one"
  (steps
    (stub-http "manifest" :url "/api/manifest" :status 200 :body "{\"protocol\":1,\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}]}")
    (run-effect 1)
    (expect-visible (role button :name "+ Chat"))
    (click (role button :name "+ CI runs (unavailable)"))
    (expect-visible (role region :name "CI runs"))
    (expect-visible (text "This widget needs ci.v1, which no connected provider supplies. Connect one that does, and it fills in here."))
    (expect-visible (role button :name "CI runs"))
    ; The first pane's close button is the Sessions pane's.
    (click (role button :name "Close pane"))
    (expect-absent (role region :name "Sessions"))
    (expect-absent (role button :name "Sessions"))
    (expect-visible (role region :name "Chat"))
    (expect-visible (role region :name "CI runs"))
  )
)

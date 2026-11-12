(test "Liton — settings add a widget as a tab of the Workbench's main area, and × closes one"
  (steps
    (stub-http "manifest" :url "/api/manifest" :status 200 :body "{\"protocol\":1,\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}]}")
    (run-effect 1)
    (click (role button :name "Settings"))
    (expect-attr (role button :name "Settings") aria-expanded "true")
    (expect-visible (role button :name "+ Chat"))
    (click (role button :name "+ CI runs (unavailable)"))
    ; Shown at once, as the main area's active tab.
    (expect-text (test-id "show-main") "Chat · CI runs")
    (expect-attr (role button :name "CI runs") aria-pressed "true")
    (expect-attr (role region :name "CI runs") class "pane")
    (expect-attr (role region :name "Chat") class "pane hidden")
    (expect-visible (text "This widget needs ci.v1, which no connected provider supplies. Connect one that does, and it fills in here."))
    ; The first pane's close button is the Sessions pane's. Its drawer stays.
    (click (role button :name "Close pane"))
    (expect-absent (role region :name "Sessions"))
    (expect-text (test-id "show-left") "")
    (expect-visible (role region :name "CI runs"))
  )
)

(test "Liton — a widget whose capabilities are offered but that liton has no view of yet says so, rather than showing another widget"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1},{\"name\":\"ci\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (click (role button :name "Settings"))
    (select-option (label "Swap Changes for") "ci")
    (click (role button :name "Close settings"))
    (expect-attr (role region :name "CI runs") class "pane focused")
    (expect-visible (text "liton can't show this widget yet."))
  )
)

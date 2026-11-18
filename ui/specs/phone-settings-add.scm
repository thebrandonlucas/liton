(test "Liton — on a phone, a widget added in Settings shows its panel, the main area, with Settings closed"
  (setup (initial-location "/#left"))
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1},{\"name\":\"workspaces\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (expect-attr (test-id "show-left") aria-pressed "true")
    (click (role button :name "Settings"))
    (click (role button :name "+ Sessions"))
    (expect-attr (role button :name "Settings") aria-expanded "false")
    (expect-attr (test-id "show-main") aria-pressed "true")
    (expect-current-location "/#main")
    (expect-attr (role region :name "Sessions") class "pane focused")
  )
)

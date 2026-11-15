(test "Liton — a page loaded at a panel's URL opens on that panel"
  (setup (initial-location "/#left"))
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1},{\"name\":\"workspaces\",\"version\":1},{\"name\":\"workspace.git\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (expect-attr (test-id "show-left") aria-pressed "true")
    (expect-attr (test-id "slot-left") class "column slot slot-left tabbed shown")
  )
)

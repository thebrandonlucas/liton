(test "Liton — a window opens the deck's surface its URL names, so a second window shows another"
  (setup
    (initial-location "/#deck=3"))
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1},{\"name\":\"workspaces\",\"version\":1},{\"name\":\"rooms\",\"version\":1},{\"name\":\"tickets\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (expect-attr (role button :name "Surface 3: Review") aria-pressed "true")
    (expect-attr (test-id "grid") class "grid workbench")
    (click (role button :name "Surface 4: Board"))
    (expect-current-location "/#deck=4")
  )
)

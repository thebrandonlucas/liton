(test "Liton — settings mark the widgets already in the layout, which can still be added again, and unmark one removed"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (click (role button :name "Settings"))
    (expect-attr (role button :name "+ Chat (already in the layout)") class "added")
    (expect-attr (role button :name "+ CI runs (unavailable)") class "")
    (click (role button :name "+ Sessions"))
    (click (role button :name "Settings"))
    (expect-attr (role button :name "+ Sessions (already in the layout)") class "added")
    (click (role button :name "Remove Sessions"))
    (expect-attr (role button :name "+ Sessions") class "")
  )
)

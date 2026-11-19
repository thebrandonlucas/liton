(test "Liton — a fresh browser shows each surface's own theme, but a theme picked stays through opening another surface and resetting one"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1},{\"name\":\"workspaces\",\"version\":1},{\"name\":\"tickets\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    ; Until a theme is picked, the Board surface shows its own.
    (press "7")
    (click (role button :name "Settings"))
    (click (role button :name "Appearance"))
    (expect-attr (role button :name "Graphite theme") aria-pressed "true")
    (click (role button :name "Pastoral theme"))
    (expect-attr (role button :name "Pastoral theme") aria-pressed "true")
    ; Another surface keeps the theme picked.
    (click (role button :name "Surface"))
    (click (role button :name "Developer preset"))
    (click (role button :name "Appearance"))
    (expect-attr (role button :name "Pastoral theme") aria-pressed "true")
    (expect-attr (role button :name "Neutral theme") aria-pressed "false")
    ; So does resetting the surface.
    (click (role button :name "Surface"))
    (select-option (label "Swap Workspaces for") "sessions")
    (click (role button :name "Reset to Developer"))
    (expect-attr (role button :name "Developer preset") aria-pressed "true")
    (click (role button :name "Appearance"))
    (expect-attr (role button :name "Pastoral theme") aria-pressed "true")
  )
)

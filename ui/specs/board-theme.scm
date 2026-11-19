(test "Liton — the Board preset shows the Graphite theme, close to Linear's, until another is picked"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1},{\"name\":\"tickets\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[{\"Sessions\":[{\"agent\":\"claude\",\"id\":\"fix-auth\",\"provider\":\"mock\",\"status\":\"Running\",\"title\":\"Fix the login redirect\",\"updated\":\"2026-01-01T08:00:00.000Z\"},{\"agent\":\"codex\",\"id\":\"docs\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Write the docs\",\"updated\":\"2026-01-01T09:00:00.000Z\"}]}]}]}")
    (run-effect 2)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[]},{\"capability\":\"chat.v1\",\"topic\":\"timeline/docs\",\"cursor\":\"t1\",\"events\":[]}]}")
    (run-effect 3)
    ; The Board preset is the fifth.
    (press "5")
    ; The Board preset shows its own theme, Graphite, dense and dark; another preset keeps it until another theme is picked.
    (click (role button :name "Settings"))
    (expect-attr (role button :name "Graphite theme") aria-pressed "true")
    (click (role button :name "Plain theme"))
    (expect-attr (role button :name "Plain theme") aria-pressed "true")
    (expect-attr (role button :name "Graphite theme") aria-pressed "false")
  )
)

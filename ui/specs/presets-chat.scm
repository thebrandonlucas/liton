(test "Liton — the presets are in Settings, not the bar, and the Chat preset lists the sessions, the latest first, beside one large chat"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[{\"id\":\"attention\",\"name\":\"Attention\",\"offers\":{\"name\":\"attention\",\"version\":1},\"uses\":[{\"name\":\"chat\",\"version\":1}]}],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[{\"Sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Fix login\",\"updated\":\"2026-01-01T08:00:00.000Z\"},{\"agent\":\"claude\",\"id\":\"s2\",\"provider\":\"mock\",\"status\":\"Finished\",\"title\":\"Write post\",\"updated\":\"2026-01-01T09:00:00.000Z\"}]}]}]}")
    (run-effect 2)
    (expect-absent (role button :name "1 Developer"))
    (expect-absent (role button :name "Chat preset"))
    (click (role button :name "Settings"))
    (click (role button :name "Chat preset"))
    (expect-attr (role button :name "Chat preset") aria-pressed "true")
    (click (role button :name "Settings"))
    (expect-absent (role region :name "Workspaces"))
    (expect-attr (test-id "slot-right") class "column slot slot-right tabbed collapsed")
    (expect-text (test-id "slot-left") "SessionsSessions⋯Write postdone+Fix loginidle+")
    ; The chat opens on the latest session.
    (expect-text (test-id "session-title") "Write post")
  )
)

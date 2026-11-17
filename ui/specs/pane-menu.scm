(test "Liton — a pane's ⋯ menu holds what it follows and Pin, and closes once used"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[{\"Sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Fix tests\"}]}]}]}")
    (run-effect 2)
    (expect-absent (role button :name "Pin"))
    (click (role button :name "Chat menu"))
    (expect-attr (role button :name "Chat menu") aria-expanded "true")
    (expect-visible (text "following Fix tests"))
    ; The main area's last pane neither closes nor hides.
    (expect-absent (role button :name "Close pane") :never-drawn)
    (expect-absent (role button :name "Hide Chat") :never-drawn)
    ; A Workbench's slots don't move panes.
    (expect-absent (role button :name "Move Chat left") :never-drawn)
    (click (role button :name "Pin"))
    (expect-attr (role button :name "Chat menu") aria-expanded "false")
    (expect-visible (text "pinned"))
    (click (role button :name "Chat menu"))
    (expect-visible (text "pinned to Fix tests"))
    (click (role button :name "Unpin"))
    (expect-text (test-id "session-title") "Fix tests")
  )
)

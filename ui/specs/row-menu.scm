(test "Liton — a row's ⋮ menu offers what the row allows, and each choice shows at once and closes it"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1},{\"name\":\"workspaces\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[{\"id\":\"attention\",\"name\":\"Attention\",\"offers\":{\"name\":\"attention\",\"version\":1},\"uses\":[{\"name\":\"chat\",\"version\":1}]}],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[{\"Sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Running\",\"title\":\"Fix tests\",\"updated\":\"2026-01-01T10:00:00.000Z\",\"workspace\":{\"directory\":\"/src/app\",\"id\":\"w1\"}},{\"agent\":\"claude\",\"id\":\"s2\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Write docs\",\"updated\":\"2026-01-01T09:00:00.000Z\",\"workspace\":{\"directory\":\"/src/app\",\"id\":\"w2\"}}]}]},{\"capability\":\"attention.v1\",\"topic\":\"items\",\"cursor\":\"i1\",\"events\":[{\"Items\":[{\"agent\":\"claude\",\"permissions\":[],\"provider\":\"mock\",\"session_id\":\"s1\",\"set_aside\":\"No\",\"signature\":\"Working 1\",\"state\":\"Working\",\"summary\":\"\",\"title\":\"Fix tests\",\"unread\":false,\"updated\":\"2026-01-01T10:00:00.000Z\"},{\"agent\":\"claude\",\"permissions\":[],\"provider\":\"mock\",\"session_id\":\"s2\",\"set_aside\":\"No\",\"signature\":\"Done 1\",\"state\":\"Done\",\"summary\":\"\",\"title\":\"Write docs\",\"unread\":true,\"updated\":\"2026-01-01T09:00:00.000Z\"}]}]},{\"capability\":\"workspaces.v1\",\"topic\":\"list\",\"cursor\":\"l1\",\"events\":[{\"Listed\":{\"projects\":[{\"directory\":\"/src/app\",\"id\":\"p1\",\"name\":\"app\",\"provider\":\"mock\"}],\"workspaces\":[{\"branch\":{\"Branch\":\"main\"},\"changes\":\"Uncounted\",\"directory\":\"/src/app\",\"dirty\":false,\"id\":\"w1\",\"kind\":\"Checkout\",\"labels\":[],\"name\":\"main\",\"pinned\":false,\"project_id\":\"p1\",\"provider\":\"mock\",\"session_ids\":[\"s1\"],\"state\":\"Working\"},{\"branch\":{\"Branch\":\"docs\"},\"changes\":\"Uncounted\",\"directory\":\"/src/app\",\"dirty\":false,\"id\":\"w2\",\"kind\":\"Worktree\",\"labels\":[],\"name\":\"docs\",\"pinned\":false,\"project_id\":\"p1\",\"provider\":\"mock\",\"session_ids\":[\"s2\"],\"state\":\"Idle\"}]}}]}]}")
    (run-effect 2)
    (expect-text (test-id "session-title") "Fix tests")
    (click (role button :name "Fix tests menu"))
    (expect-attr (role button :name "Fix tests menu") aria-expanded "true")
    (expect-visible (role button :name "New agent beside it"))
    (expect-visible (role button :name "Copy id"))
    ; Working, it can't be marked read or unread, but stops from its row,
    ; shown stopping at once, and the menu closes.
    (expect-absent (role button :name "Mark unread"))
    (click (role button :name "Stop agent"))
    (expect-absent (role button :name "Stop agent"))
    (expect-text (test-id "stop-status") "Stopping…")
    ; Done and unread, it is marked read before the daemon answers.
    (click (role button :name "Write docs menu"))
    (click (role button :name "Mark read"))
    (expect-absent (role button :name "Mark read"))
    (click (role button :name "Write docs menu"))
    (expect-visible (role button :name "Mark unread"))
    (expect-absent (role button :name "Stop agent"))
    ; Escape closes a menu.
    (press "Escape")
    (expect-absent (role button :name "Copy id"))
    ; A project's menu creates a workspace of it.
    (click (role button :name "App menu"))
    (click (role button :name "New workspace"))
    (expect-visible (role button :name "Create"))
  )
)

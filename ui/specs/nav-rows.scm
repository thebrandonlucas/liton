(test "Liton — over the Developer preset's Workspaces, New workspace opens the form to create one, and Search the palette"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1},{\"name\":\"workspaces\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[{\"Sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Running\",\"title\":\"Fix tests\",\"updated\":\"2026-01-01T10:00:00.000Z\",\"workspace\":{\"directory\":\"/src/app\",\"id\":\"w1\"}},{\"agent\":\"claude\",\"id\":\"s2\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Write docs\",\"updated\":\"2026-01-01T09:00:00.000Z\",\"workspace\":{\"directory\":\"/src/app\",\"id\":\"w2\"}}]}]},{\"capability\":\"attention.v1\",\"topic\":\"items\",\"cursor\":\"\",\"events\":[]},{\"capability\":\"workspaces.v1\",\"topic\":\"list\",\"cursor\":\"l1\",\"events\":[{\"Listed\":{\"projects\":[{\"directory\":\"/src/app\",\"id\":\"p1\",\"name\":\"app\",\"provider\":\"mock\"}],\"workspaces\":[{\"branch\":{\"Branch\":\"main\"},\"changes\":\"Uncounted\",\"directory\":\"/src/app\",\"dirty\":false,\"id\":\"w1\",\"kind\":\"Worktree\",\"labels\":[],\"name\":\"main\",\"pinned\":false,\"project_id\":\"p1\",\"provider\":\"mock\",\"session_ids\":[\"s1\"],\"state\":\"Working\"},{\"branch\":{\"Branch\":\"docs\"},\"changes\":\"Uncounted\",\"directory\":\"/src/app\",\"dirty\":false,\"id\":\"w2\",\"kind\":\"Worktree\",\"labels\":[],\"name\":\"docs\",\"pinned\":true,\"project_id\":\"p1\",\"provider\":\"mock\",\"session_ids\":[\"s2\"],\"state\":\"Idle\"},{\"branch\":{\"Branch\":\"scratch\"},\"changes\":\"Uncounted\",\"directory\":\"/src/app\",\"dirty\":false,\"id\":\"w3\",\"kind\":\"Worktree\",\"labels\":[],\"name\":\"scratch\",\"pinned\":false,\"project_id\":\"p1\",\"provider\":\"mock\",\"session_ids\":[],\"state\":\"Idle\"}]}}]}]}")
    (run-effect 2)
    (click (test-id "nav-new-workspace"))
    (expect-visible (role button :name "Create"))
    (click (role button :name "Cancel"))
    (expect-absent (role button :name "Create"))
    (click (role button :name "Search"))
    (expect-visible (role dialog :name "Palette"))
  )
)

(test "Liton — a click anywhere in a Workspaces row opens it, as its title does, while its + and ⋮ keep their own actions"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1},{\"name\":\"workspaces\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[{\"Sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Running\",\"title\":\"Fix tests\",\"updated\":\"2026-01-01T10:00:00.000Z\",\"workspace\":{\"directory\":\"/src/app\",\"id\":\"w1\"}},{\"agent\":\"claude\",\"id\":\"s2\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Write docs\",\"updated\":\"2026-01-01T09:00:00.000Z\",\"workspace\":{\"directory\":\"/src/app\",\"id\":\"w2\"}}]}]},{\"capability\":\"attention.v1\",\"topic\":\"items\",\"cursor\":\"\",\"events\":[]},{\"capability\":\"workspaces.v1\",\"topic\":\"list\",\"cursor\":\"l1\",\"events\":[{\"Listed\":{\"projects\":[{\"directory\":\"/src/app\",\"id\":\"p1\",\"name\":\"app\",\"provider\":\"mock\"}],\"workspaces\":[{\"branch\":{\"Branch\":\"main\"},\"changes\":\"Uncounted\",\"directory\":\"/src/app\",\"dirty\":false,\"id\":\"w1\",\"kind\":\"Worktree\",\"labels\":[],\"name\":\"main\",\"pinned\":false,\"project_id\":\"p1\",\"provider\":\"mock\",\"session_ids\":[\"s1\"],\"state\":\"Working\"},{\"branch\":{\"Branch\":\"docs\"},\"changes\":\"Uncounted\",\"directory\":\"/src/app\",\"dirty\":false,\"id\":\"w2\",\"kind\":\"Worktree\",\"labels\":[],\"name\":\"docs\",\"pinned\":false,\"project_id\":\"p1\",\"provider\":\"mock\",\"session_ids\":[\"s2\"],\"state\":\"Idle\"}]}}]}]}")
    (run-effect 2)
    (expect-text (test-id "workspace-title") "main")
    ; Its second line, away from its title, opens it at once.
    (click (text "docs · app"))
    (expect-text (test-id "workspace-title") "docs")
    ; Another row's ⋮ opens its menu and + its form, neither opening the row.
    (click (role button :name "Fix tests menu"))
    (expect-visible (role button :name "Pin"))
    (expect-text (test-id "workspace-title") "docs")
    (click (role button :name "New agent beside Fix tests"))
    (expect-text (test-id "workspace-title") "docs")
    (expect-visible (label "Agent"))
  )
)

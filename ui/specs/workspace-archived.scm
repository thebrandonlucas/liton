(test "Liton — archiving the workspace shown shows the latest left at once, never its id; archiving its last agent leaves it shown empty; with none left, the main area asks to pick one"
  (setup
    (local-storage "liton.snapshot" "{\"collapsed\":[],\"grid\":{\"columns\":[1,1,1],\"rows\":[1],\"tiles\":[{\"active\":\"pane-1\",\"bottom\":1,\"id\":\"tile-1\",\"left\":0,\"panes\":[{\"id\":\"pane-1\",\"options\":[{\"key\":\"sessions\",\"value\":\"Tabs\"}],\"pinned\":\"\",\"widget\":\"workspaces\"}],\"right\":1,\"top\":0},{\"active\":\"pane-2\",\"bottom\":1,\"id\":\"tile-2\",\"left\":1,\"panes\":[{\"id\":\"pane-2\",\"options\":[],\"pinned\":\"\",\"widget\":\"chat\"},{\"id\":\"pane-8\",\"options\":[],\"pinned\":\"\",\"widget\":\"ticket\"}],\"right\":2,\"top\":0},{\"active\":\"pane-3\",\"bottom\":1,\"id\":\"tile-3\",\"left\":2,\"panes\":[{\"id\":\"pane-3\",\"options\":[],\"pinned\":\"\",\"widget\":\"changes\"}],\"right\":3,\"top\":0}]},\"hidden\":[\"pane-8\"],\"shell\":\"Workbench\",\"theme\":\"\",\"version\":8}"))
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1},{\"name\":\"workspaces\",\"version\":1},{\"name\":\"workspace.git\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[{\"Sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Fix tests\",\"updated\":\"2026-01-01T10:00:00.000Z\",\"workspace\":{\"directory\":\"/src/app\",\"id\":\"w1\"}},{\"agent\":\"claude\",\"id\":\"s2\",\"provider\":\"mock\",\"status\":\"AwaitingPermission\",\"title\":\"Write docs\",\"updated\":\"2026-01-01T09:00:00.000Z\",\"workspace\":{\"directory\":\"/src/app\",\"id\":\"w1\"}},{\"agent\":\"claude\",\"id\":\"s3\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Draft notes\",\"updated\":\"2026-01-01T11:00:00.000Z\",\"workspace\":{\"directory\":\"/src/app\",\"id\":\"w2\"}}]}]},{\"capability\":\"attention.v1\",\"topic\":\"items\",\"cursor\":\"\",\"events\":[]},{\"capability\":\"workspaces.v1\",\"topic\":\"list\",\"cursor\":\"l1\",\"events\":[{\"Listed\":{\"projects\":[{\"directory\":\"/src/app\",\"id\":\"p1\",\"name\":\"app\",\"provider\":\"mock\"}],\"workspaces\":[{\"branch\":{\"Branch\":\"main\"},\"changes\":\"Uncounted\",\"directory\":\"/src/app\",\"dirty\":false,\"id\":\"w1\",\"kind\":\"Checkout\",\"labels\":[],\"name\":\"main\",\"pinned\":false,\"project_id\":\"p1\",\"provider\":\"mock\",\"session_ids\":[\"s1\",\"s2\"],\"state\":\"NeedsYou\"},{\"branch\":{\"Branch\":\"notes\"},\"changes\":\"Uncounted\",\"directory\":\"/src/app\",\"dirty\":false,\"id\":\"w2\",\"kind\":\"Worktree\",\"labels\":[],\"name\":\"notes\",\"pinned\":false,\"project_id\":\"p1\",\"provider\":\"mock\",\"session_ids\":[\"s3\"],\"state\":\"Idle\"}]}}]}]}")
    (run-effect 2)
    (click (role button :name "main"))
    (expect-text (test-id "workspace-title") "main")
    ; Archived from its header, the workspace gives way to the latest session's.
    (click (role button :name "Workspace menu"))
    (click (role button :name "Archive workspace"))
    (expect-text (test-id "workspace-title") "notes")
    (expect-text (test-id "session-title") "Draft notes")
    (stub-http "archive" :url "/liton/v1/call" :status 200 :body "{\"Ok\":\"Accepted\"}")
    (run-effect 4)
    (expect-text (test-id "workspace-title") "notes")
    ; Its last agent archived, the workspace stays, empty, by its name.
    (click (role button :name "Draft notes menu"))
    (click (role button :name "Archive"))
    (expect-visible (text "No agents in notes yet"))
    (expect-visible (role button :name "Start an agent"))
    (expect-text (test-id "workspace-title") "notes")
    ; With no workspace left, the main area says to pick one, and starts nothing in one gone.
    (click (role button :name "Workspace menu"))
    (click (role button :name "Archive workspace"))
    (expect-visible (text "Pick a workspace"))
    (expect-absent (role button :name "Start an agent"))
  )
)

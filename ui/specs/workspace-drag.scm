(test "Liton — the workspace a Workbench shows as tabs drags as other panes do, by a session's tab or its header's name, with its chat"
  (setup
    (local-storage "liton.snapshot" "{\"collapsed\":[],\"grid\":{\"columns\":[1,1,1],\"rows\":[1],\"tiles\":[{\"active\":\"pane-1\",\"bottom\":1,\"id\":\"tile-1\",\"left\":0,\"panes\":[{\"id\":\"pane-1\",\"options\":[{\"key\":\"sessions\",\"value\":\"Tabs\"}],\"pinned\":\"\",\"widget\":\"workspaces\"}],\"right\":1,\"top\":0},{\"active\":\"pane-2\",\"bottom\":1,\"id\":\"tile-2\",\"left\":1,\"panes\":[{\"id\":\"pane-2\",\"options\":[],\"pinned\":\"\",\"widget\":\"chat\"},{\"id\":\"pane-8\",\"options\":[],\"pinned\":\"\",\"widget\":\"ticket\"}],\"right\":2,\"top\":0},{\"active\":\"pane-3\",\"bottom\":1,\"id\":\"tile-3\",\"left\":2,\"panes\":[{\"id\":\"pane-3\",\"options\":[],\"pinned\":\"\",\"widget\":\"changes\"}],\"right\":3,\"top\":0}]},\"hidden\":[\"pane-8\"],\"shell\":\"Workbench\",\"theme\":\"\",\"version\":8}"))
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1},{\"name\":\"workspaces\",\"version\":1},{\"name\":\"workspace.git\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[{\"Sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Fix tests\",\"updated\":\"2026-01-01T10:00:00.000Z\",\"workspace\":{\"directory\":\"/src/app\",\"id\":\"w1\"}},{\"agent\":\"claude\",\"id\":\"s2\",\"provider\":\"mock\",\"status\":\"AwaitingPermission\",\"title\":\"Write docs\",\"updated\":\"2026-01-01T09:00:00.000Z\",\"workspace\":{\"directory\":\"/src/app\",\"id\":\"w1\"}},{\"agent\":\"claude\",\"id\":\"s3\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Draft notes\",\"updated\":\"2026-01-01T11:00:00.000Z\",\"workspace\":{\"directory\":\"/src/app\",\"id\":\"w2\"}}]}]},{\"capability\":\"attention.v1\",\"topic\":\"items\",\"cursor\":\"\",\"events\":[]},{\"capability\":\"workspaces.v1\",\"topic\":\"list\",\"cursor\":\"l1\",\"events\":[{\"Listed\":{\"projects\":[{\"directory\":\"/src/app\",\"id\":\"p1\",\"name\":\"app\",\"provider\":\"mock\"}],\"workspaces\":[{\"branch\":{\"Branch\":\"main\"},\"changes\":\"Uncounted\",\"directory\":\"/src/app\",\"dirty\":false,\"id\":\"w1\",\"kind\":\"Checkout\",\"labels\":[],\"name\":\"main\",\"pinned\":false,\"project_id\":\"p1\",\"provider\":\"mock\",\"session_ids\":[\"s1\",\"s2\"],\"state\":\"NeedsYou\"},{\"branch\":{\"Branch\":\"notes\"},\"changes\":\"Uncounted\",\"directory\":\"/src/app\",\"dirty\":false,\"id\":\"w2\",\"kind\":\"Worktree\",\"labels\":[],\"name\":\"notes\",\"pinned\":false,\"project_id\":\"p1\",\"provider\":\"mock\",\"session_ids\":[\"s3\"],\"state\":\"Idle\"}]}}]}]}")
    (run-effect 2)
    (click (role button :name "main"))
    (expect-text (test-id "workspace-title") "main")
    ; Held by a session's tab, the chat moves, as if dropped where the pointer is.
    (pointer-down (role tab :name "Write docs"))
    (expect-port-subscriptions "liton/drag/pointer" 1)
    (emit-port "liton/drag/pointer" "{\"phase\":\"Moved\",\"x\":600,\"y\":400,\"tile\":\"tile-3\",\"tab\":\"\",\"across\":5000,\"down\":5000}")
    (expect-attr (role region :name "Chat") class "pane dragged")
    (press "Escape")
    (pointer-up (role tab :name "Write docs"))
    (expect-port-subscriptions "liton/drag/pointer" 0)
    ; Held by its header's name, it drops beside Changes, its tabs with it.
    (pointer-down (test-id "workspace-title"))
    (expect-port-subscriptions "liton/drag/pointer" 1)
    (emit-port "liton/drag/pointer" "{\"phase\":\"Released\",\"x\":600,\"y\":400,\"tile\":\"tile-3\",\"tab\":\"\",\"across\":5000,\"down\":5000}")
    (pointer-up (test-id "workspace-title"))
    (expect-port-subscriptions "liton/drag/pointer" 0)
    (expect-text (test-id "show-right") "Changes · Chat")
    (expect-visible (role tab :name "Write docs"))
  )
)

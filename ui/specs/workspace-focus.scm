(test "Liton — Workspaces listing sessions as rows list each project's workspaces and sessions, and clicking a workspace shows it in Chat and Changes"
  (setup
    ; The Developer layout with Workspaces listing sessions as rows, under their projects.
    (local-storage "liton.snapshot" "{\"collapsed\":[],\"grid\":{\"columns\":[1,1,1],\"rows\":[1],\"tiles\":[{\"active\":\"pane-1\",\"bottom\":1,\"id\":\"tile-1\",\"left\":0,\"panes\":[{\"id\":\"pane-1\",\"options\":[],\"pinned\":\"\",\"widget\":\"workspaces\"}],\"right\":1,\"top\":0},{\"active\":\"pane-2\",\"bottom\":1,\"id\":\"tile-2\",\"left\":1,\"panes\":[{\"id\":\"pane-2\",\"options\":[],\"pinned\":\"\",\"widget\":\"chat\"},{\"id\":\"pane-8\",\"options\":[],\"pinned\":\"\",\"widget\":\"ticket\"}],\"right\":2,\"top\":0},{\"active\":\"pane-3\",\"bottom\":1,\"id\":\"tile-3\",\"left\":2,\"panes\":[{\"id\":\"pane-3\",\"options\":[],\"pinned\":\"\",\"widget\":\"changes\"},{\"id\":\"pane-4\",\"options\":[],\"pinned\":\"\",\"widget\":\"files\"},{\"id\":\"pane-5\",\"options\":[],\"pinned\":\"\",\"widget\":\"tickets\"}],\"right\":3,\"top\":0}]},\"hidden\":[\"pane-8\"],\"shell\":\"Workbench\",\"theme\":\"\",\"version\":8}"))
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1},{\"name\":\"workspaces\",\"version\":1},{\"name\":\"workspace.git\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[{\"Sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Fix tests\",\"workspace\":{\"directory\":\"/src/app\",\"id\":\"w1\"}},{\"agent\":\"codex\",\"id\":\"s2\",\"provider\":\"mock\",\"status\":\"AwaitingPermission\",\"title\":\"Write docs\",\"workspace\":{\"directory\":\"/src/app\",\"id\":\"w1\"}}]}]},{\"capability\":\"attention.v1\",\"topic\":\"items\",\"cursor\":\"\",\"events\":[]},{\"capability\":\"workspaces.v1\",\"topic\":\"list\",\"cursor\":\"l1\",\"events\":[{\"Listed\":{\"projects\":[{\"directory\":\"/src/app\",\"id\":\"p1\",\"name\":\"app\",\"provider\":\"mock\"}],\"workspaces\":[{\"branch\":{\"Branch\":\"fix-tests\"},\"changes\":{\"Counted\":{\"additions\":3,\"deletions\":1}},\"directory\":\"/src/app\",\"dirty\":true,\"id\":\"w1\",\"kind\":\"Worktree\",\"labels\":[],\"name\":\"main\",\"pinned\":false,\"project_id\":\"p1\",\"provider\":\"mock\",\"session_ids\":[\"s1\",\"s2\"],\"state\":\"NeedsYou\"}]}}]}]}")
    (run-effect 2)
    (expect-visible (role button :name "App"))
    (expect-visible (text "fix-tests"))
    (expect-visible (text "+3"))
    (expect-visible (text "−1"))
    ; The right drawer's button shows the changes of the chat's workspace.
    (expect-text (label "Right drawer") "+3−1")
    (expect-visible (role button :name "Fix tests"))
    (expect-visible (text "waiting for you"))
    ; The chat follows the first session until a workspace is picked.
    (expect-text (test-id "session-title") "Fix tests")
    (click (role button :name "main"))
    ; At once: the chat shows the workspace's session that needs you.
    (expect-text (test-id "session-title") "Write docs")
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[]}]}")
    (run-effect 3)
    ; Then Changes polls the workspace's git, not a session's.
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[]},{\"capability\":\"chat.v1\",\"topic\":\"timeline/s2\",\"cursor\":\"\",\"events\":[]},{\"capability\":\"workspace.git.v1\",\"topic\":\"changes/workspace:w1/Uncommitted\",\"cursor\":\"g1\",\"events\":[{\"Changes\":{\"workspace\":{\"Known\":{\"directory\":\"/src/app\",\"id\":\"/src/app\",\"kind\":\"Worktree\",\"name\":\"app\",\"provider\":\"mock\",\"repository_root\":\"/src/app\"}},\"status\":{\"Status\":{\"ahead\":1,\"base\":{\"Base\":\"main\"},\"behind\":0,\"branch\":{\"Branch\":\"fix-tests\"},\"dirty\":true,\"upstream\":\"NoUpstream\"}},\"changes\":{\"scope\":\"Uncommitted\",\"fingerprint\":\"f1\",\"files\":[]},\"commits\":[]}}]}]}")
    (run-effect 4)
    (expect-text (test-id "ahead-behind") "1 ahead / 0 behind main")
    ; Clicking its other session focuses that one.
    (click (role button :name "Fix tests"))
    (expect-text (test-id "session-title") "Fix tests")
    (click (role button :name "App"))
    (expect-absent (role button :name "main"))
  )
)

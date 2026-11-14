(test "Liton — a saved version 2 layout of the old default loads as the Developer Workbench"
  (setup
    (local-storage "liton.snapshot" "{\"columns\":[{\"active\":\"pane-1\",\"id\":\"column-1\",\"panes\":[{\"id\":\"pane-1\",\"pinned\":\"\",\"widget\":\"sessions\"}],\"size\":1,\"tabbed\":false},{\"active\":\"pane-2\",\"id\":\"column-2\",\"panes\":[{\"id\":\"pane-2\",\"pinned\":\"\",\"widget\":\"chat\"}],\"size\":3,\"tabbed\":false},{\"active\":\"pane-3\",\"id\":\"column-3\",\"panes\":[{\"id\":\"pane-3\",\"pinned\":\"\",\"widget\":\"capabilities\"}],\"size\":1,\"tabbed\":false}],\"version\":2}"))
  (steps
    (expect-text (test-id "show-right") "Changes")
    (expect-absent (label "Make column wider"))
    (click (role button :name "Left drawer"))
    (expect-local-storage "liton.snapshot" "{\"collapsed\":[\"Left\"],\"columns\":[{\"active\":\"pane-1\",\"id\":\"column-1\",\"panes\":[{\"id\":\"pane-1\",\"options\":[],\"pinned\":\"\",\"widget\":\"workspaces\"}],\"size\":1,\"tabbed\":true},{\"active\":\"pane-2\",\"id\":\"column-2\",\"panes\":[{\"id\":\"pane-2\",\"options\":[],\"pinned\":\"\",\"widget\":\"chat\"}],\"size\":1,\"tabbed\":true},{\"active\":\"pane-3\",\"id\":\"column-3\",\"panes\":[{\"id\":\"pane-3\",\"options\":[],\"pinned\":\"\",\"widget\":\"changes\"}],\"size\":1,\"tabbed\":true}],\"shell\":\"Workbench\",\"theme\":\"\",\"version\":5}")
  )
)

(test "Liton — a saved version 3 layout loads with each option's default, and is saved back as version 5 with those set"
  (setup
    (local-storage "liton.snapshot" "{\"columns\":[{\"active\":\"pane-1\",\"id\":\"column-1\",\"panes\":[{\"id\":\"pane-1\",\"pinned\":\"\",\"widget\":\"sessions\"}],\"size\":1,\"tabbed\":true},{\"active\":\"pane-2\",\"id\":\"column-2\",\"panes\":[{\"id\":\"pane-2\",\"pinned\":\"\",\"widget\":\"chat\"}],\"size\":1,\"tabbed\":true},{\"active\":\"pane-4\",\"id\":\"column-3\",\"panes\":[{\"id\":\"pane-3\",\"pinned\":\"\",\"widget\":\"changes\"},{\"id\":\"pane-4\",\"pinned\":\"\",\"widget\":\"capabilities\"}],\"size\":1,\"tabbed\":true}],\"shell\":\"Workbench\",\"version\":3}"))
  (steps
    (expect-text (test-id "show-right") "Changes · Capabilities")
    (click (role button :name "Settings"))
    (expect-value (label "Tool output") "Folded")
    (expect-checked (label "Show status lines") true)
    (expect-checked (label "Show agent") true)
    (select-option (label "Tool output") "Full")
    (expect-local-storage "liton.snapshot" "{\"collapsed\":[],\"columns\":[{\"active\":\"pane-1\",\"id\":\"column-1\",\"panes\":[{\"id\":\"pane-1\",\"options\":[],\"pinned\":\"\",\"widget\":\"sessions\"}],\"size\":1,\"tabbed\":true},{\"active\":\"pane-2\",\"id\":\"column-2\",\"panes\":[{\"id\":\"pane-2\",\"options\":[{\"key\":\"tool_output\",\"value\":\"Full\"}],\"pinned\":\"\",\"widget\":\"chat\"}],\"size\":1,\"tabbed\":true},{\"active\":\"pane-4\",\"id\":\"column-3\",\"panes\":[{\"id\":\"pane-3\",\"options\":[],\"pinned\":\"\",\"widget\":\"changes\"},{\"id\":\"pane-4\",\"options\":[],\"pinned\":\"\",\"widget\":\"capabilities\"}],\"size\":1,\"tabbed\":true}],\"shell\":\"Workbench\",\"theme\":\"\",\"version\":5}")
  )
)

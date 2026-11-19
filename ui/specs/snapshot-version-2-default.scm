(test "Liton — a saved version 2 layout of the old default loads as the Developer Workbench"
  (setup
    (local-storage "liton.snapshot" "{\"columns\":[{\"active\":\"pane-1\",\"id\":\"column-1\",\"panes\":[{\"id\":\"pane-1\",\"pinned\":\"\",\"widget\":\"sessions\"}],\"size\":1,\"tabbed\":false},{\"active\":\"pane-2\",\"id\":\"column-2\",\"panes\":[{\"id\":\"pane-2\",\"pinned\":\"\",\"widget\":\"chat\"}],\"size\":3,\"tabbed\":false},{\"active\":\"pane-3\",\"id\":\"column-3\",\"panes\":[{\"id\":\"pane-3\",\"pinned\":\"\",\"widget\":\"capabilities\"}],\"size\":1,\"tabbed\":false}],\"version\":2}"))
  (steps
    (expect-text (test-id "show-right") "Changes · Files · Tickets")
    (expect-absent (label "Make tile wider") :never-drawn)
    (click (role button :name "Left drawer"))
    (expect-local-storage "liton.snapshot" "{\"surfaces\":[{\"name\":\"\",\"snapshot\":{\"collapsed\":[\"Left\"],\"grid\":{\"columns\":[1,1,1],\"rows\":[1],\"tiles\":[{\"active\":\"pane-1\",\"bottom\":1,\"id\":\"tile-1\",\"left\":0,\"panes\":[{\"id\":\"pane-1\",\"options\":[{\"key\":\"group_by\",\"value\":\"Status\"},{\"key\":\"sessions\",\"value\":\"Tabs\"}],\"pinned\":\"\",\"widget\":\"workspaces\"}],\"right\":1,\"top\":0},{\"active\":\"pane-2\",\"bottom\":1,\"id\":\"tile-2\",\"left\":1,\"panes\":[{\"id\":\"pane-2\",\"options\":[],\"pinned\":\"\",\"widget\":\"chat\"},{\"id\":\"pane-8\",\"options\":[],\"pinned\":\"\",\"widget\":\"ticket\"}],\"right\":2,\"top\":0},{\"active\":\"pane-3\",\"bottom\":1,\"id\":\"tile-3\",\"left\":2,\"panes\":[{\"id\":\"pane-3\",\"options\":[],\"pinned\":\"\",\"widget\":\"changes\"},{\"id\":\"pane-4\",\"options\":[],\"pinned\":\"\",\"widget\":\"files\"},{\"id\":\"pane-5\",\"options\":[],\"pinned\":\"\",\"widget\":\"tickets\"}],\"right\":3,\"top\":0}]},\"hidden\":[\"pane-8\"],\"shell\":\"Workbench\",\"theme\":\"\",\"version\":9}}],\"version\":9}")
  )
)

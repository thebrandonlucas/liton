(test "Liton — a saved version 1 layout loads in Tiling, and is saved back as version 5"
  (setup
    (local-storage "liton.snapshot" "{\"version\":1,\"panes\":[{\"id\":\"pane-7\",\"widget\":\"chat\",\"pinned\":\"\"},{\"id\":\"pane-8\",\"widget\":\"capabilities\",\"pinned\":\"\"}]}"))
  (steps
    ; Each pane of a version 1 layout gets a column of its own.
    (expect-visible (role button :name "Chat"))
    (expect-visible (role button :name "Capabilities"))
    (expect-absent (role region :name "Sessions"))
    ; The first change saves the layout, as version 3.
    (click (label "Make column wider"))
    (expect-local-storage "liton.snapshot" "{\"collapsed\":[],\"columns\":[{\"active\":\"pane-7\",\"id\":\"column-1\",\"panes\":[{\"id\":\"pane-7\",\"options\":[],\"pinned\":\"\",\"widget\":\"chat\"}],\"size\":2,\"tabbed\":false},{\"active\":\"pane-8\",\"id\":\"column-2\",\"panes\":[{\"id\":\"pane-8\",\"options\":[],\"pinned\":\"\",\"widget\":\"capabilities\"}],\"size\":1,\"tabbed\":false}],\"shell\":\"Tiling\",\"theme\":\"\",\"version\":5}")
  )
)

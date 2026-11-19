(test "Liton — a saved version 1 layout loads in Tiling, and is saved back in the current version, as a deck of it alone"
  (setup
    (local-storage "liton.snapshot" "{\"version\":1,\"panes\":[{\"id\":\"pane-7\",\"widget\":\"chat\",\"pinned\":\"\"},{\"id\":\"pane-8\",\"widget\":\"capabilities\",\"pinned\":\"\"}]}"))
  (steps
    ; Each pane of a version 1 layout gets a tile of its own.
    (expect-visible (role button :name "Chat"))
    (expect-visible (role button :name "Capabilities"))
    (expect-absent (role region :name "Sessions") :never-drawn)
    ; The first change saves the layout, in the current version.
    (click (label "Make tile wider"))
    (expect-local-storage "liton.snapshot" "{\"surfaces\":[{\"name\":\"\",\"snapshot\":{\"collapsed\":[],\"grid\":{\"columns\":[3,2],\"rows\":[1],\"tiles\":[{\"active\":\"pane-7\",\"bottom\":1,\"id\":\"column-1\",\"left\":0,\"panes\":[{\"id\":\"pane-7\",\"options\":[],\"pinned\":\"\",\"widget\":\"chat\"}],\"right\":1,\"top\":0},{\"active\":\"pane-8\",\"bottom\":1,\"id\":\"column-2\",\"left\":1,\"panes\":[{\"id\":\"pane-8\",\"options\":[],\"pinned\":\"\",\"widget\":\"capabilities\"}],\"right\":2,\"top\":0}]},\"hidden\":[],\"shell\":\"Tiling\",\"theme\":\"\",\"version\":9}}],\"version\":9}")
  )
)

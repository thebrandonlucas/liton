(test "Liton — a role the daemon says is locked shows no Settings and no pane menus, and its keys don't open Settings, so its layout stays as it is"
  (setup
    (local-storage "liton.snapshot" "{\"version\":6,\"shell\":\"Tiling\",\"columns\":[{\"id\":\"column-1\",\"size\":1,\"tabbed\":false,\"active\":\"pane-1\",\"panes\":[{\"id\":\"pane-1\",\"widget\":\"rooms\",\"pinned\":\"\",\"options\":[]}]}],\"collapsed\":[],\"hidden\":[],\"theme\":\"\"}"))
  (steps
    (expect-visible (role button :name "Settings"))
    (expect-visible (role button :name "Rooms menu"))
    (press "Control+,")
    (expect-visible (role region :name "Settings"))
    (press "Control+,")
    (expect-absent (role region :name "Settings"))
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"rooms\",\"version\":1}],\"id\":\"relay\",\"name\":\"Relay\"}],\"transformers\":[],\"topics\":[],\"access\":{\"role\":\"staff\",\"locked\":true}}")
    (run-effect 1)
    (expect-absent (role button :name "Settings"))
    (expect-absent (role button :name "Rooms menu"))
    (press "Control+,")
    (expect-absent (role region :name "Settings"))
  )
)

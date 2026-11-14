(test "Liton — a saved version 4 layout shows the setup's default theme, and a theme picked is saved with it as version 5"
  (setup
    (local-storage "liton.snapshot" "{\"collapsed\":[\"Right\"],\"columns\":[{\"active\":\"pane-1\",\"id\":\"column-1\",\"panes\":[{\"id\":\"pane-1\",\"options\":[],\"pinned\":\"\",\"widget\":\"sessions\"}],\"size\":1,\"tabbed\":true},{\"active\":\"pane-2\",\"id\":\"column-2\",\"panes\":[{\"id\":\"pane-2\",\"options\":[],\"pinned\":\"\",\"widget\":\"chat\"}],\"size\":1,\"tabbed\":true},{\"active\":\"pane-3\",\"id\":\"column-3\",\"panes\":[{\"id\":\"pane-3\",\"options\":[],\"pinned\":\"\",\"widget\":\"changes\"}],\"size\":1,\"tabbed\":true}],\"shell\":\"Workbench\",\"version\":4}"))
  (steps
    (expect-attr (role button :name "Right drawer") aria-expanded "false")
    (click (role button :name "Settings"))
    (expect-attr (role button :name "Pastoral theme") aria-pressed "true")
    (click (role button :name "Hypr theme"))
    (expect-attr (role button :name "Hypr theme") aria-pressed "true")
    (expect-attr (role button :name "Pastoral theme") aria-pressed "false")
    (expect-local-storage "liton.snapshot" "{\"collapsed\":[\"Right\"],\"columns\":[{\"active\":\"pane-1\",\"id\":\"column-1\",\"panes\":[{\"id\":\"pane-1\",\"options\":[],\"pinned\":\"\",\"widget\":\"sessions\"}],\"size\":1,\"tabbed\":true},{\"active\":\"pane-2\",\"id\":\"column-2\",\"panes\":[{\"id\":\"pane-2\",\"options\":[],\"pinned\":\"\",\"widget\":\"chat\"}],\"size\":1,\"tabbed\":true},{\"active\":\"pane-3\",\"id\":\"column-3\",\"panes\":[{\"id\":\"pane-3\",\"options\":[],\"pinned\":\"\",\"widget\":\"changes\"}],\"size\":1,\"tabbed\":true}],\"shell\":\"Workbench\",\"theme\":\"Hypr\",\"version\":5}")
    (navigate "/")
    (click (role button :name "Settings"))
    (expect-attr (role button :name "Hypr theme") aria-pressed "true")
    (uncheck (label "Glass"))
    (expect-local-storage "liton.glass" "off")
  )
)

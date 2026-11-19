(test "Liton — dragging a tab or a pane's header shows the layout as if dropped where it is, drops it there, and Escape or a drop outside leaves it"
  (setup
    ; The Developer layout with Workspaces listing sessions as rows, under their projects.
    (local-storage "liton.snapshot" "{\"collapsed\":[],\"grid\":{\"columns\":[1,1,1],\"rows\":[1],\"tiles\":[{\"active\":\"pane-1\",\"bottom\":1,\"id\":\"tile-1\",\"left\":0,\"panes\":[{\"id\":\"pane-1\",\"options\":[],\"pinned\":\"\",\"widget\":\"workspaces\"}],\"right\":1,\"top\":0},{\"active\":\"pane-2\",\"bottom\":1,\"id\":\"tile-2\",\"left\":1,\"panes\":[{\"id\":\"pane-2\",\"options\":[],\"pinned\":\"\",\"widget\":\"chat\"},{\"id\":\"pane-8\",\"options\":[],\"pinned\":\"\",\"widget\":\"ticket\"}],\"right\":2,\"top\":0},{\"active\":\"pane-3\",\"bottom\":1,\"id\":\"tile-3\",\"left\":2,\"panes\":[{\"id\":\"pane-3\",\"options\":[],\"pinned\":\"\",\"widget\":\"changes\"},{\"id\":\"pane-4\",\"options\":[],\"pinned\":\"\",\"widget\":\"files\"},{\"id\":\"pane-5\",\"options\":[],\"pinned\":\"\",\"widget\":\"tickets\"}],\"right\":3,\"top\":0}]},\"hidden\":[\"pane-8\"],\"shell\":\"Workbench\",\"theme\":\"\",\"version\":8}"))
  (steps
    ; Held, the page reports the pointer; over the chat's tile, the main area
    ; shows the Files tab already, the dragged pane faded, and a ghost of it
    ; follows the pointer.
    (pointer-down (role button :name "Files"))
    (expect-port-subscriptions "liton/drag/pointer" 1)
    (emit-port "liton/drag/pointer" "{\"phase\":\"Moved\",\"x\":600,\"y\":400,\"tile\":\"tile-2\",\"tab\":\"\",\"across\":5000,\"down\":5000}")
    (expect-text (test-id "show-main") "Chat · Files")
    (expect-text (test-id "show-right") "Changes · Tickets")
    (expect-attr (test-id "slot-main") class "tile slot slot-main tabbed drop-into")
    (expect-attr (role region :name "Files") class "pane dragged")
    (expect-text (test-id "drag-ghost") "Files")
    ; Released there, it stays, and the page stops reporting.
    (emit-port "liton/drag/pointer" "{\"phase\":\"Released\",\"x\":600,\"y\":400,\"tile\":\"tile-2\",\"tab\":\"\",\"across\":5000,\"down\":5000}")
    (pointer-up (role button :name "Files"))
    (expect-port-subscriptions "liton/drag/pointer" 0)
    (expect-absent (test-id "drag-ghost"))
    (expect-text (test-id "show-main") "Chat · Files")
    (expect-attr (test-id "slot-main") class "tile slot slot-main tabbed")
    (expect-attr (role button :name "Files") aria-pressed "true")
    ; Over a tab's left half, it goes before it.
    (pointer-down (role button :name "Files"))
    (emit-port "liton/drag/pointer" "{\"phase\":\"Moved\",\"x\":600,\"y\":400,\"tile\":\"tile-2\",\"tab\":\"pane-2\",\"across\":1000,\"down\":5000}")
    (expect-text (test-id "show-main") "Files · Chat")
    (emit-port "liton/drag/pointer" "{\"phase\":\"Released\",\"x\":600,\"y\":400,\"tile\":\"tile-2\",\"tab\":\"pane-2\",\"across\":1000,\"down\":5000}")
    (pointer-up (role button :name "Files"))
    (expect-text (test-id "show-main") "Files · Chat")
    ; Over the bottom fifth of a drawer, a new tile opens below it, the main
    ; area spanning both rows.
    (pointer-down (role button :name "Files"))
    (emit-port "liton/drag/pointer" "{\"phase\":\"Moved\",\"x\":600,\"y\":400,\"tile\":\"tile-3\",\"tab\":\"\",\"across\":5000,\"down\":9500}")
    (expect-text (test-id "show-main") "Chat")
    (expect-visible (role button :name "Files"))
    ; The chat doesn't fit the left drawer, so over it the layout is as it was.
    (emit-port "liton/drag/pointer" "{\"phase\":\"Moved\",\"x\":600,\"y\":400,\"tile\":\"tile-1\",\"tab\":\"\",\"across\":5000,\"down\":5000}")
    (expect-text (test-id "show-main") "Files · Chat")
    ; Escape leaves the drag, and so does a release outside the tiles.
    (emit-port "liton/drag/pointer" "{\"phase\":\"Moved\",\"x\":600,\"y\":400,\"tile\":\"tile-3\",\"tab\":\"\",\"across\":5000,\"down\":5000}")
    (expect-text (test-id "show-right") "Changes · Tickets · Files")
    (press "Escape")
    (pointer-up (role button :name "Files"))
    (expect-text (test-id "show-right") "Changes · Tickets")
    (expect-text (test-id "show-main") "Files · Chat")
    (expect-port-subscriptions "liton/drag/pointer" 0)
    (pointer-down (role button :name "Files"))
    (emit-port "liton/drag/pointer" "{\"phase\":\"Moved\",\"x\":600,\"y\":400,\"tile\":\"tile-3\",\"tab\":\"\",\"across\":5000,\"down\":5000}")
    (emit-port "liton/drag/pointer" "{\"phase\":\"Released\",\"x\":600,\"y\":400,\"tile\":\"\",\"tab\":\"\",\"across\":5000,\"down\":5000}")
    (pointer-up (role button :name "Files"))
    (expect-text (test-id "show-main") "Files · Chat")
    ; A press released without moving is a click.
    (pointer-down (role button :name "Chat"))
    (pointer-up (role button :name "Chat"))
    (expect-port-subscriptions "liton/drag/pointer" 0)
    ; In Tiling, a header drops into a tile's tabs, or by a tile's edge into
    ; a new tile.
    (click (role button :name "Settings"))
    (click (role button :name "Tiling preset"))
    (click (role button :name "Settings"))
    (pointer-down (test-id "grip-pane-1"))
    (emit-port "liton/drag/pointer" "{\"phase\":\"Moved\",\"x\":600,\"y\":400,\"tile\":\"tile-2\",\"tab\":\"\",\"across\":5000,\"down\":5000}")
    (emit-port "liton/drag/pointer" "{\"phase\":\"Released\",\"x\":600,\"y\":400,\"tile\":\"tile-2\",\"tab\":\"\",\"across\":5000,\"down\":5000}")
    (pointer-up (test-id "grip-pane-1"))
    (expect-visible (role button :name "Chat · Sessions"))
    (pointer-down (test-id "grip-pane-1"))
    (emit-port "liton/drag/pointer" "{\"phase\":\"Moved\",\"x\":600,\"y\":400,\"tile\":\"tile-3\",\"tab\":\"\",\"across\":9500,\"down\":5000}")
    (emit-port "liton/drag/pointer" "{\"phase\":\"Released\",\"x\":600,\"y\":400,\"tile\":\"tile-3\",\"tab\":\"\",\"across\":9500,\"down\":5000}")
    (pointer-up (test-id "grip-pane-1"))
    (expect-absent (role button :name "Chat · Sessions"))
    (expect-visible (role button :name "Sessions"))
  )
)

(test "Liton — a message's thread opens from its replies beside the room, with who types in it, and closes with ×"
  (setup
    (local-storage "liton.snapshot" "{\"version\":6,\"shell\":\"Tiling\",\"columns\":[{\"id\":\"column-1\",\"size\":1,\"tabbed\":false,\"active\":\"pane-1\",\"panes\":[{\"id\":\"pane-1\",\"widget\":\"rooms\",\"pinned\":\"\",\"options\":[]}]}],\"collapsed\":[],\"hidden\":[],\"theme\":\"\"}"))
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"rooms\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    ; The poll sent before the manifest arrived, for every capability.
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[]}")
    (run-effect 2)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"rooms.v1\",\"topic\":\"rooms\",\"cursor\":\"r1\",\"events\":[{\"Rooms\":[{\"id\":\"general\",\"provider\":\"mock\",\"name\":\"general\",\"kind\":\"Channel\",\"private\":false,\"archived\":false,\"joined\":true,\"unread\":\"Unknown\",\"links\":[],\"me\":\"you\"},{\"id\":\"ideas\",\"provider\":\"mock\",\"name\":\"ideas\",\"kind\":\"Forum\",\"private\":false,\"archived\":false,\"joined\":true,\"unread\":\"Unknown\",\"links\":[],\"me\":\"you\"}]}]}]}")
    (run-effect 3)
    (click (role button :name "#general"))
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"rooms.v1\",\"topic\":\"rooms\",\"cursor\":\"r1\",\"events\":[]},{\"capability\":\"rooms.v1\",\"topic\":\"messages/general\",\"cursor\":\"2\",\"events\":[{\"RoomEntry\":{\"sequence\":1,\"event\":{\"Posted\":{\"id\":\"general-1\",\"room_id\":\"general\",\"author\":\"ada\",\"text\":\"Why does logging in loop?\",\"time\":\"2026-01-01T09:00:00.000Z\",\"place\":\"TopLevel\",\"mentions\":[\"scout\"],\"reactions\":[],\"edited\":false,\"deleted\":false}}}},{\"RoomEntry\":{\"sequence\":2,\"event\":{\"Threaded\":{\"root\":\"general-1\",\"replies\":1,\"last_reply\":\"2026-01-01T09:01:00.000Z\",\"participants\":[\"scout\"]}}}}]},{\"capability\":\"rooms.v1\",\"topic\":\"members/general\",\"cursor\":\"m1\",\"events\":[{\"Members\":[{\"id\":\"you\",\"provider\":\"mock\",\"name\":\"You\",\"kind\":\"Person\",\"role\":\"Owner\",\"presence\":\"Online\"},{\"id\":\"ada\",\"provider\":\"mock\",\"name\":\"Ada\",\"kind\":\"Person\",\"role\":\"Admin\",\"presence\":\"Away\"},{\"id\":\"scout\",\"provider\":\"mock\",\"name\":\"Scout\",\"kind\":{\"Agent\":{\"owner\":\"you\"}},\"role\":\"Member\",\"presence\":\"Online\"},{\"id\":\"patch\",\"provider\":\"mock\",\"name\":\"Patch\",\"kind\":{\"Agent\":{\"owner\":\"ada\"}},\"role\":\"Member\",\"presence\":\"Online\"}]}]}]}")
    (run-effect 4)
    (click (role button :name "1 reply · Scout"))
    ; Opened at once, its replies loading.
    (expect-visible (role region :name "Thread"))
    (expect-visible (text "Loading…"))
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"rooms.v1\",\"topic\":\"rooms\",\"cursor\":\"r1\",\"events\":[]},{\"capability\":\"rooms.v1\",\"topic\":\"messages/general\",\"cursor\":\"2\",\"events\":[]},{\"capability\":\"rooms.v1\",\"topic\":\"members/general\",\"cursor\":\"m1\",\"events\":[]},{\"capability\":\"rooms.v1\",\"topic\":\"thread/general/general-1\",\"cursor\":\"5\",\"events\":[{\"RoomEntry\":{\"sequence\":4,\"event\":{\"Posted\":{\"id\":\"general-2\",\"room_id\":\"general\",\"author\":\"scout\",\"text\":\"Found it in `src/Auth.roc`\",\"time\":\"2026-01-01T09:01:00.000Z\",\"place\":{\"Reply\":{\"root\":\"general-1\",\"parent\":\"general-1\"}},\"mentions\":[],\"reactions\":[],\"edited\":false,\"deleted\":false}}}},{\"RoomEntry\":{\"sequence\":5,\"event\":{\"Typing\":{\"member\":\"ada\",\"place\":{\"Reply\":{\"root\":\"general-1\",\"parent\":\"general-2\"}}}}}}]}]}")
    (run-effect 5)
    (expect-absent (text "Loading…"))
    (expect-visible (text "src/Auth.roc"))
    (expect-text (test-id "thread-typing") "Ada is typing…")
    (click (role button :name "Close the thread"))
    (expect-absent (role region :name "Thread"))
    (expect-absent (text "src/Auth.roc"))
  )
)

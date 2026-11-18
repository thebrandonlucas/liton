(test "Liton — typing @ in a room's composer offers its other members to mention, and picking one completes the name"
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
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"rooms.v1\",\"topic\":\"rooms\",\"cursor\":\"r1\",\"events\":[]},{\"capability\":\"rooms.v1\",\"topic\":\"messages/general\",\"cursor\":\"1\",\"events\":[{\"RoomEntry\":{\"sequence\":1,\"event\":{\"Posted\":{\"id\":\"general-1\",\"room_id\":\"general\",\"author\":\"ada\",\"text\":\"Who can look at the build?\",\"time\":\"2026-01-01T09:00:00.000Z\",\"place\":\"TopLevel\",\"mentions\":[],\"reactions\":[],\"edited\":false,\"deleted\":false}}}}]},{\"capability\":\"rooms.v1\",\"topic\":\"members/general\",\"cursor\":\"m1\",\"events\":[{\"Members\":[{\"id\":\"you\",\"provider\":\"mock\",\"name\":\"You\",\"kind\":\"Person\",\"role\":\"Owner\",\"presence\":\"Online\"},{\"id\":\"ada\",\"provider\":\"mock\",\"name\":\"Ada\",\"kind\":\"Person\",\"role\":\"Admin\",\"presence\":\"Away\"},{\"id\":\"scout\",\"provider\":\"mock\",\"name\":\"Scout\",\"kind\":{\"Agent\":{\"owner\":\"you\"}},\"role\":\"Member\",\"presence\":\"Online\"},{\"id\":\"patch\",\"provider\":\"mock\",\"name\":\"Patch\",\"kind\":{\"Agent\":{\"owner\":\"ada\"}},\"role\":\"Member\",\"presence\":\"Online\"}]}]}]}")
    (run-effect 4)
    (fill (label "Your message") "Thanks @")
    ; Everyone but you, until the name narrows them.
    (expect-visible (role button :name "@Ada"))
    (expect-absent (role button :name "@You") :never-drawn)
    (fill (label "Your message") "Thanks @sc")
    (expect-absent (role button :name "@Ada"))
    (click (role button :name "@Scout"))
    (expect-value (label "Your message") "Thanks @Scout ")
    (expect-absent (role button :name "@Scout"))
    (click (role button :name "Send to the room"))
    (expect-pending-effects 1)
    (expect-text (test-id "room-sent-status") "Sending…")
  )
)

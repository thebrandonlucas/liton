(test "Liton — a message sent to a room shows at once as sending, and settles when the room posts it"
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
    (fill (label "Your message") "Morning **all**")
    (click (role button :name "Send to the room"))
    ; Shown before the daemon answers the send.
    (expect-pending-effects 1)
    (expect-text (test-id "room-sent-status") "Sending…")
    (expect-visible (text "all"))
    (expect-value (label "Your message") "")
    (stub-http "send" :url "/liton/v1/call" :status 200 :body "{\"Ok\":{\"Sent\":{\"message_id\":\"general-5\"}}}")
    (run-effect 5)
    ; Sent, it polls at once, and shows sending until the room posts it.
    (expect-pending-effects 1)
    (expect-text (test-id "room-sent-status") "Sending…")
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"rooms.v1\",\"topic\":\"rooms\",\"cursor\":\"r1\",\"events\":[]},{\"capability\":\"rooms.v1\",\"topic\":\"messages/general\",\"cursor\":\"5\",\"events\":[{\"RoomEntry\":{\"sequence\":5,\"event\":{\"Posted\":{\"id\":\"general-5\",\"room_id\":\"general\",\"author\":\"you\",\"text\":\"Morning **all**\",\"time\":\"2026-01-01T09:05:00.000Z\",\"place\":\"TopLevel\",\"mentions\":[],\"reactions\":[],\"edited\":false,\"deleted\":false}}}}]},{\"capability\":\"rooms.v1\",\"topic\":\"members/general\",\"cursor\":\"m1\",\"events\":[]}]}")
    (run-effect 6)
    (expect-absent (test-id "room-sent-status"))
    (expect-visible (text "all"))
    ; An empty message is not sent, and says why.
    (click (role button :name "Send to the room"))
    (expect-pending-effects 0)
    (expect-text (test-id "notice") "A message needs text.")
  )
)

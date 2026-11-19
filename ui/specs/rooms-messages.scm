(test "Liton — a room picked in Rooms shows in the Room pane a saved Rooms pane now comes with, with its messages: who wrote each, a person or an agent, its text as Markdown, edits, deletions, reactions and thread, and who is typing"
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
    (expect-visible (text "Pick a room in Rooms to show it here."))
    (click (role button :name "#general"))
    ; Opened at once, its messages loading.
    (expect-absent (text "Pick a room in Rooms to show it here."))
    (expect-visible (role status :name "Loading"))
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"rooms.v1\",\"topic\":\"rooms\",\"cursor\":\"r1\",\"events\":[]},{\"capability\":\"rooms.v1\",\"topic\":\"messages/general\",\"cursor\":\"8\",\"events\":[{\"RoomEntry\":{\"sequence\":1,\"event\":{\"Posted\":{\"id\":\"general-1\",\"room_id\":\"general\",\"author\":\"ada\",\"text\":\"**Why** does logging in loop?\",\"time\":\"2026-01-01T09:00:00.000Z\",\"place\":\"TopLevel\",\"mentions\":[\"scout\"],\"reactions\":[],\"edited\":false,\"deleted\":false}}}},{\"RoomEntry\":{\"sequence\":2,\"event\":{\"Posted\":{\"id\":\"general-3\",\"room_id\":\"general\",\"author\":\"you\",\"text\":\"Morning\",\"time\":\"2026-01-01T09:00:00.000Z\",\"place\":\"TopLevel\",\"mentions\":[],\"reactions\":[],\"edited\":false,\"deleted\":false}}}},{\"RoomEntry\":{\"sequence\":3,\"event\":{\"Threaded\":{\"root\":\"general-1\",\"replies\":2,\"last_reply\":\"2026-01-01T09:01:00.000Z\",\"participants\":[\"scout\",\"ada\"]}}}},{\"RoomEntry\":{\"sequence\":4,\"event\":{\"Reacted\":{\"id\":\"general-1\",\"emoji\":\"+\",\"by\":\"you\",\"added\":true}}}},{\"RoomEntry\":{\"sequence\":5,\"event\":{\"Edited\":{\"id\":\"general-3\",\"text\":\"Morning, all\"}}}},{\"RoomEntry\":{\"sequence\":6,\"event\":{\"Posted\":{\"id\":\"general-4\",\"room_id\":\"general\",\"author\":\"scout\",\"text\":\"Oops\",\"time\":\"2026-01-01T09:00:00.000Z\",\"place\":\"TopLevel\",\"mentions\":[],\"reactions\":[],\"edited\":false,\"deleted\":false}}}},{\"RoomEntry\":{\"sequence\":7,\"event\":{\"Deleted\":{\"id\":\"general-4\"}}}},{\"RoomEntry\":{\"sequence\":8,\"event\":{\"Typing\":{\"member\":\"patch\",\"place\":\"TopLevel\"}}}}]},{\"capability\":\"rooms.v1\",\"topic\":\"members/general\",\"cursor\":\"m1\",\"events\":[{\"Members\":[{\"id\":\"you\",\"provider\":\"mock\",\"name\":\"You\",\"kind\":\"Person\",\"role\":\"Owner\",\"presence\":\"Online\"},{\"id\":\"ada\",\"provider\":\"mock\",\"name\":\"Ada\",\"kind\":\"Person\",\"role\":\"Admin\",\"presence\":\"Away\"},{\"id\":\"scout\",\"provider\":\"mock\",\"name\":\"Scout\",\"kind\":{\"Agent\":{\"owner\":\"you\"}},\"role\":\"Member\",\"presence\":\"Online\"},{\"id\":\"patch\",\"provider\":\"mock\",\"name\":\"Patch\",\"kind\":{\"Agent\":{\"owner\":\"ada\"}},\"role\":\"Member\",\"presence\":\"Online\"}]}]}]}")
    (run-effect 4)
    (expect-absent (role status :name "Loading"))
    (expect-visible (text "Ada"))
    (expect-visible (text "Why"))
    (expect-visible (text " does logging in loop?"))
    (expect-visible (text "Morning, all"))
    (expect-visible (text "edited"))
    (expect-visible (text "This message was deleted."))
    (expect-visible (text "agent"))
    (expect-visible (text "+ 1"))
    (expect-text (test-id "room-replies") "2 replies · Scout, Ada")
    (expect-text (test-id "room-typing") "Patch is typing…")
    ; The rooms stay listed beside it.
    (expect-visible (role button :name "#ideas"))
  )
)

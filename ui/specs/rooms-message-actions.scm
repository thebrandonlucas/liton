(test "Liton — a message's actions copy a link to it, saying Copied at once, and reply in its thread"
  (setup
    (local-storage "liton.snapshot" "{\"version\":6,\"shell\":\"Tiling\",\"columns\":[{\"id\":\"column-1\",\"size\":1,\"tabbed\":false,\"active\":\"pane-1\",\"panes\":[{\"id\":\"pane-1\",\"widget\":\"rooms\",\"pinned\":\"\",\"options\":[]}]}],\"collapsed\":[],\"hidden\":[],\"theme\":\"\"}"))
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"rooms\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[]}")
    (run-effect 2)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"rooms.v1\",\"topic\":\"rooms\",\"cursor\":\"r1\",\"events\":[{\"Rooms\":[{\"id\":\"general\",\"provider\":\"mock\",\"name\":\"general\",\"kind\":\"Channel\",\"private\":false,\"archived\":false,\"joined\":true,\"unread\":\"Unknown\",\"links\":[],\"me\":\"you\"},{\"id\":\"ideas\",\"provider\":\"mock\",\"name\":\"ideas\",\"kind\":\"Forum\",\"private\":false,\"archived\":false,\"joined\":true,\"unread\":\"Unknown\",\"links\":[],\"me\":\"you\"}]}]}]}")
    (run-effect 3)
    (click (role button :name "#general"))
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"rooms.v1\",\"topic\":\"rooms\",\"cursor\":\"r1\",\"events\":[]},{\"capability\":\"rooms.v1\",\"topic\":\"messages/general\",\"cursor\":\"2\",\"events\":[{\"RoomEntry\":{\"sequence\":1,\"event\":{\"Posted\":{\"id\":\"general-1\",\"room_id\":\"general\",\"author\":\"ada\",\"text\":\"Why does logging in loop?\",\"time\":\"2026-01-01T09:00:00.000Z\",\"place\":\"TopLevel\",\"mentions\":[\"scout\"],\"reactions\":[],\"edited\":false,\"deleted\":false}}}},{\"RoomEntry\":{\"sequence\":2,\"event\":{\"Threaded\":{\"root\":\"general-1\",\"replies\":1,\"last_reply\":\"2026-01-01T09:01:00.000Z\",\"participants\":[\"scout\"]}}}}]},{\"capability\":\"rooms.v1\",\"topic\":\"members/general\",\"cursor\":\"m1\",\"events\":[{\"Members\":[{\"id\":\"you\",\"provider\":\"mock\",\"name\":\"You\",\"kind\":\"Person\",\"role\":\"Owner\",\"presence\":\"Online\"},{\"id\":\"ada\",\"provider\":\"mock\",\"name\":\"Ada\",\"kind\":\"Person\",\"role\":\"Admin\",\"presence\":\"Away\"},{\"id\":\"scout\",\"provider\":\"mock\",\"name\":\"Scout\",\"kind\":{\"Agent\":{\"owner\":\"you\"}},\"role\":\"Member\",\"presence\":\"Online\"},{\"id\":\"patch\",\"provider\":\"mock\",\"name\":\"Patch\",\"kind\":{\"Agent\":{\"owner\":\"ada\"}},\"role\":\"Member\",\"presence\":\"Online\"}]}]}]}")
    (run-effect 4)
    (expect-text (role button :name "Copy link") "Copy link")
    (click (role button :name "Copy link"))
    ; Copied before the clipboard answers.
    (expect-text (role button :name "Copy link") "Copied")
    (expect-port-call 5 "liton/copy" "\"room:general/general-1\"")
    (answer-port 5 reply "true")
    (click (role button :name "Reply in the thread"))
    (expect-visible (role region :name "Thread"))
    (expect-visible (label "Your reply"))
  )
)

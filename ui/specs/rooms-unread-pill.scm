(test "Liton — while an unread room's row is scrolled out of view, Rooms shows a pill counting the unread, which scrolls to it"
  (setup
    (local-storage "liton.snapshot" "{\"version\":6,\"shell\":\"Tiling\",\"columns\":[{\"id\":\"column-1\",\"size\":1,\"tabbed\":false,\"active\":\"pane-1\",\"panes\":[{\"id\":\"pane-1\",\"widget\":\"rooms\",\"pinned\":\"\",\"options\":[]}]}],\"collapsed\":[],\"hidden\":[],\"theme\":\"\"}"))
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"rooms\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[]}")
    (run-effect 2)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"rooms.v1\",\"topic\":\"rooms\",\"cursor\":\"r1\",\"events\":[{\"Rooms\":[{\"id\":\"general\",\"provider\":\"mock\",\"name\":\"general\",\"kind\":\"Channel\",\"private\":false,\"archived\":false,\"joined\":true,\"unread\":{\"Counted\":{\"messages\":3,\"mentions\":1}},\"links\":[],\"me\":\"you\"},{\"id\":\"releases\",\"provider\":\"mock\",\"name\":\"releases\",\"kind\":\"Announce\",\"private\":false,\"archived\":false,\"joined\":false,\"unread\":\"Unknown\",\"links\":[],\"me\":\"you\"}]}]}]}")
    (run-effect 3)
    (expect-absent (role button :name "Show the unread rooms"))
    (report-seen (role button :name "#general") no)
    (expect-text (role button :name "Show the unread rooms") "1 unread")
    ; A room read stays out of the count.
    (report-seen (role button :name "#releases") no)
    (expect-text (role button :name "Show the unread rooms") "1 unread")
    (click (role button :name "Show the unread rooms"))
    (expect-focused (role button :name "#general"))
    (report-seen (role button :name "#general") yes)
    (expect-absent (role button :name "Show the unread rooms"))
  )
)

(test "Liton — an inbox item says when its session nears or passed its context limit, as limits.v1 warns"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"protocol\":1,\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"topics\":[],\"transformers\":[{\"id\":\"attention\",\"name\":\"Attention\",\"offers\":{\"name\":\"attention\",\"version\":1},\"uses\":[{\"name\":\"chat\",\"version\":1}]}]}")
    (run-effect 1)
    (click (role button :name "Settings"))
    (click (role button :name "Inbox preset"))
    (click (role button :name "Settings"))
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"cursor\":\"c1\",\"events\":[{\"Sessions\":[{\"agent\":\"claude\",\"id\":\"s2\",\"provider\":\"mock\",\"status\":\"Finished\",\"title\":\"Fix tests\"},{\"agent\":\"claude\",\"id\":\"s3\",\"provider\":\"mock\",\"status\":\"Finished\",\"title\":\"Write docs\"}]}],\"topic\":\"sessions\"},{\"capability\":\"attention.v1\",\"cursor\":\"i1\",\"events\":[{\"Items\":[{\"agent\":\"claude\",\"permissions\":[],\"provider\":\"mock\",\"session_id\":\"s2\",\"set_aside\":\"No\",\"signature\":\"Done 1 Over\",\"state\":\"Done\",\"summary\":\"Fixed.\",\"title\":\"Fix tests\",\"unread\":true,\"updated\":\"2026-01-01T09:00:00.000Z\",\"warning\":\"Over its context limit: 85% of 80%. Compact it or start fresh\"},{\"agent\":\"claude\",\"permissions\":[],\"provider\":\"mock\",\"session_id\":\"s3\",\"set_aside\":\"No\",\"signature\":\"Done 1\",\"state\":\"Done\",\"summary\":\"Docs written.\",\"title\":\"Write docs\",\"unread\":true,\"updated\":\"2026-01-01T09:05:00.000Z\"}]}],\"topic\":\"items\"}]}")
    (run-effect 2)
    (expect-visible (text "Over its context limit: 85% of 80%. Compact it or start fresh"))
    (expect-attr (text "Over its context limit: 85% of 80%. Compact it or start fresh") class "limit-warning over")
  )
)

(test "Liton — the document title counts what needs you"
  (steps
    (stub-http "manifest" :url "/api/manifest" :status 200 :body "{\"protocol\":1,\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"},{\"capabilities\":[{\"name\":\"attention\",\"version\":1}],\"id\":\"liton\",\"name\":\"liton\"}]}")
    (run-effect 1)
    (expect-document-title "liton")
    (stub-http "attention" :url "/api/attention" :status 200 :body "[{\"agent\":\"claude\",\"permissions\":[],\"provider\":\"mock\",\"session_id\":\"s1\",\"set_aside\":\"No\",\"signature\":\"NeedsYou 3\",\"state\":\"NeedsYou\",\"summary\":\"\",\"title\":\"Fix tests\"},{\"agent\":\"claude\",\"permissions\":[],\"provider\":\"mock\",\"session_id\":\"s2\",\"set_aside\":\"No\",\"signature\":\"NeedsYou 1\",\"state\":\"NeedsYou\",\"summary\":\"\",\"title\":\"Write docs\"},{\"agent\":\"claude\",\"permissions\":[],\"provider\":\"mock\",\"session_id\":\"s3\",\"set_aside\":\"Settled\",\"signature\":\"NeedsYou 1\",\"state\":\"NeedsYou\",\"summary\":\"\",\"title\":\"Scratch\"}]")
    (run-effect 3)
    (expect-document-title "(2) liton")
  )
)

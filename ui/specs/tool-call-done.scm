(test "Liton — a tool call that succeeded shows done, with long output folded"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[{\"Sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Running\",\"title\":\"Fix tests\"}]}]}]}")
    (run-effect 2)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[]},{\"capability\":\"chat.v1\",\"topic\":\"timeline/s1\",\"cursor\":\"2\",\"events\":[{\"Entry\":{\"event\":{\"ToolCall\":{\"call_id\":\"c1\",\"input\":\"ls\",\"tool\":\"bash\"}},\"sequence\":1}},{\"Entry\":{\"event\":{\"ToolResult\":{\"call_id\":\"c1\",\"failed\":false,\"output\":\"a\\nb\\nc\\nd\\ne\\nf\"}},\"sequence\":2}}]}]}")
    (run-effect 3)
    (expect-text (test-id "tool-state") "done")
    (expect-visible (text "a\nb\nc\nd"))
    (expect-visible (text "2 more lines"))
    (expect-visible (text "e\nf"))
  )
)

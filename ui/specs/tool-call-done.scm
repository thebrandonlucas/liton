(test "Liton — a tool call that succeeded shows done, with long output folded"
  (steps
    (stub-http "manifest" :url "/api/manifest" :status 200 :body "{\"protocol\":1,\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}]}")
    (run-effect 1)
    (stub-http "poll" :url "/api/chat/poll" :status 200 :body "{\"sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Running\",\"title\":\"Fix tests\"}],\"timelines\":[{\"session_id\":\"s1\",\"entries\":[{\"event\":{\"ToolCall\":{\"call_id\":\"c1\",\"input\":\"ls\",\"tool\":\"bash\"}},\"sequence\":1},{\"event\":{\"ToolResult\":{\"call_id\":\"c1\",\"failed\":false,\"output\":\"a\\nb\\nc\\nd\\ne\\nf\"}},\"sequence\":2}]}]}")
    (run-effect 2)
    (stub-http "poll" :url "/api/chat/poll" :status 200 :body "{\"sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Running\",\"title\":\"Fix tests\"}],\"timelines\":[{\"session_id\":\"s1\",\"entries\":[{\"event\":{\"ToolCall\":{\"call_id\":\"c1\",\"input\":\"ls\",\"tool\":\"bash\"}},\"sequence\":1},{\"event\":{\"ToolResult\":{\"call_id\":\"c1\",\"failed\":false,\"output\":\"a\\nb\\nc\\nd\\ne\\nf\"}},\"sequence\":2}]}]}")
    (run-effect 3)
    (expect-text (test-id "tool-state") "done")
    (expect-visible (text "a\nb\nc\nd"))
    (expect-visible (text "2 more lines"))
    (expect-visible (text "e\nf"))
  )
)

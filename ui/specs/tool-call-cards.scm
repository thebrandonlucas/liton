(test "Liton — a tool call and its result show as one card"
  (steps
    (stub-http "manifest" :url "/api/manifest" :status 200 :body "{\"protocol\":1,\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}]}")
    (run-effect 1)
    (stub-http "poll" :url "/api/chat/poll" :status 200 :body "{\"sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Running\",\"title\":\"Fix tests\"}],\"timelines\":[]}")
    (run-effect 2)
    (stub-http "poll" :url "/api/chat/poll" :status 200 :body "{\"sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Running\",\"title\":\"Fix tests\"}],\"timelines\":[{\"session_id\":\"s1\",\"entries\":[{\"event\":{\"ToolCall\":{\"call_id\":\"c1\",\"input\":\"zig build test\",\"tool\":\"bash\"}},\"sequence\":1}]}]}")
    (run-effect 3)
    (expect-text (test-id "tool-state") "running")
    (expect-visible (text "zig build test"))
    ; The result fills in its call's card: no entry of its own.
    (mark-metrics)
    (stub-http "poll" :url "/api/chat/poll" :status 200 :body "{\"sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Running\",\"title\":\"Fix tests\"}],\"timelines\":[{\"session_id\":\"s1\",\"entries\":[{\"event\":{\"ToolResult\":{\"call_id\":\"c1\",\"failed\":true,\"output\":\"1 failed\"}},\"sequence\":2}]}]}")
    (run-effect 4)
    (expect-metric-delta rows_created 0)
    (expect-text (test-id "tool-state") "failed")
    (expect-visible (text "1 failed"))
  )
)

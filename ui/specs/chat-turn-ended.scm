(test "Liton — a turn's end says how long the agent worked, and Collapse Turns folds a turn where it ends"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    ; Listed as running still, but its timeline says the turn ended.
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[{\"Sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Running\",\"title\":\"Fix tests\"}]}]}]}")
    (run-effect 2)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[]},{\"capability\":\"chat.v1\",\"topic\":\"timeline/s1\",\"cursor\":\"6\",\"events\":[{\"Entry\":{\"event\":{\"UserMessage\":{\"text\":\"Fix the test\"}},\"sequence\":1}},{\"Entry\":{\"event\":{\"ToolCall\":{\"call_id\":\"c1\",\"input\":\"zig build test\",\"tool\":\"bash\"}},\"sequence\":2}},{\"Entry\":{\"event\":{\"ToolResult\":{\"call_id\":\"c1\",\"failed\":false,\"output\":\"ok\"}},\"sequence\":3}},{\"Entry\":{\"event\":{\"AgentMessage\":{\"text\":\"Fixed it.\"}},\"sequence\":4}},{\"Entry\":{\"event\":{\"TurnEnded\":{\"ended\":\"2026-01-01T10:02:14.000Z\",\"started\":\"2026-01-01T10:00:00.000Z\"}},\"sequence\":5}},{\"Entry\":{\"event\":{\"TurnEnded\":{\"ended\":\"2026-01-01T10:03:00.000Z\"}},\"sequence\":6}}]}]}")
    (run-effect 3)
    (expect-visible (text "Worked for 2m 14s"))
    (expect-visible (text "zig build test"))
    (click (role button :name "Settings"))
    (select-option (label "Collapse") "Turns")
    (expect-absent (text "zig build test"))
    (expect-visible (role button :name "1 tool call"))
    (expect-visible (text "Fixed it."))
    (expect-visible (text "Worked for 2m 14s"))
  )
)

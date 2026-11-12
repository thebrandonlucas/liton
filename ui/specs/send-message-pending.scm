(test "Liton — a sent message shows at once as sending, and settles when the timeline has it"
  (steps
    (stub-http "manifest" :url "/api/manifest" :status 200 :body "{\"protocol\":1,\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}]}")
    (run-effect 1)
    (stub-http "poll" :url "/api/chat/poll" :status 200 :body "{\"sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Scratch\"}],\"timelines\":[]}")
    (run-effect 2)
    ; The chat follows Scratch before its timeline arrives.
    (expect-visible (text "Loading…"))
    (stub-http "poll" :url "/api/chat/poll" :status 200 :body "{\"sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Scratch\"}],\"timelines\":[{\"session_id\":\"s1\",\"entries\":[{\"event\":{\"StatusChanged\":\"Idle\"},\"sequence\":1}]}]}")
    (run-effect 3)
    (expect-absent (text "Loading…"))
    (fill (label "Message") "Find the TODOs")
    (click (role button :name "Send"))
    ; Shown before the daemon answers the send.
    (expect-pending-effects 2)
    (expect-visible (text "Find the TODOs"))
    (expect-text (test-id "sent-status") "Sending…")
    (expect-value (label "Message") "")
    (stub-http "send" :url "/api/chat" :status 200 :body "\"Accepted\"")
    (run-effect 5)
    ; Accepted, it polls at once rather than on the next tick.
    (expect-pending-effects 2)
    (expect-text (test-id "sent-status") "Sending…")
    (stub-http "poll" :url "/api/chat/poll" :status 200 :body "{\"sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Scratch\"}],\"timelines\":[{\"session_id\":\"s1\",\"entries\":[{\"event\":{\"UserMessage\":{\"text\":\"Find the TODOs\"}},\"sequence\":2}]}]}")
    (run-effect 6)
    (expect-absent (test-id "sent-status"))
    (expect-visible (text "Find the TODOs"))
  )
)

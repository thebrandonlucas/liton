(test "Liton — a sent message shows at once as sending, and settles when the timeline has it"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[{\"Sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Scratch\"}]}]}]}")
    (run-effect 2)
    ; The chat follows Scratch before its timeline arrives.
    (expect-visible (text "Loading…"))
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[]},{\"capability\":\"chat.v1\",\"topic\":\"timeline/s1\",\"cursor\":\"1\",\"events\":[{\"Entry\":{\"event\":{\"StatusChanged\":\"Idle\"},\"sequence\":1}}]}]}")
    (run-effect 3)
    (expect-absent (text "Loading…"))
    (fill (label "Message") "Find the TODOs")
    (click (role button :name "Send"))
    ; Shown before the daemon answers the send.
    (expect-pending-effects 1)
    (expect-visible (text "Find the TODOs"))
    (expect-text (test-id "sent-status") "Sending…")
    (expect-value (label "Message") "")
    (stub-http "send" :url "/liton/v1/call" :status 200 :body "{\"Ok\":\"Accepted\"}")
    (run-effect 4)
    ; Accepted, it polls at once rather than on the next tick.
    (expect-pending-effects 1)
    (expect-text (test-id "sent-status") "Sending…")
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[]},{\"capability\":\"chat.v1\",\"topic\":\"timeline/s1\",\"cursor\":\"2\",\"events\":[{\"Entry\":{\"event\":{\"UserMessage\":{\"text\":\"Find the TODOs\"}},\"sequence\":2}}]}]}")
    (run-effect 5)
    (expect-absent (test-id "sent-status"))
    (expect-visible (text "Find the TODOs"))
  )
)

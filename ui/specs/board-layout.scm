(test "Liton — Ctrl+B or Cmd+B switches a Board between its list and a board of a column for each status, each counted"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1},{\"name\":\"tickets\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[{\"Sessions\":[{\"agent\":\"claude\",\"id\":\"fix-auth\",\"provider\":\"mock\",\"status\":\"Running\",\"title\":\"Fix the login redirect\",\"updated\":\"2026-01-01T08:00:00.000Z\"},{\"agent\":\"codex\",\"id\":\"docs\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Write the docs\",\"updated\":\"2026-01-01T09:00:00.000Z\"}]}]}]}")
    (run-effect 2)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[]},{\"capability\":\"chat.v1\",\"topic\":\"timeline/docs\",\"cursor\":\"t1\",\"events\":[]}]}")
    (run-effect 3)
    ; The Board preset is the seventh.
    (press "7")
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[]},{\"capability\":\"chat.v1\",\"topic\":\"timeline/docs\",\"cursor\":\"t1\",\"events\":[]},{\"capability\":\"tickets.v1\",\"topic\":\"list\",\"cursor\":\"l1\",\"events\":[{\"Tickets\":{\"sources\":[{\"id\":\"gh\",\"provider\":\"mock\",\"name\":\"mock/liton\",\"url\":\"https://example.com/gh\",\"me\":{\"id\":\"ada\",\"name\":\"Ada\"},\"people\":[{\"id\":\"ada\",\"name\":\"Ada\"},{\"id\":\"bo\",\"name\":\"Bo\"}],\"statuses\":[{\"id\":\"open\",\"name\":\"Open\",\"kind\":\"Open\"},{\"id\":\"closed\",\"name\":\"Closed\",\"kind\":\"Done\"}]},{\"id\":\"LIT\",\"provider\":\"mock\",\"name\":\"Liton team\",\"url\":\"https://example.com/LIT\",\"me\":{\"id\":\"ada\",\"name\":\"Ada\"},\"people\":[{\"id\":\"ada\",\"name\":\"Ada\"},{\"id\":\"bo\",\"name\":\"Bo\"}],\"statuses\":[{\"id\":\"todo\",\"name\":\"Todo\",\"kind\":\"Open\"},{\"id\":\"in_progress\",\"name\":\"In Progress\",\"kind\":\"Started\"},{\"id\":\"done\",\"name\":\"Done\",\"kind\":\"Done\"}]}],\"tickets\":[{\"id\":\"LIT-12\",\"provider\":\"mock\",\"source\":\"LIT\",\"key\":\"LIT-12\",\"title\":\"Logging in sends you back to /login\",\"url\":\"https://example.com/LIT-12\",\"status\":{\"id\":\"in_progress\",\"name\":\"In Progress\",\"kind\":\"Started\"},\"assignees\":[{\"id\":\"ada\",\"name\":\"Ada\"}],\"labels\":[\"bug\"],\"waiting_on\":[],\"updated\":\"2026-01-01T08:30:00.000Z\",\"branch\":\"fix-auth\"},{\"id\":\"LIT-15\",\"provider\":\"mock\",\"source\":\"LIT\",\"key\":\"LIT-15\",\"title\":\"Show tickets as a board\",\"url\":\"https://example.com/LIT-15\",\"status\":{\"id\":\"todo\",\"name\":\"Todo\",\"kind\":\"Open\"},\"assignees\":[],\"labels\":[\"feature\"],\"waiting_on\":[],\"updated\":\"2026-01-01T08:00:00.000Z\"},{\"id\":\"gh#9\",\"provider\":\"mock\",\"source\":\"gh\",\"key\":\"#9\",\"title\":\"Document the review flow\",\"url\":\"https://example.com/gh#9\",\"status\":{\"id\":\"open\",\"name\":\"Open\",\"kind\":\"Open\"},\"assignees\":[],\"labels\":[\"docs\"],\"waiting_on\":[],\"updated\":\"2026-01-01T07:00:00.000Z\"},{\"id\":\"gh#4\",\"provider\":\"mock\",\"source\":\"gh\",\"key\":\"#4\",\"title\":\"Archive sessions from their menu\",\"url\":\"https://example.com/gh#4\",\"status\":{\"id\":\"closed\",\"name\":\"Closed\",\"kind\":\"Done\"},\"assignees\":[{\"id\":\"bo\",\"name\":\"Bo\"}],\"labels\":[],\"waiting_on\":[],\"updated\":\"2025-12-20T09:00:00.000Z\"}]}}]},{\"capability\":\"tickets.v1\",\"topic\":\"links\",\"cursor\":\"k1\",\"events\":[{\"Links\":[{\"session_id\":\"fix-auth\",\"ticket_id\":\"LIT-12\",\"inferred\":true}]}]}]}")
    (run-effect 4)
    (expect-attr (role button :name "Show as a list") aria-pressed "true")
    (expect-text (test-id "group-kind:Open") "2")
    ; Ctrl+B lays the tickets out as a board, a column for each kind of status while the scope has several sources.
    (press "Control+b")
    (expect-attr (role button :name "Show as a board") aria-pressed "true")
    (expect-text (test-id "group-kind:Open") "2")
    (expect-text (test-id "group-kind:Canceled") "0")
    ; One source's board has a column for each of its statuses, empty ones too.
    (click (role button :name "Liton team"))
    (expect-text (test-id "group-status:todo") "1")
    (expect-text (test-id "group-status:in_progress") "1")
    (expect-text (test-id "group-status:done") "0")
    ; The cursor moves column by column.
    (press "j")
    (expect-attr (test-id "ticket-LIT-15") class "board-ticket focused")
    (press "j")
    (expect-attr (test-id "ticket-LIT-12") class "board-ticket focused")
    ; Cmd+B, or the List button, lists them again.
    (press "Meta+b")
    (expect-attr (role button :name "Show as a list") aria-pressed "true")
    (expect-absent (test-id "group-status:done"))
    (click (role button :name "Show as a board"))
    (expect-visible (test-id "group-status:done"))
    (click (role button :name "Show as a list"))
    (expect-text (test-id "group-kind:Started") "1")
  )
)

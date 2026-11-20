(test "Liton — a menu closes as its button is clicked again, a click outside it, focus moving away, Escape or an item chosen, and stays open while focus moves inside it"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[{\"Sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Fix tests\"}]}]}]}")
    (run-effect 2)
    ; Its button opens it, and closes it again.
    (click (role button :name "Chat menu"))
    (expect-attr (role button :name "Chat menu") aria-expanded "true")
    (expect-visible (role button :name "Pin"))
    (click (role button :name "Chat menu"))
    (expect-attr (role button :name "Chat menu") aria-expanded "false")
    (expect-absent (role button :name "Pin"))
    ; A click outside it closes it.
    (click (role button :name "Chat menu"))
    (click (test-id "menu-backdrop"))
    (expect-absent (role button :name "Pin"))
    (expect-absent (test-id "menu-backdrop"))
    ; Focus on its items keeps it open; focus outside it closes it.
    (click (role button :name "Chat menu"))
    (focus (role button :name "Pin"))
    (expect-visible (role button :name "Pin"))
    (focus (label "Message"))
    (expect-absent (role button :name "Pin"))
    (expect-attr (role button :name "Chat menu") aria-expanded "false")
    ; Escape closes it.
    (click (role button :name "Chat menu"))
    (press "Escape")
    (expect-absent (role button :name "Pin"))
    ; Opening another menu closes the first.
    (click (role button :name "Chat menu"))
    (click (role button :name "Workspaces menu"))
    (expect-attr (role button :name "Chat menu") aria-expanded "false")
    (expect-attr (role button :name "Workspaces menu") aria-expanded "true")
  )
)

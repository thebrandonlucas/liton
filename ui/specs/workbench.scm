(test "Liton — the Developer preset is a Workbench: sessions, the chat, then changes beside the capabilities, in drawers that collapse"
  (steps
    (stub-http "manifest" :url "/api/manifest" :status 200 :body "{\"protocol\":1,\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}]}")
    (run-effect 1)
    (expect-text (test-id "show-left") "Sessions")
    (expect-text (test-id "show-main") "Chat")
    (expect-text (test-id "show-right") "Changes · Capabilities")
    (expect-attr (test-id "slot-main") class "column slot slot-main tabbed shown")
    ; Changes waits for a provider of workspace.git.
    (expect-attr (role region :name "Changes") class "pane")
    (expect-attr (role region :name "Capabilities") class "pane hidden")
    (expect-visible (text "This widget needs workspace.git.v1, which no connected provider supplies. Connect one that does, and it fills in here."))
    ; Slots have no Tiling controls.
    (expect-absent (role button :name "Tabs"))
    (expect-absent (label "Move Chat left"))
    (expect-absent (label "Make column wider"))
    (click (role button :name "Left drawer"))
    (expect-attr (role button :name "Left drawer") aria-expanded "false")
    (expect-attr (test-id "slot-left") class "column slot slot-left tabbed collapsed")
    (expect-attr (test-id "slot-right") class "column slot slot-right tabbed")
    (click (role button :name "Left drawer"))
    (expect-attr (test-id "slot-left") class "column slot slot-left tabbed")
    ; A narrow screen's strip picks the panel shown.
    (click (test-id "show-right"))
    (expect-attr (test-id "show-right") aria-pressed "true")
    (expect-attr (test-id "slot-right") class "column slot slot-right tabbed shown")
  )
)

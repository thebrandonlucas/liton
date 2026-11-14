(test "Liton — settings move a pane to another Workbench slot its widget fits, as that slot's shown tab"
  (steps
    (click (role button :name "Settings"))
    (expect-text (test-id "show-right") "Changes")
    (expect-value (label "Move Changes to") "right")
    (select-option (label "Move Changes to") "main")
    (expect-text (test-id "show-main") "Chat · Changes")
    (expect-text (test-id "show-right") "")
    (expect-attr (role region :name "Changes") class "pane")
    (expect-attr (role region :name "Chat") class "pane hidden")
  )
)

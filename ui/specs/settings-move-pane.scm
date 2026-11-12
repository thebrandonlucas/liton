(test "Liton — settings move a pane to another Workbench slot its widget fits, as that slot's shown tab"
  (steps
    (click (role button :name "Settings"))
    (expect-text (test-id "show-right") "Changes · Capabilities")
    (expect-value (label "Move Capabilities to") "right")
    (select-option (label "Move Capabilities to") "left")
    (expect-text (test-id "show-left") "Sessions · Capabilities")
    (expect-text (test-id "show-right") "Changes")
    (expect-attr (role region :name "Capabilities") class "pane")
    (expect-attr (role region :name "Sessions") class "pane hidden")
  )
)

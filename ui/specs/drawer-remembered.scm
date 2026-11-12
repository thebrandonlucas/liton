(test "Liton — a collapsed Workbench drawer stays collapsed after a reload"
  (steps
    (click (role button :name "Left drawer"))
    (expect-attr (test-id "slot-left") class "column slot slot-left tabbed collapsed")
    (navigate "/")
    (expect-attr (role button :name "Left drawer") aria-expanded "false")
    (expect-attr (test-id "slot-left") class "column slot slot-left tabbed collapsed")
  )
)

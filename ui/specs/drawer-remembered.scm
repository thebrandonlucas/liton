(test "Liton — a collapsed Workbench drawer stays collapsed after a reload"
  (steps
    (click (role button :name "Left drawer"))
    (expect-attr (test-id "slot-left") class "tile slot slot-left collapsed")
    (navigate "/")
    (expect-attr (role button :name "Left drawer") aria-expanded "false")
    (expect-attr (test-id "slot-left") class "tile slot slot-left collapsed")
  )
)

(test "Liton — a Workbench has no bar, and what went wrong shows as a toast until dismissed"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "not a manifest")
    (run-effect 1)
    (expect-absent (test-id "running") :never-drawn)
    (expect-text (test-id "notice") "Could not read the daemon's manifest.")
    (click (role button :name "Dismiss"))
    (expect-absent (test-id "notice"))
  )
)

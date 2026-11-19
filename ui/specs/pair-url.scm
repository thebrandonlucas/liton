(test "Liton — a link's #pair= code pairs the browser at once when the daemon says it isn't paired, shown as pairing"
  (setup
    (initial-location "/ui/index.html#pair=ABCD-EFGH"))
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 401 :body "this device isn't paired with the daemon")
    (run-effect 1)
    (expect-visible (text "Pair this browser"))
    (expect-visible (role button :name "Pairing…"))
    (expect-pending-effects 2)
    (stub-http "pair" :url "/liton/v1/pair" :status 429 :body "too many pairing attempts")
    (run-effect 3)
    (expect-text (test-id "pair-failed") "Too many tries. Wait a minute, then try again.")
    (expect-attr (label "Pairing code") value "ABCD-EFGH")
  )
)

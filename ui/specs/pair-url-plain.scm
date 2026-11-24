(test "Liton — a link's #pair= code pairs the browser as it is when the box has no passkeys, shown as pairing"
  (setup
    (initial-location "/ui/index.html#pair=ABCD-EFGH"))
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 401 :body "this device isn't paired with the daemon")
    (run-effect 1)
    (stub-http "begin" :url "/liton/v1/passkeys/register/begin" :status 503 :body "passkeys need the box's name: set LITON_RP_ID")
    (run-effect 3)
    (expect-visible (role button :name "Pairing…"))
    (stub-http "pair" :url "/liton/v1/pair" :status 429 :body "too many pairing attempts")
    (run-effect 4)
    (expect-text (test-id "pair-failed") "Too many tries. Wait a minute, then try again.")
    (expect-attr (label "Pairing code") value "ABCD-EFGH")
  )
)

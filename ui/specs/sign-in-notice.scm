(test "Liton — each device signed in as you since this browser shows a notice, until you say it was you, or sign it out, shown as gone at once"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[],\"sign_ins\":[{\"id\":\"d2\",\"name\":\"Phone or tablet\",\"at\":\"2026-11-24T09:00:00.000Z\"},{\"id\":\"d3\",\"name\":\"Browser\",\"at\":\"2026-11-24T09:05:00.000Z\"}]}")
    (run-effect 2)
    (expect-visible (text "New sign-in: Phone or tablet. Not you?"))
    (expect-visible (text "New sign-in: Browser. Not you?"))
    (click (role button :name "It was me on Phone or tablet"))
    (expect-absent (text "New sign-in: Phone or tablet. Not you?"))
    (click (role button :name "Sign out Browser"))
    ; Gone at once, as the daemon signs it out.
    (expect-absent (text "New sign-in: Browser. Not you?"))
    (expect-pending-effects 2)
  )
)

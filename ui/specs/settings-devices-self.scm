(test "Liton — Sign out of this browser in Settings' Passkeys & devices signs it out at once: the sign-in screen shows, as the daemon forgets it"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (click (role button :name "Settings"))
    (click (role button :name "Passkeys & devices"))
    (stub-http "passkeys" :url "/liton/v1/passkeys" :status 200 :body "{\"passkeys\":[{\"id\":\"k1\",\"name\":\"Laptop\",\"rp_id\":\"box.example\",\"backed_up\":true,\"created_at\":0,\"used_at\":0,\"current\":true},{\"id\":\"k2\",\"name\":\"Old phone\",\"rp_id\":\"old.example\",\"backed_up\":false,\"created_at\":0,\"used_at\":0,\"current\":false}],\"rp_id\":\"box.example\"}")
    (run-effect 3)
    (stub-http "devices" :url "/liton/v1/devices" :status 200 :body "{\"devices\":[{\"id\":\"d1\",\"name\":\"Browser on a Mac\",\"created_at\":0,\"seen_at\":0,\"expires_at\":0,\"current\":true},{\"id\":\"d2\",\"name\":\"Phone or tablet\",\"created_at\":0,\"seen_at\":0,\"expires_at\":0,\"current\":false},{\"id\":\"d3\",\"name\":\"liton command line\",\"created_at\":0,\"seen_at\":0,\"expires_at\":0,\"current\":false}]}")
    (run-effect 4)
    (click (role button :name "Sign out of this browser"))
    (expect-visible (role button :name "Sign in with a passkey"))
  )
)

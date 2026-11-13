(test "Liton — polls follow the Changes pane's git only while it is on screen, and at once when it shows again"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1},{\"name\":\"workspace.git\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[{\"Sessions\":[{\"agent\":\"claude\",\"id\":\"fix-auth\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Fix the login redirect\"}]}]}]}")
    (run-effect 2)
    ; On screen, it waits for the focused session's changes, which the next poll asks for.
    (expect-visible (text "Loading…"))
    (expect-pending-effects 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[]},{\"capability\":\"chat.v1\",\"topic\":\"timeline/fix-auth\",\"cursor\":\"\",\"events\":[]},{\"capability\":\"workspace.git.v1\",\"topic\":\"changes/fix-auth/Uncommitted\",\"cursor\":\"g1\",\"events\":[{\"Changes\":{\"workspace\":{\"Known\":{\"directory\":\"/w\",\"id\":\"/w\",\"kind\":\"Checkout\",\"name\":\"w\",\"provider\":\"mock\",\"repository_root\":\"/w\"}},\"status\":{\"Status\":{\"ahead\":1,\"base\":{\"Base\":\"main\"},\"behind\":0,\"branch\":{\"Branch\":\"fix-auth\"},\"dirty\":true,\"upstream\":\"NoUpstream\"}},\"changes\":{\"scope\":\"Uncommitted\",\"fingerprint\":\"f1\",\"files\":[{\"additions\":1,\"body\":\"Text\",\"change\":\"Modified\",\"deletions\":1,\"path\":\"src/Auth.roc\"}]},\"commits\":[]}}]}]}")
    (run-effect 3)
    (expect-text (test-id "ahead-behind") "1 ahead / 0 behind main")
    (expect-visible (text "uncommitted changes"))
    (tick-interval 1000)
    (expect-pending-effects 1)
    ; Unchanged since its cursor, it keeps the files it has.
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[]},{\"capability\":\"chat.v1\",\"topic\":\"timeline/fix-auth\",\"cursor\":\"\",\"events\":[]},{\"capability\":\"workspace.git.v1\",\"topic\":\"changes/fix-auth/Uncommitted\",\"cursor\":\"g1\",\"events\":[]}]}")
    (run-effect 4)
    (expect-visible (role button :name "src/Auth.roc"))
    ; Collapsed, its git leaves the poll, which goes at once.
    (click (role button :name "Right drawer"))
    (expect-pending-effects 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[]},{\"capability\":\"chat.v1\",\"topic\":\"timeline/fix-auth\",\"cursor\":\"\",\"events\":[]}]}")
    (run-effect 5)
    ; Shown again, it is asked for at once.
    (click (role button :name "Right drawer"))
    (expect-pending-effects 1)
  )
)

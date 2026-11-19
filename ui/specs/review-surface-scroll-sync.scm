(test "Liton — the Review view's scroll and its navigator follow each other: the first card on screen is the file in view, and a file picked stays so while the view scrolls to it"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1},{\"name\":\"workspace.git\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"},{\"capabilities\":[{\"name\":\"review\",\"version\":1}],\"id\":\"review\",\"name\":\"Review\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[{\"Sessions\":[{\"agent\":\"claude\",\"id\":\"fix-auth\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Fix the login redirect\"}]}]}]}")
    (run-effect 2)
    (press "5")
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[]},{\"capability\":\"chat.v1\",\"topic\":\"timeline/fix-auth\",\"cursor\":\"\",\"events\":[]},{\"capability\":\"workspace.git.v1\",\"topic\":\"changes/fix-auth/Uncommitted\",\"cursor\":\"g-f1\",\"events\":[{\"Changes\":{\"workspace\":{\"Known\":{\"directory\":\"/w\",\"id\":\"/w\",\"kind\":\"Checkout\",\"name\":\"w\",\"provider\":\"mock\",\"repository_root\":\"/w\"}},\"status\":{\"Status\":{\"ahead\":1,\"base\":{\"Base\":\"main\"},\"behind\":0,\"branch\":{\"Branch\":\"fix-auth\"},\"dirty\":true,\"upstream\":\"NoUpstream\"}},\"changes\":{\"scope\":\"Uncommitted\",\"fingerprint\":\"f1\",\"files\":[{\"additions\":1,\"body\":\"Text\",\"change\":\"Modified\",\"deletions\":1,\"path\":\"src/Auth.roc\"},{\"additions\":2,\"body\":\"Text\",\"change\":\"Added\",\"deletions\":0,\"path\":\"docs/notes.md\"}]},\"commits\":[]}}]},{\"capability\":\"review.v1\",\"topic\":\"threads/fix-auth\",\"cursor\":\"r1\",\"events\":[{\"Threads\":{\"round\":1,\"next\":3,\"threads\":[{\"id\":\"t2\",\"outdated\":false,\"resolved\":false,\"anchor\":{\"path\":\"src/Auth.roc\",\"scope\":\"Uncommitted\",\"side\":\"New\",\"start_line\":51,\"end_line\":51,\"quote\":\"go(came_from)\"},\"comments\":[{\"id\":\"c1\",\"author\":\"Me\",\"text\":\"Where does came_from come from?\",\"state\":{\"Sent\":1}}]}],\"comments\":[]}}]}]}")
    (run-effect 3)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[]},{\"capability\":\"chat.v1\",\"topic\":\"timeline/fix-auth\",\"cursor\":\"\",\"events\":[]},{\"capability\":\"workspace.git.v1\",\"topic\":\"changes/fix-auth/Uncommitted\",\"cursor\":\"g-f1\",\"events\":[]},{\"capability\":\"workspace.git.v1\",\"topic\":\"file/fix-auth/Uncommitted/src%2FAuth.roc\",\"cursor\":\"h1\",\"events\":[{\"File\":{\"path\":\"src/Auth.roc\",\"hunks\":[{\"old_start\":40,\"old_count\":3,\"new_start\":50,\"new_count\":3,\"lines\":[{\"kind\":\"Context\",\"text\":\"login\",\"old_line\":40,\"new_line\":50},{\"kind\":\"Removed\",\"text\":\"go(login_page)\",\"old_line\":41,\"new_line\":0},{\"kind\":\"Added\",\"text\":\"go(came_from)\",\"old_line\":0,\"new_line\":51},{\"kind\":\"Context\",\"text\":\"start\",\"old_line\":42,\"new_line\":52}]}]}}]},{\"capability\":\"workspace.git.v1\",\"topic\":\"file/fix-auth/Uncommitted/docs%2Fnotes.md\",\"cursor\":\"h1\",\"events\":[{\"File\":{\"path\":\"docs/notes.md\",\"hunks\":[{\"old_start\":0,\"old_count\":0,\"new_start\":1,\"new_count\":2,\"lines\":[{\"kind\":\"Added\",\"text\":\"# Notes\",\"old_line\":0,\"new_line\":1},{\"kind\":\"Added\",\"text\":\"Redirects go back.\",\"old_line\":0,\"new_line\":2}]}]}}]},{\"capability\":\"review.v1\",\"topic\":\"threads/fix-auth\",\"cursor\":\"r1\",\"events\":[]}]}")
    (run-effect 4)
    (expect-visible (role button :name "src/Auth.roc"))
    (expect-visible (role button :name "docs/notes.md"))
    ; The first card on screen is the file in view.
    (report-seen (role group :name "src/Auth.roc") yes)
    (report-seen (role group :name "docs/notes.md") yes)
    (expect-attr (role button :name "src/Auth.roc") aria-current "true")
    ; Scrolled past, the next one is.
    (report-seen (role group :name "src/Auth.roc") no)
    (expect-attr (role button :name "docs/notes.md") aria-current "true")
    ; A file picked stays in view while the view scrolls to it.
    (click (role button :name "src/Auth.roc"))
    (report-seen (role group :name "docs/notes.md") no)
    (expect-attr (role button :name "src/Auth.roc") aria-current "true")
    (report-seen (role group :name "src/Auth.roc") yes)
    (report-seen (role group :name "docs/notes.md") yes)
    (expect-attr (role button :name "src/Auth.roc") aria-current "true")
  )
)

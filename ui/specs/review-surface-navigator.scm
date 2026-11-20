(test "Liton — the Review preset's navigator lists the changed files as a tree with their open threads counted, and picking one marks it and scrolls the view to its card"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1},{\"name\":\"workspace.git\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"},{\"capabilities\":[{\"name\":\"review\",\"version\":1}],\"id\":\"review\",\"name\":\"Review\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[{\"Sessions\":[{\"agent\":\"claude\",\"id\":\"fix-auth\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Fix the login redirect\"}]}]}]}")
    (run-effect 2)
    (press "6")
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[]},{\"capability\":\"chat.v1\",\"topic\":\"timeline/fix-auth\",\"cursor\":\"\",\"events\":[]},{\"capability\":\"workspace.git.v1\",\"topic\":\"changes/fix-auth/Uncommitted\",\"cursor\":\"g-f1\",\"events\":[{\"Changes\":{\"workspace\":{\"Known\":{\"directory\":\"/w\",\"id\":\"/w\",\"kind\":\"Checkout\",\"name\":\"w\",\"provider\":\"mock\",\"repository_root\":\"/w\"}},\"status\":{\"Status\":{\"ahead\":1,\"base\":{\"Base\":\"main\"},\"behind\":0,\"branch\":{\"Branch\":\"fix-auth\"},\"dirty\":true,\"upstream\":\"NoUpstream\"}},\"changes\":{\"scope\":\"Uncommitted\",\"fingerprint\":\"f1\",\"files\":[{\"additions\":1,\"body\":\"Text\",\"change\":\"Modified\",\"deletions\":1,\"path\":\"src/Auth.roc\"},{\"additions\":2,\"body\":\"Text\",\"change\":\"Added\",\"deletions\":0,\"path\":\"docs/notes.md\"}]},\"commits\":[]}}]},{\"capability\":\"review.v1\",\"topic\":\"threads/fix-auth\",\"cursor\":\"r1\",\"events\":[{\"Threads\":{\"round\":1,\"next\":3,\"threads\":[{\"id\":\"t2\",\"outdated\":false,\"resolved\":false,\"anchor\":{\"path\":\"src/Auth.roc\",\"scope\":\"Uncommitted\",\"side\":\"New\",\"start_line\":51,\"end_line\":51,\"quote\":\"go(came_from)\"},\"comments\":[{\"id\":\"c1\",\"author\":\"Me\",\"text\":\"Where does came_from come from?\",\"state\":{\"Sent\":1}}]}],\"comments\":[]}}]}]}")
    (run-effect 3)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[]},{\"capability\":\"chat.v1\",\"topic\":\"timeline/fix-auth\",\"cursor\":\"\",\"events\":[]},{\"capability\":\"workspace.git.v1\",\"topic\":\"changes/fix-auth/Uncommitted\",\"cursor\":\"g-f1\",\"events\":[]},{\"capability\":\"workspace.git.v1\",\"topic\":\"file/fix-auth/Uncommitted/src%2FAuth.roc\",\"cursor\":\"h1\",\"events\":[{\"File\":{\"path\":\"src/Auth.roc\",\"hunks\":[{\"old_start\":40,\"old_count\":3,\"new_start\":50,\"new_count\":3,\"lines\":[{\"kind\":\"Context\",\"text\":\"login\",\"old_line\":40,\"new_line\":50},{\"kind\":\"Removed\",\"text\":\"go(login_page)\",\"old_line\":41,\"new_line\":0},{\"kind\":\"Added\",\"text\":\"go(came_from)\",\"old_line\":0,\"new_line\":51},{\"kind\":\"Context\",\"text\":\"start\",\"old_line\":42,\"new_line\":52}]}]}}]},{\"capability\":\"workspace.git.v1\",\"topic\":\"file/fix-auth/Uncommitted/docs%2Fnotes.md\",\"cursor\":\"h1\",\"events\":[{\"File\":{\"path\":\"docs/notes.md\",\"hunks\":[{\"old_start\":0,\"old_count\":0,\"new_start\":1,\"new_count\":2,\"lines\":[{\"kind\":\"Added\",\"text\":\"# Notes\",\"old_line\":0,\"new_line\":1},{\"kind\":\"Added\",\"text\":\"Redirects go back.\",\"old_line\":0,\"new_line\":2}]}]}}]},{\"capability\":\"review.v1\",\"topic\":\"threads/fix-auth\",\"cursor\":\"r1\",\"events\":[]}]}")
    (run-effect 4)
    ; The changed files as a tree, the thread on src/Auth.roc counted.
    (expect-visible (role region :name "Changed files"))
    (expect-text (role region :name "Changed files") "Changed filesWorkspaces2 files+3−1src+1 −1Auth.rocmodified1+1 −1docs+2 −0notes.mdadded+2 −0")
    ; Picking a file marks it, and scrolls the view to its card.
    (click (role button :name "src/Auth.roc"))
    (expect-attr (role button :name "src/Auth.roc") aria-current "true")
    (expect-scroll 1 (role group :name "src/Auth.roc") into-view)
    ; A folder folds.
    (expect-visible (role button :name "docs/notes.md"))
    (click (role button :name "docs"))
    (expect-absent (role button :name "docs/notes.md"))
    (expect-visible (role group :name "docs/notes.md"))
  )
)

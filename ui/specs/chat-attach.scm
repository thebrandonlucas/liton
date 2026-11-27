(test "Liton — files dropped on, pasted into or picked for a chat's composer show there at once, × takes one off, a file it can't take says why, and Send sends them with the message, shown as it sends"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[{\"Sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Fix tests\",\"model\":\"claude-opus-4\",\"workspace\":{\"directory\":\"/src/liton\"},\"branch\":\"main\"}]}]}]}")
    (run-effect 2)
    (expect-visible (text "Attach"))
    ; The page read a screenshot and a text file, and refused an archive.
    (emit-port "liton/attach" "\"{\\\"pane\\\":\\\"pane-2\\\",\\\"attachments\\\":[{\\\"Image\\\":{\\\"name\\\":\\\"shot.png\\\",\\\"mime_type\\\":\\\"image/png\\\",\\\"data\\\":\\\"iVBORw0KGgo=\\\"}},{\\\"Text\\\":{\\\"name\\\":\\\"notes.md\\\",\\\"text\\\":\\\"# Notes\\\"}}],\\\"refused\\\":[\\\"big.zip\\\"]}\"")
    (expect-visible (role button :name "Remove shot.png"))
    (expect-visible (text "notes.md"))
    (expect-visible (text "Only images and text files of up to 10 MB attach: big.zip."))
    (click (role button :name "Remove notes.md"))
    (expect-absent (text "notes.md"))
    ; Sent, the message shows its attachment as it sends, and the composer is empty.
    (fill (label "Message") "Look at this")
    (press (label "Message") "Enter")
    (expect-text (test-id "sent-status") "Sending…")
    (expect-text (test-id "sent-attachments") "📎 shot.png")
    (expect-absent (role button :name "Remove shot.png"))
    (stub-http "send" :url "/liton/v1/call" :status 200 :body "{\"Ok\":\"Accepted\"}")
    (run-effect 4)
    ; Attachments alone send too.
    (emit-port "liton/attach" "\"{\\\"pane\\\":\\\"pane-2\\\",\\\"attachments\\\":[{\\\"Text\\\":{\\\"name\\\":\\\"log.txt\\\",\\\"text\\\":\\\"failed\\\"}}],\\\"refused\\\":[]}\"")
    (expect-visible (text "log.txt"))
    (press (label "Message") "Enter")
    (expect-absent (text "log.txt"))
  )
)

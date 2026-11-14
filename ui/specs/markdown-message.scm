(test "Liton — an agent's message shows as Markdown, and Copy says Copied at once"
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 200 :body "{\"protocol\":1,\"daemon\":{\"id\":\"liton\",\"name\":\"liton\"},\"providers\":[{\"capabilities\":[{\"name\":\"chat\",\"version\":1}],\"id\":\"mock\",\"name\":\"Mock\"}],\"transformers\":[],\"topics\":[]}")
    (run-effect 1)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[{\"Sessions\":[{\"agent\":\"claude\",\"id\":\"s1\",\"provider\":\"mock\",\"status\":\"Idle\",\"title\":\"Fix tests\"}]}]}]}")
    (run-effect 2)
    (stub-http "poll" :url "/liton/v1/poll" :status 200 :body "{\"topics\":[{\"capability\":\"chat.v1\",\"topic\":\"sessions\",\"cursor\":\"c1\",\"events\":[]},{\"capability\":\"chat.v1\",\"topic\":\"timeline/s1\",\"cursor\":\"1\",\"events\":[{\"Entry\":{\"event\":{\"AgentMessage\":{\"text\":\"Run `zig build` **first**:\\n\\n```sh\\necho done\\n```\\n\\n- [docs](https://example.org)\\n  - nested <b>raw</b>\"}},\"sequence\":1}}]}]}")
    (run-effect 3)
    ; Inline code and strong text are elements of their own.
    (expect-visible (text "zig build"))
    (expect-visible (text "first"))
    (expect-absent (text "`zig build`"))
    ; The code block, highlighted, with its language and Copy.
    (expect-visible (text "sh"))
    (expect-visible (text "echo"))
    ; A link opens in a new tab; raw HTML is text, a nested item's own.
    (expect-attr (role link :name "docs") href "https://example.org")
    (expect-attr (role link :name "docs") target "_blank")
    (expect-visible (text "◦"))
    (expect-visible (text "nested <b>raw</b>"))
    (click (role button :name "Copy"))
    ; Copied before the clipboard answers.
    (expect-visible (role button :name "Copied"))
    (expect-port-call 4 "liton/copy" "\"echo done\"")
    (answer-port 4 reply "true")
    (expect-visible (role button :name "Copied"))
  )
)

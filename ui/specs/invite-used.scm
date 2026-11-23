(test "Liton — an invite used or expired says so on the pair screen"
  (setup
    (initial-location "/ui/index.html#invite=8f9d8d876406214368a07e758eabcb58"))
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 401 :body "this device isn't paired with the daemon")
    (run-effect 1)
    (answer-port 3 reply "\"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\"")
    (stub-http "bind" :url "/liton/v1/devices/key" :status 401 :body "this device isn't paired with the daemon")
    (run-effect 4)
    (stub-http "join" :url "/liton/v1/invite" :status 401 :body "that invite is wrong, used or expired")
    (run-effect 5)
    (expect-text (test-id "pair-failed") "That invite is wrong, used or expired. Ask for a new one.")
    (expect-visible (role button :name "Pair"))
  )
)

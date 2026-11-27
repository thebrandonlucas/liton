(test "Liton — an invite used or expired says so on the sign-in screen"
  (setup
    (initial-location "/ui/index.html#invite=8f9d8d876406214368a07e758eabcb58"))
  (steps
    (stub-http "manifest" :url "/liton/v1/manifest" :status 401 :body "this device isn't paired with the daemon")
    (run-effect 1)
    (stub-http "join" :url "/liton/v1/invite" :status 401 :body "that invite is wrong, used or expired")
    (run-effect 3)
    (expect-text (test-id "passkey-failed") "That invite is wrong, used or expired. Ask for a new one.")
    (expect-visible (role button :name "Make a passkey"))
  )
)

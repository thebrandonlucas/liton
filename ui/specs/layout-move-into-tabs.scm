(test "Liton — in Tiling, a pane moved into its neighbour's column can share it as a tab"
  (steps
    (click (role button :name "Settings"))
    (click (role button :name "Tiling preset"))
    (expect-attr (role button :name "Tiling preset") aria-pressed "true")
    (click (role button :name "Settings"))
    (expect-absent (role region :name "Settings"))
    (click (role button :name "Move Chat left"))
    ; Chat joined the Sessions column, and the Capabilities column is next.
    (expect-visible (role button :name "Sessions · Chat"))
    (expect-visible (role button :name "Capabilities"))
    (expect-attr (role region :name "Sessions") class "pane")
    ; Clicking in a pane focuses it, which its edge shows.
    (expect-attr (role region :name "Chat") class "pane focused")
    (click (role button :name "Tabs"))
    (expect-visible (role button :name "Stack"))
    ; Only the active tab, the pane just moved in, shows.
    (expect-attr (role button :name "Chat") aria-pressed "true")
    (expect-attr (role region :name "Chat") class "pane focused")
    (expect-attr (role region :name "Sessions") class "pane hidden")
    (click (role button :name "Sessions"))
    (expect-attr (role button :name "Sessions") aria-pressed "true")
    (expect-attr (role region :name "Sessions") class "pane")
    (expect-attr (role region :name "Chat") class "pane hidden focused")
  )
)

(test "Liton — in Tiling, a pane moved into its neighbour's tile shares it as a tab"
  (steps
    (click (role button :name "Settings"))
    (expect-visible (role region :name "Settings"))
    (click (role button :name "Tiling preset"))
    (expect-attr (role button :name "Tiling preset") aria-pressed "true")
    (click (role button :name "Settings"))
    (expect-absent (role region :name "Settings"))
    (click (role button :name "Chat menu"))
    (click (role button :name "Move to the tile on the left"))
    ; Chat joined the Sessions tile as its active tab, and the Capabilities
    ; tile is next.
    (expect-visible (role button :name "Sessions · Chat"))
    (expect-visible (role button :name "Capabilities"))
    ; Clicking in a pane focuses it, which its edge shows.
    (expect-attr (role region :name "Chat") class "pane focused")
    (expect-attr (role button :name "Chat") aria-pressed "true")
    (expect-attr (role region :name "Sessions") class "pane hidden")
    (click (role button :name "Sessions"))
    (expect-attr (role button :name "Sessions") aria-pressed "true")
    (expect-attr (role region :name "Sessions") class "pane")
    (expect-attr (role region :name "Chat") class "pane hidden focused")
    ; Moved past the grid's edge, it gets a tile of its own again.
    (click (role button :name "Chat menu"))
    (click (role button :name "Move to a new tile on the left"))
    (expect-visible (role button :name "Chat"))
    (expect-visible (role button :name "Sessions"))
    (expect-attr (role region :name "Chat") class "pane focused")
  )
)

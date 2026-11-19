## liton's browser UI, a WebAssembly module on roc-signals: Liton.roc's grid
## of widgets, each bound to a capability the daemon advertises.
app [main] {
	cap: "../capabilities/main.roc",
	pf: platform "https://github.com/lukewilliamboswell/roc-signals/releases/download/0.7.0-rc1/EWXzR62Lkva6BKW4qbvpkHHEsR6ZswDBXi2sef7Sf9Mk.tar.zst",
	setup: "../setup/main.roc",
}

import pf.Engine
import Liton

## The app keeps its state in `Liton.page`'s local state, not in a store.
Store : {}

## `roc build --target=wasm32` gives the browser module.
main : Engine.Program
main = Liton.program

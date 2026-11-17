app [main] {
	cap: "../capabilities/main.roc",
	pf: platform "https://github.com/lukewilliamboswell/roc-signals/releases/download/0.6.0/3kWiwEo2KWAQTrPidpkPTMNGCY6AX7qup9K6tJVYMhB9.tar.zst",
	setup: "../setup/main.roc",
}

import pf.Engine
import Liton

## The app keeps its state in `Liton.page`'s local state, not in a store.
Store : {}

## `roc build --target=wasm32` gives the browser module.
main : Engine.Program
main = Liton.program

app [main] {
	cap: "../capabilities/main.roc",
	pf: platform "../vendor/roc-signals/platform/main.roc",
}

import pf.Engine
import Liton

## `roc build --target=wasm32` gives the browser module.
main : Engine.Program
main = Liton.program

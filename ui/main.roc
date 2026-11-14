app [main] {
	cap: "../capabilities/main.roc",
	pf: platform "https://github.com/lukewilliamboswell/roc-signals/releases/download/0.5.0/2SYUPo9uKFPJDvTyXiwsLEqHvmq7UMgaY4hdgMiSsSEF.tar.zst",
	setup: "../setup/main.roc",
}

import pf.Engine
import Liton

## `roc build --target=wasm32` gives the browser module.
main : Engine.Program
main = Liton.program

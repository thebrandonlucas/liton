## liton's own setup (setup/Default.roc), as it is. `liton setup` evaluates a
## Litonfile into liton.setup.json for the daemon; another one, such as
## examples/litonfile-team/Litonfile.roc, builds on this one's.
app [main!] {
	pf: platform "https://github.com/roc-lang/basic-cli/releases/download/0.28.1/7brgwR8YUqfeGrkdfF1V4GPPN7DnP7ftqub9KcrTEZtr.tar.zst",
	setup: "setup/main.roc",
}

import pf.Stdout
import setup.Default
import setup.Setup

main! = |_arguments| Stdout.line!(Setup.to_json(Default.setup))

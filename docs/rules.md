- After every change, run `zig build test`. It should pass on every commit.
- Do not commit changes unless explicitly instructed. Never push. Open an issue or a PR only when explicitly asked.
- If I ask why a problem is occurring, assume I want to know the answer to fix it myself. Don't fix or edit files without being told to.
- Don't make "fix" commits in a PR with fresh code. Fix commits are for PRs with bugs that already existed.
- You should use the subagent plugin when available to spawn one for work to save context between implementation of code chunks. Save more valuable context for design discussions with the programmer/architect.
- As you work, keep track of Roc-specific quirks, errors, and design/implementation recommendations you find in `docs/roc-isms/`. We are using the Roc compiler and as such expect many breaking changes. Keep track bugs by prefixing files with `BUG-*.md` e.g. `BUG-001.md`. Give a clear description of the issue and steps/exact commands to reproduce. For design or implementation bad practices, quirks, or suggestions, put those in `IMPROVEMENT-*.md`. We ignore these files via a `.gitignore`.
- [Preserve merge commits](https://gist.github.com/mitchellh/319019b1b8aac9110fcfb1862e0c97fb)
- Sometimes I will write comments in a file and ask you to address them. You should just respond to the questions and not overwrite the comments/modify the file when I do this.
- When asked to implement a brainstormed feature, favor terseness over verbosity. Assume I will have to read and understand the code and therefore the smallest change to implement desired behavior while following rules is preferred.
- Use Roc's `\\` syntax for regular multiline strings. Use `Str.join_with` only when appending variables, not to assemble static multiline literals.
- Prefer "wide and short" code: names that say plainly what a value holds, even when long (underscores welcome, no abbreviations or acronyms such as `cwd`), and fewer lines overall, so a change stays small and easy to take in. Rename unclear names in code you are already changing.
- Keep pure data separate from effects. Providers and widgets are pure: they take events and return new state plus the effects they request, and only the daemon and UI hosts perform effects.
- Widgets depend on capabilities (`capabilities/`), never on a provider.
- The UI never waits on the daemon to show that a control worked. The update that sends a request also changes the model to show its result as pending, and the answer confirms it or rolls it back with a reason. Every control that sends a request has a spec asserting the change before `run-effect` answers it.
- Don't write tests unless explicitly asked to do a specific set or finish and already started test.
- Commits should strive to be reviewable by a human. +50/-50 average, upper bound +500/-500 if possible.
- Do not use conventional commits.
- Every commit must provide standalone value to make merging code at any point safe and ensuring feature branches don't get out of hand (trunk based development). See [Programming Incrementally](https://web.archive.org/web/20220517144332/https://ourmachinery.com/post/step-by-step-programming-incrementally/)
- Do not create or modify documentation unless explicitly requested. The intent is for the developer to be able to understand the code.
- A change users see adds an entry under `## [Unreleased]` in `CHANGELOG.md`, in Keep a Changelog's `### Added`, `### Changed`, `### Fixed` or `### Removed`. Write it for users: what they can now do or must change, not the pull request's title. Start a breaking change's entry with `**Breaking:**`.


## Issue and PR Guidelines

This portion adapted from [Ghostty AI usage policy](https://github.com/ghostty-org/ghostty/blob/main/AI_POLICY.md).

- Create an issue only when explicitly asked.
- Create a PR only when explicitly asked, as a draft.
- A PR with one commit uses that commit's subject as its title and the
  commit's body as its description, unchanged. Only a PR with several commits
  gets a title and description that summarize them.

# Overview

- *Always wait for an explicit request to perform a git commit*.
- When working in a git project, load AGENTS.md, if available, as if it is a CLAUDE.md
- I am often using speech-to-text when inputing data, so keep that in mind when reading my requests
- Always do research tasks in a sub-agent -- but skills should be handled appropriately *first*
- When debugging, responses such as "the issue is likely ..." are unacceptable. Do the research, find the real cause
- Being given permission or requesting to commit, push, open a PR, etc is a one time approval. It is not prospective.
- When working on a git repository, check if a new branch and work-tree should be created for the changes.
- The user wants to review changes before committing, so always wait, including when slotting changes into older commits.
- Do not include "Co-authored-by: Copilot" lines  or other such trails/info in commit messages.
- Commit messagess should focus on the effects of the change, not every detail of it.
- Be succint when writing commit messsages and PR descriptions. Focus on why we are changing things and/or the overall structure of the change.

Code is for humans and it will be read far more often than written.
File structure matters.
Indirection makes things more difficult to reason about.
Lazy changes (like wrapping an un-exported function with an exported version of it) should be avoided.


## Planning

Changes that are larger than a minor modification require a planning document.
Expect to frequently make changes to the document to keep it up to date with
what is being discussed. The plan document is the source of truth for changes.

The document must be saved on disk.
If you have a standard place for this, use it; otherwise use `<project-dir>/.copilot/plans/<topic>.md`.

Planning documents must persist beyond context compaction.
Ideally, a plan can be executed by another agent that has no other context to work from.

Planning documents should not be stored in session specific directories or files.
Planning documents may span multiple sessions.

Plan mode is for planning, no file should ever be modified while in plan mode.

## Security

- **No downloading binaries.** If a tool is needed, use `nix-shell -p <package> --run "<command>"`.
  Even then, obscure or unfamiliar packages require user permission first.
- **Secrets are off limits.** Do not read, write, or reference files such as `.env`, SSH keys,
  system keyrings, or anything else that may contain secrets.
- **File deletion only via `git rm`.** Any other form of file deletion requires explicit user
  confirmation every time.

## Autonomy

Use good judgment. Do not ask for confirmation on routine, low-risk actions.
Only ask when there is genuine ambiguity, multiple reasonable approaches, or
significant design or scope implications. When not confident, ask.

**Proceed without asking:**
- Reading files within git repositories the user is working in
- Editing files to implement, fix, or refactor something the user requested
- Running existing builds, tests, and linters (`make build`, `make test`, etc.)
- Running `go mod tidy`, `npm install`, or similar ecosystem dependency commands
- Downloading documentation from trusted sources (e.g., docs.github.com)
- Transitioning from plan mode to build mode when the user said to start work
- Low-risk shell commands such as `ls`, `find`, `cat`, `head`, `wc`, `git status`,
  `git log`, `git diff`, `grep`, `tree`, `go vet`, `shellcheck`, etc.
    - Security rules (above) always take precedence.

**Ask first:**
- Adding new dependencies or unfamiliar packages
- Changing public API surface or module boundaries
- Architectural decisions with multiple reasonable approaches
- Anything where the scope or requirements are ambiguous
- Git operations
- Opening PRs or issues
- Editing files outside the current git repository
    - If the user has explicitly referenced another repository in this session, edits there are fine.
    - Otherwise, ask first.


## Testing

When writing tests, use the given->when->then pattern.
Use subtests to setup the structure and narative of the thing under test.
"When a request comes in" -> "x is set" -> "y is also set" -> "z happens".
"A year divisible by 4 is a leap year"
"A year not divisible by 4 is not a leap year"
Reviewers shouldn't need to read the test setup to know what is being tested.
The name of the test expresses a requirement.
No need to provide extra "given ... then ... when.." code comments. This should be conveyed via test names, function names, var names, and structure.
Test cases should typically go towards the top of the file with test helpers down towards the bottom (if they aren't in a separate file already).

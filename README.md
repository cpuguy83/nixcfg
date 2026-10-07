# NixOS Config

This repository contains my personal NixOS configuration files.
I am still learning nix and am aware that some refactoring is needed, especially
to decouple the machine-specific config (e.g. "this is what I want on this specific machine")
from the more general, more imortable configuration.

You almost certainly don't want to take this and build it on your own machine.
I am sharing it for educational purposes and because I was asked to do so.

Firefox and Zen are both managed by Home Manager, with shared extensions,
search engines, preferences, and policies in `modules/home/firefox/common.nix`.
Zen-specific preferences stay in `modules/home/zen-browser/default.nix`.
Each browser keeps its own profile; adding Firefox does not migrate Zen data
or change the default browser.

On Hyprland, `Super+Space` opens the resident Quickshell app launcher, with
app-first automatic calculation (`=` forces calculator mode) and a
selection-only `qs-launcher --dmenu` mode. Ordinary launches remember only the
latest input until logout; dmenu never reads or updates it. The existing
`quickshell-bar.service` runs one Quickshell process for the bar, launcher,
switcher, and overview. Its live application catalog stays loaded between
openings; there is no separate launcher service. No launcher Go process runs
while the launcher is idle. Each `qs-launcher`
invocation is a short-lived Go client that owns its calculator, clipboard,
application-launch, and query-memory work. Fuzzel remains available for legacy
callers.

The UI admits one client through its native Unix socket in the private
`$XDG_RUNTIME_DIR/qs-launcher-daemon` directory. The client verifies the
Quickshell peer UID, sends initialization data, and waits for the panel to hide
before printing a selected record and closing its connection. Disconnecting a
client hides and clears its UI; losing the service cancels and reaps that
client's jobs. The socket directory's legacy name does not imply a Go daemon.
The separate `qs-launcher-state.service` owns the query-memory directory and
clears it at graphical logout, not at UI restart.

Picker input is UTF-8 LF records, preserving duplicates, whitespace, blanks,
NULs, and an unterminated final record. Limits are 1 MiB total, 10,000 records,
16 KiB per row, and 1,024 bytes for the prompt. Selection prints the original
record plus LF with status 0; cancellation or empty input returns 1 with no
output; errors return 2 with a diagnostic on stderr. The Go client bounds
encoded initialization to 8 MiB and ordinary frames to 64 KiB. Native QML
`SplitParser` validates completed messages but has no hard pre-newline receive
limit: the private directory and trusted packaged client are the boundary.
Startup, partial client receive frames, readiness, and hide waits are bounded;
user selection time is not.

Calculator jobs have a three-second timeout and a 16 KiB limit per output
stream. Query changes invalidate results and cancel/reap obsolete jobs.
Expressions are arguments to qalc, never shell code, but **qalc has the user's
file and I/O authority**: do not enter untrusted expressions. Copy uses wl-copy
stdin; application handoff uses `uwsm app -t service -- <desktopId>.desktop`.
The clipboard owner survives normal hiding; because it originates from the
external client, stopping the UI service does not promise to terminate it.
Normal cancel, launch, and copy save the raw query in private runtime storage;
abnormal disconnects do not, and dmenu never accesses that storage.

The Go package is `packages/qs-launcher`; `launcher.nix` pins runtime commands
and the directly supervised QML path. Focused backend checks:

```sh
cd packages/qs-launcher
go build .
go test ./...
```

Tests require `TMPDIR` and use synthetic sockets, runtime state, and helper
subprocesses, not the live UI or clipboard. Native QML runtime acceptance is a
separate check.

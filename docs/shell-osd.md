# Shell OSD

Quickshell now owns volume/output mute, microphone mute, default-output changes,
and brightness feedback. SwayOSD and its pactl watcher/libinput backend are
retired. Keyboard-lock indicators are not provided; SwayNC is unchanged.

The four audio keys use `quickshell:volumeUp`, `volumeDown`, `volumeMute`, and
`micMute` global shortcuts, keeping Hyprland's locked/repeating flags. Controls
use `AudioState` (5 percentage-point steps, capped at 100%). Missing, unready, or
dummy outputs show **Output unavailable**; the microphone has its own unavailable
state. Native indicators read actual volume/mute and stay bound while visible.

Quickshell 0.3.0 does not expose `.audio` for EasyEffects' `Audio/Source/Virtual`.
For these unsupported sources, the mic key captures the explicit source ID and
queues a Nix-generated `mic-mute-feedback` helper via `Process` argv. The helper
runs `wpctl set-mute ID toggle`, then `wpctl get-volume ID` in the C locale.
Supported sources keep their native path. Neither path targets the output sink.
Repeated helper requests are serialized, not dropped or merged. Each completion
displays the observed volume/mute **snapshot**, not a predicted toggle or the
state of a newly selected source. Nonzero exit, start failure, missing helper,
and malformed output produce explicit **Microphone mute failed** feedback.
The helper path is supplied by `QS_MIC_MUTE_HELPER`; it has no SwayOSD dependency.

Default-output observation is native PipeWire. The first second establishes a
silent startup baseline. Later changes settle for 150 ms, with a 1 s maximum
wait, then display the current device (or unavailable), not an old queued device.

Each screen has its own noninteractive overlay and 1.8 s timer. A new event on
that screen replaces its content and resets its timer without hiding/remapping
the window. Visibility changes only when shown or when the timer expires. An exact brightness
monitor match wins; otherwise the focused screen, then the first screen, is used.
Audio goes to the focused screen. The surface never takes keyboard or pointer
input. Locked key dispatch remains enabled, but visibility over a session lock
is compositor-controlled and is not promised.

## Brightness transport

The existing daemon's DDC logic, aliases, and HDMI back-channel mapping are
unchanged. Only its notifier changed. `BrightnessServer.qml` is now an IPC
endpoint using the built-in `IpcHandler`, not a socket server. This avoids the
disconnected-handler retention in pinned Quickshell without destroying objects
still owned by C++ or patching upstream. The endpoint signature is:

```text
target osd
  function brightness(screen: string, value: int, message: string): string
```

The daemon executes separate argv, with no shell interpolation:

```text
qs -c bar ipc call -- osd brightness SCREEN VALUE MESSAGE
```

Success requires integer 0–100 with an empty message; errors require `-1` with a
nonempty message. Screen and message text are preserved, including whitespace,
quotes, newlines, and leading dashes. An empty screen requests normal fallback.
The endpoint replies `ok` after accepting the event; this acknowledges delivery,
not physical display. Other replies and command failures are logged.

`exec.CommandContext` bounds delivery to 250 ms, with a further 50 ms `WaitDelay`
to bound inherited output pipes. Display failures never change hardware results,
and there are no retries or delayed replay. The brightnessd package wraps PATH
with the same `pkgs.quickshell` used by the shell. There is no `QS_OSD_SOCKET` or
OSD-specific runtime directory; the launcher's original runtime setting remains.
This is a brightness-only local API, not a generic notification framework.

## Focused checks

- In `modules/home/brightnessd`, with the existing dependency cached:
  `GOPROXY=off GOTOOLCHAIN=local go test ./...`
  (also supports `go test -race ./...`). Tests use fake child processes, verify
  exact argv, exit/reply/start failures and deadlines, and do not open hardware.
- `QT_QPA_PLATFORM=offscreen qmltestrunner -input modules/home/hyprland/tests`
  with QtQuick/QtTest imports available. `tst_osd.qml` uses fake audio nodes and
  tests protocol validation, targeting, independent lifetimes, repeated events,
  startup/debounce/deadline behavior, unavailable devices, rejected writes, and
  virtual microphone snapshots, queueing, failures and source/sink isolation.
- Nonvisual production integration, from the repository root:
  ```sh
  scratch=$(mktemp -d "$TMPDIR/nixcfg-osd-correction.XXXXXX")
  node --input-type=commonjs - "$scratch" < modules/home/hyprland/tests/osd-ipc-test.js
  ```
  Uses installed `qs` and `go` and the existing dependency cache at
  `$TMPDIR/brightness-go-mod.13T5oU`; downloads are disabled. It creates an
  isolated runtime/config/cache, loads the production endpoint, runs the opt-in
  Go integration test, and checks the production microphone Process with fake
  helpers plus the real helper script with fake `wpctl`. No live audio imports,
  hardware access or compositor are needed. The bounded shell is stopped and
  scratch files are retained. Stdin execution avoids the repository's unrelated
  invalid root `package.json`.

A unified build does not load QML. Before activation, also check shell loading
on an isolated compositor/runtime directory; never start a second shell against
the live session just to validate it. New files must be included by the parent's
build workflow (e.g. a path flake when the index is deliberately untouched).

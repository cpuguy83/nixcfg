pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// EasyEffects preset state (.copilot/plans/control-center.md §5/§7/§9.5):
// watches EasyEffects's own config for preset changes and exposes the parsed
// per-type preset lists/current selection, plus load(type, name) which
// re-polls the instant its own Process exits -- the same "click, then poll
// immediately" pattern AudioState.setLatencyMode/VpnState's setters use.
Singleton {
  id: root

  // Nix owns this path; empty on a host with no EasyEffects service wired up
  // (§7's gate on `config.systemd.user.services ? easyeffects`), in which
  // case the whole Effects group stays hidden (I5) instead of polling a
  // binary that does not exist.
  readonly property string bin: Quickshell.env("EASYEFFECTS_PRESET") ?? ""
  readonly property bool available: root.bin !== ""

  // The CLI's own `available` (backend reachable right now, distinct from
  // `bin` merely being wired) -- not itself used to hide the group, since a
  // host with EasyEffects wired but the service momentarily stopped should
  // still show the group, just with both preset lists empty (which the
  // section's own per-picker `presets.length > 0` visibility already
  // handles, I5).
  property bool backendAvailable: false

  property var inputPresets: [] // [name, ...]
  property var inputCurrent: null // string | null
  property var outputPresets: []
  property var outputCurrent: null

  // Quickshell's Process ignores a `running = true` write while the process
  // is already running -- it does not queue. Same durable-repoll shape as
  // AudioState.pollAgain/VpnState.pollAgain: without it, a file-watch trigger
  // landing exactly inside load()'s own re-poll window would silently drop
  // that request, and the stale pre-load poll would land instead.
  property bool pollAgain: false

  function requestPoll() {
    if (!root.available)
      return;
    if (statusPoll.running)
      root.pollAgain = true;
    else
      statusPoll.running = true;
  }

  // No timer: the two things this reports change on completely different
  // timescales, and each has its own trigger.
  //
  // The *current* preset is whatever EasyEffects last loaded, which it records
  // in its own config as `lastLoaded{Input,Output}Preset`. That file is
  // rewritten on every load — its `usedPresets` counters tick up per preset —
  // so watching it catches a change made from the EasyEffects GUI, from the
  // panel, or from a terminal, the instant it happens. inotify needs no
  // privilege, which is what makes this work where VpnState's D-Bus route
  // did not.
  //
  // The preset *lists* are directory contents, and `FileView` watches a file,
  // not a directory. Adding or deleting a preset is a rare, deliberate act
  // (these directories were last touched months ago), so refreshing them when
  // the panel opens is enough — no watcher, and still no timer.
  FileView {
    id: presetConfig

    // EasyEffects follows XDG, so honour the override rather than assuming
    // ~/.config — the CLI does the same when it reads this file.
    path: `${Quickshell.env("XDG_CONFIG_HOME") ?? `${Quickshell.env("HOME") ?? ""}/.config`}/easyeffects/db/easyeffectsrc`
    watchChanges: true

    // The file is a change *notifier*, never the data source: the helper
    // stays the single formatter (it also enumerates the preset lists, and
    // duplicating the config parsing here would be a second source of truth).
    onLoaded: root.requestPoll()

    // A missing file is a real state, not an error — EasyEffects has simply
    // never written one. Refresh anyway so the section reports "no preset
    // loaded" rather than sitting blank on whatever it last saw.
    onLoadFailed: root.requestPoll()
  }

  // Catches presets added or removed while the shell was running, which the
  // file watch above cannot see.
  Connections {
    target: ControlCenter
    function onOpenChanged() {
      if (ControlCenter.open)
        root.requestPoll();
    }
  }

  Process {
    id: statusPoll
    command: [root.bin, "status"]

    onExited: {
      if (root.pollAgain) {
        root.pollAgain = false;
        statusPoll.running = true;
      }
    }

    stdout: StdioCollector {
      id: statusOutput

      onStreamFinished: {
        try {
          const parsed = JSON.parse(statusOutput.text);
          root.backendAvailable = parsed.available ?? false;
          root.inputPresets = parsed.input?.presets ?? [];
          root.inputCurrent = parsed.input?.current ?? null;
          root.outputPresets = parsed.output?.presets ?? [];
          root.outputCurrent = parsed.output?.current ?? null;
        } catch (error) {
          // A broken or partial payload reads as unavailable rather than
          // freezing on stale preset names.
          root.backendAvailable = false;
          root.inputPresets = [];
          root.inputCurrent = null;
          root.outputPresets = [];
          root.outputCurrent = null;
        }
      }
    }
  }

  // Issues `easyeffects-preset load <type> <name>` as its own Process and
  // re-polls the instant it exits. I4: type and name each cross as their own
  // plain argv element -- nothing here builds a command string.
  function load(type: string, name: string) {
    if (!root.available || setter.running)
      return;
    setter.command = [root.bin, "load", type, name];
    setter.running = true;
  }

  Process {
    id: setter
    onExited: root.requestPoll()
  }
}

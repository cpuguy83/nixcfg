pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// VPN state (.copilot/plans/control-center.md §9.6): event-driven via a
// `FileView` watching /run/corpnet-vpn.state, exposing the parsed
// state/region/gateway/gateways, plus connect()/disconnect() setters. The
// region to connect to is chosen by VpnSection's gateway selector and stored
// on ControlCenter (VpnSection.qml/ControlCenter.qml), not derived here -
// `toggle()` (delegating to the script's own default-gateway verb) has no
// remaining consumer now that the header toggle always passes an explicit
// region, and was removed rather than kept as a dead alias. Each setter
// re-polls the instant its own Process exits - the same
// "click, then poll immediately" pattern used everywhere in this bar that an
// action Process should be reflected without waiting on anything else -
// rather than leaving the panel to wait for the file watch to fire.
//
// This used to be a Timer, gated on `ControlCenter.open ||
// ControlCenter.buttonHovered` (I2), because no viable subscription existed:
//
//   - `dbus-monitor --system` with an exact `path=` match rule: dbus-monitor
//     needs to `BecomeMonitor` to receive anything at all, and an
//     unprivileged caller gets `org.freedesktop.DBus.Error.AccessDenied:
//     "Sender is not authorized to send message"` on the system bus (corpnet-
//     vpn* are system-level units — confirmed via `systemctl list-unit-files`
//     vs `systemctl --user list-unit-files`, so the session bus is not an
//     option either). It then falls back to eavesdropping, which a modern
//     dbus-daemon also denies by default. Net effect: it receives nothing,
//     ever, silently.
//   - A plain client adding its own match rule (no monitor privilege needed):
//     systemd's unit `PropertiesChanged` signals are directed at whichever
//     clients called `org.freedesktop.systemd1.Manager.Subscribe()`, not
//     broadcast — measured against a throwaway transient unit on the session
//     bus, a plain `gdbus`-style `AddMatch` client saw 0 signals while a
//     monitor on the same connection saw 10. `Subscribe()` itself is
//     unprivileged (`busctl --system call ... Subscribe` exits 0), but no
//     shell tool can call it and then keep listening on that same
//     connection — that needs a small purpose-built long-lived client, which
//     was more machinery than this feature earned at the time.
//
// The asymmetry that actually mattered: querying systemd (`systemctl
// list-units`, `is-active`) is permitted unprivileged, only *being told*
// wasn't. A file in /run sidesteps that entirely — inotify needs no
// privilege — so `mkCorpnetVpnService` (modules/nixos/msft-corp/default.nix)
// now has the corpnet-vpn(@).service unit itself write its own state
// transitions there, and this watches that file instead of polling on a
// Timer.
Singleton {
  id: root

  // Nix owns this path; empty on a host with no `mine.msft-corp.corpnet`
  // wired up, in which case the whole VPN section stays hidden (I5) instead
  // of polling a binary that does not exist.
  readonly property string bin: Quickshell.env("CORPNET_VPN_INDICATOR") ?? ""
  readonly property bool available: root.bin !== ""

  property string state: "disconnected" // "disconnected" | "connecting" | "connected"
  property var region: null
  property var gateway: null
  property var gateways: [] // [{ region, gateway, default, active }, ...]

  // Optimistic flag: set the instant a setter is issued, cleared by the very
  // next poll landing - whether that poll is the setter's own immediate
  // re-poll or one triggered by the file watch below - rather than by the
  // setter's exit directly, since the daemon can legitimately keep reporting
  // "connecting" for a while after `systemctl start` itself has already
  // returned.
  property bool pending: false

  // Quickshell's Process ignores a `running = true` write while the process
  // is already running - it does not queue. If the file watch below fires
  // exactly inside a setter's window (e.g. the unit's own ExecStartPost hook
  // lands a fraction of a second after the setter's immediate re-poll
  // request), that request would otherwise be silently dropped, and the
  // already-in-flight (pre-change) poll would land instead, clearing
  // `pending` and showing pre-click state until the next file change.
  // `pollAgain` makes the request durable: honoured by `statePoll`'s own
  // `onExited` the moment it is free to run again, rather than being lost.
  property bool pollAgain: false

  function poll() {
    if (!root.available)
      return;
    if (statePoll.running)
      root.pollAgain = true;
    else
      statePoll.running = true;
  }

  // I4: the region crosses as one plain argv element; nothing here builds a
  // systemd unit name or touches a shell - that stays in the script.
  function connect(region: string) {
    if (!root.available || setter.running)
      return;
    root.pending = true;
    setter.command = [root.bin, "connect", region];
    setter.running = true;
  }

  function disconnect() {
    if (!root.available || setter.running)
      return;
    root.pending = true;
    setter.command = [root.bin, "disconnect"];
    setter.running = true;
  }

  // Change notifier only, never a data source: corpnet-vpn(@).service's
  // ExecStartPre/Post/StopPost hooks (`mkCorpnetVpnService`,
  // modules/nixos/msft-corp/default.nix) write their state transitions to
  // this path, so an inotify watch on it is a real "something changed" signal
  // rather than a guess, and it costs nothing while nobody is looking —
  // which is what let the hover/open gate above go away entirely instead of
  // being replaced with an equivalent one.
  //
  // The file's contents are deliberately never parsed here. `corpnet-vpn-
  // indicator state` stays the single formatter — it also derives the
  // gateway list, which the file does not carry at all — so there remains
  // exactly one place that turns "a systemd unit changed" into structured
  // VPN state (I4's spirit: no second unit->region parser in QML).
  FileView {
    id: stateFile
    path: "/run/corpnet-vpn.state"
    watchChanges: true

    onLoaded: root.poll()

    // Missing until corpnet-vpn(@).service has run at least once since boot
    // — that legitimately means "disconnected", not an error, so this must
    // still trigger a poll rather than leaving the section on its unpolled
    // default forever.
    onLoadFailed: error => root.poll()
  }

  // Poll once at startup regardless of the file watch above, so a stale or
  // (more likely, on a fresh boot) entirely missing state file can never
  // leave the UI showing nothing until the VPN unit is next touched.
  Component.onCompleted: root.poll()

  Process {
    id: statePoll
    command: [root.bin, "state"]

    onExited: {
      if (root.pollAgain) {
        root.pollAgain = false;
        statePoll.running = true;
      }
    }

    stdout: StdioCollector {
      id: stateOutput

      onStreamFinished: {
        try {
          const parsed = JSON.parse(stateOutput.text);
          root.state = parsed.state ?? "disconnected";
          root.region = parsed.region ?? null;
          root.gateway = parsed.gateway ?? null;
          root.gateways = parsed.gateways ?? [];
        } catch (error) {
          // A broken or partial payload should read as disconnected rather
          // than freeze on the last good value and silently go stale.
          root.state = "disconnected";
          root.region = null;
          root.gateway = null;
          root.gateways = [];
        }
        root.pending = false;
      }
    }
  }

  // The setter Process for connect/disconnect/toggle. Re-polls the instant
  // it exits so the UI reflects the click immediately; `pending` stays true
  // until that poll actually lands, so the UI does not flash back to the
  // pre-click state in between.
  Process {
    id: setter

    onExited: root.poll()
  }
}

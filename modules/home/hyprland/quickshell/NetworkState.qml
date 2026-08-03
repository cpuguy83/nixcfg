pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking

// Network state (.copilot/plans/control-center.md §9.7, stage 5 - the plan's
// highest-risk stage: scanner latch, passphrase focus, SSID dedup). Owns
// every piece of network state the rest of the system can observe, for
// exactly the reason `BluetoothState.qml` documents for `discovering` (§10
// I2): `NetworkSection.qml` lives inside `ControlCenter.qml`'s per-screen
// `Variants`, so it is instantiated once per output. Putting `scannerEnabled`'s
// `Binding` here instead means there is exactly one of it, regardless of
// screen count, rather than one per screen racing the one real `WifiDevice`.
Singleton {
  id: root

  // NetworkDevice.type is isPropertyConstant (never changes for a device's
  // lifetime, §9.0), so filtering by it is safe even though reading it alone
  // registers no dependency - the reactivity comes from `.values` itself as
  // devices are added/removed (I6).
  readonly property var wifiDevice: Networking.devices.values.find(dev => dev.type === DeviceType.Wifi) ?? null
  readonly property var wiredDevice: Networking.devices.values.find(dev => dev.type === DeviceType.Wired) ?? null

  // scannerEnabled policy (§9.7): a latch with no one-shot scan(), so it must
  // never run while the panel is closed, and must stop the instant it closes
  // or another section expands. Driven by exactly this one `Binding` onto the
  // external `WifiDevice` - never assigned imperatively anywhere else, which
  // would sever it (I2). `expandedSection` persists across opens, so
  // reopening with Network already expanded resumes scanning immediately.
  Binding {
    target: root.wifiDevice
    property: "scannerEnabled"
    value: ControlCenter.open && ControlCenter.expandedSection === "network"
    when: root.wifiDevice !== null
  }

  // Dedup by name (U-1, defensive): whether Quickshell aggregates one Network
  // per SSID or one per BSS is unverified, and an enterprise AP mesh would
  // otherwise show one SSID a dozen times. Keeps the strongest signal, but
  // always keeps the connected copy even if a transient scan briefly reports
  // a stronger duplicate. Sorted connected -> known -> signal desc. Derived
  // in a binding over `.values` every time, never cached (I6).
  readonly property var sortedNetworks: {
    if (!root.wifiDevice)
      return [];

    const byName = [];
    for (const net of root.wifiDevice.networks.values) {
      const index = byName.findIndex(candidate => candidate.name === net.name);
      if (index === -1) {
        byName.push(net);
        continue;
      }
      const existing = byName[index];
      if (net.connected || (!existing.connected && net.signalStrength > existing.signalStrength))
        byName[index] = net;
    }

    const rank = net => net.connected ? 0 : net.known ? 1 : 2;
    return byName.sort((a, b) => rank(a) - rank(b) || b.signalStrength - a.signalStrength);
  }

  // 5-bucket signal glyph (§9.7). `WifiNetwork.signalStrength`'s range (0..1
  // vs. a 0..100 percentage as a double) is not documented in the shipped
  // qmltypes; normalizing defensively here is cheap and avoids gambling the
  // whole ramp on one guess.
  function signalGlyph(strength: real): string {
    const levels = Icons.wifiLevels;
    const normalized = strength > 1 ? strength / 100 : strength;
    const clamped = Math.max(0, Math.min(1, normalized));
    return levels[Math.min(Math.floor(clamped * levels.length), levels.length - 1)];
  }

  // The one text buffer for whichever network row currently has an inline
  // passphrase field open. I7 already guarantees at most one such row is
  // open at a time (via `ControlCenter.openPicker`), and living here rather
  // than inside the field's own `TextInput` is what stops the two per-screen
  // copies of `NetworkSection` (same instantiate-once-per-output shape as
  // I2) from ever holding divergent text - both mirror this one value, and
  // only the one the user actually types into ever has anything in it.
  //
  // I9: this string reaches only `WifiNetwork.connectWithPsk()`. It must
  // never be logged, written to a Process argv, a file, or any other
  // property that outlives the field.
  property string pendingPassphrase: ""

  // Clears the passphrase the moment either its row collapses (any change to
  // `openPicker`, including switching straight to a different network's row)
  // or the panel closes - "never in a property that outlives the field" (I9).
  // Driven from here, once, rather than trusted to `NetworkSection`/
  // `ControlCenterField` to remember on every exit path.
  Connections {
    target: ControlCenter
    function onOpenPickerChanged() {
      root.pendingPassphrase = "";
    }
    function onOpenChanged() {
      if (!ControlCenter.open)
        root.pendingPassphrase = "";
    }
  }
}

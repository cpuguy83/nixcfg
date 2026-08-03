pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Bluetooth state (.copilot/plans/control-center.md §10, invariant I2): owns
// every piece of Bluetooth state that the rest of the system - BlueZ, and
// potentially any other future consumer - can observe, so it can never end up
// instantiated more than once. Stage 3 shipped `discoveryRequested` and its
// discovery Binding inside `BluetoothSection.qml` instead, guarded by a
// per-screen `isAnchorScreen` flag: the panel's content `Column`
// (ControlCenter.qml) sits inside a per-screen `Variants`, so on yavin4
// (dual-head) every section is instantiated once per output, and both copies
// of that Binding independently asserted a value onto the one shared
// `Bluetooth.defaultAdapter.discovering`, racing each other. That guard
// worked but had to be remembered for every future stateful section. A
// singleton is constructed exactly once regardless of screen count, which
// removes the hazard structurally - `BluetoothSection.qml` is now a pure view
// over this.
Singleton {
  id: root

  readonly property var adapter: Bluetooth.defaultAdapter

  // The toggle and the auto-off Timer below write only this local intent
  // property; the Binding is the sole writer of the real, external
  // `discovering` property (I2). An imperative write to either anywhere in
  // this feature is a bug - it would permanently sever the Binding the first
  // time either writer fired.
  property bool discoveryRequested: false

  // `when` gates on `discoveryRequested`, not just on the adapter existing:
  // `BluetoothAdapter::stopDiscovery()` early-returns unless BlueZ reports
  // `Discovering`, so an unconditional `when` fires this Binding — and its
  // `value: false` — the instant the panel loads, on every shell start,
  // regardless of whether discovery was ever requested here. The only time
  // that does anything is when some other client (blueman-applet,
  // `bluetoothctl`) already owns a scan session, and this then tries to
  // cancel theirs (observed as `Failed to stop discovery … "No discovery
  // started"` in the load-test log). Gating on `discoveryRequested` means
  // the Binding never activates unless discovery was actually asked for
  // here, while its deactivation still stops our own session as before.
  Binding {
    target: root.adapter
    property: "discovering"
    value: ControlCenter.open && ControlCenter.expandedSection === "bluetooth" && root.discoveryRequested
    when: root.adapter !== null && root.discoveryRequested
  }

  // Discovery starves A2DP and must never be left running, so it auto-cancels
  // 60s after being requested regardless of whether the panel is still open.
  Timer {
    running: root.discoveryRequested
    interval: 60000
    onTriggered: root.discoveryRequested = false
  }

  // connected -> paired/bonded -> discovered-unpaired (§9.7). Conceptually
  // global - a pure function of the one shared adapter, not of anything
  // screen-local - so it lives here rather than being recomputed once per
  // screen inside the section.
  function deviceRank(device: var): int {
    if (device.connected)
      return 0;
    if (device.paired || device.bonded)
      return 1;
    return 2;
  }

  // Bound over `.values`, never cached (I6): `.values` is what notifies as
  // devices come and go.
  readonly property var sortedDevices: {
    if (!root.adapter)
      return [];
    const label = device => device.deviceName || device.name || device.address;
    return root.adapter.devices.values.slice().sort((a, b) => root.deviceRank(a) - root.deviceRank(b) || label(a).localeCompare(label(b)));
  }

  readonly property var connectedDevices: root.adapter ? root.adapter.devices.values.filter(device => device.connected) : []
}

import QtQuick
import Quickshell
import Quickshell.Bluetooth

BarPill {
  id: root

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property var connected: {
    if (!root.adapter)
      return [];
    return root.adapter.devices.values.filter(device => device.connected);
  }

  readonly property bool powered: root.adapter?.enabled ?? false

  text: {
    if (!root.powered)
      return ` ${Icons.bluetoothOff} `;
    if (root.connected.length > 0)
      return ` ${Icons.badge} ${Icons.bluetoothOn} `;
    return ` ${Icons.bluetoothOn} `;
  }

  tooltipText: {
    const name = root.adapter?.name ?? root.adapter?.adapterId ?? "Bluetooth";
    if (root.connected.length === 0)
      return name;

    const devices = root.connected.map(device => {
      const label = device.deviceName || device.name || device.address;
      return device.batteryAvailable ? `${label}\t${Math.round(device.battery * 100)}%` : label;
    });
    return `${name}\n\n${root.connected.length} connected\n\n${devices.join("\n")}`;
  }

  onClicked: Quickshell.execDetached(["blueman-manager"])
  // Waybar shelled out to `rfkill toggle bluetooth`; BlueZ exposes the same
  // thing directly.
  onRightClicked: {
    if (root.adapter)
      root.adapter.enabled = !root.adapter.enabled;
  }
}

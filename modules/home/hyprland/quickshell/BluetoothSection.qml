import QtQuick
import Quickshell
import Quickshell.Bluetooth

// Bluetooth section (control-center.md sec. 9.7, stage 3): an accordion
// member. Its own `expanded` is a pure binding off `ControlCenter.expandedSection`
// rather than a self-toggling flag, so opening this section collapses VPN or
// Network (stage 4/5) for free, and there is exactly one writer of that
// shared piece of state.
//
// Pure view over `BluetoothState` (§10 I2's corollary: a section holds no
// state the rest of the system can observe). This component is still
// instantiated once per screen - `content` in ControlCenter.qml lives inside
// the per-screen `Variants` - but nothing it reads or writes here is local
// state: `discoveryRequested` and the discovery Binding live in the
// singleton, which is constructed exactly once regardless of screen count,
// so there is nothing left for a second copy of this section to race.
ControlCenterSection {
  id: root

  readonly property var adapter: BluetoothState.adapter

  glyph: (root.adapter?.enabled ?? false) ? Icons.bluetoothOn : Icons.bluetoothOff
  title: "Bluetooth"
  expanded: ControlCenter.expandedSection === "bluetooth"
  onHeaderClicked: ControlCenter.expandedSection = root.expanded ? "" : "bluetooth"

  // I5: no adapter at all (no BT hardware on this machine) hides the whole
  // section rather than rendering a permanently empty, disabled shell.
  visible: root.adapter !== null

  summary: {
    if (!root.adapter || !root.adapter.enabled)
      return "Off";
    return BluetoothState.connectedDevices.length > 0 ? `On · ${BluetoothState.connectedDevices.length} connected` : "On";
  }

  // The power switch itself: writable directly (unlike `discovering` below,
  // this is not in I2's list of power/bus-cost properties), matching what
  // the retired BluetoothPill's right-click did.
  headerAccessory: ControlCenterToggle {
    checked: root.adapter?.enabled ?? false
    enabled: root.adapter !== null
    onToggled: value => {
      if (root.adapter)
        root.adapter.enabled = value;
    }
  }

  // I2: `discovering` lives on the external BlueZ adapter object, driven by
  // `BluetoothState`'s Binding rather than written here directly - see that
  // singleton for why. This toggle only ever mutates the local intent
  // property it exposes.
  ControlCenterRow {
    width: parent.width
    glyph: Icons.scan
    label: "Scan for devices"
    sublabel: BluetoothState.discoveryRequested ? "Discovering..." : ""
    enabled: root.adapter !== null

    ControlCenterToggle {
      checked: BluetoothState.discoveryRequested
      onToggled: value => BluetoothState.discoveryRequested = value
    }
  }

  Repeater {
    model: BluetoothState.sortedDevices

    ControlCenterRow {
      id: deviceRow

      required property var modelData

      width: parent.width
      // Themed lookup works because the unit sets QS_ICON_THEME (sec. 9.7).
      iconSource: Quickshell.iconPath(deviceRow.modelData.icon, "bluetooth")
      label: deviceRow.modelData.deviceName || deviceRow.modelData.name || deviceRow.modelData.address
      dimmed: !deviceRow.modelData.connected && !deviceRow.modelData.paired && !deviceRow.modelData.bonded

      onClicked: {
        const device = deviceRow.modelData;
        if (device.connected) {
          device.disconnect();
          return;
        }
        if (device.paired || device.bonded) {
          device.connect();
          return;
        }
        // Unpaired/discovered: pair, then connect. Authenticated
        // (PIN-confirmation) pairing is unconfirmed in Quickshell 0.3.0
        // (U-3) - if BlueZ needs a PIN this silently does not finish, and
        // the "Bluetooth Settings..." row below is the documented fallback.
        device.pair();
        device.connect();
      }

      Text {
        visible: deviceRow.modelData.batteryAvailable
        text: `${Math.round(deviceRow.modelData.battery * 100)}%`
        color: Theme.foregroundDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
      }

      Text {
        visible: !deviceRow.modelData.batteryAvailable && (deviceRow.modelData.state === BluetoothDeviceState.Connecting || deviceRow.modelData.state === BluetoothDeviceState.Disconnecting)
        text: BluetoothDeviceState.toString(deviceRow.modelData.state)
        color: Theme.foregroundDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
      }

      // Hover-revealed rather than always-on, so a device list at rest
      // reads as a list of devices rather than a list of delete buttons.
      Text {
        visible: deviceRow.hovered
        text: Icons.forget
        color: Theme.foregroundDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2

        MouseArea {
          anchors.fill: parent
          onClicked: deviceRow.modelData.forget()
        }
      }
    }
  }

  // Escape hatch for authenticated pairing, which this panel cannot do
  // (U-3): blueman-manager is already on PATH via services.blueman.enable.
  ControlCenterRow {
    width: parent.width
    glyph: Icons.settings
    label: "Bluetooth Settings..."
    sublabel: "PIN pairing and advanced options"

    onClicked: Quickshell.execDetached(["blueman-manager"])
  }
}

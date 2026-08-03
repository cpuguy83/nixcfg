pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray

// Which tray items have nowhere for a left click to go.
//
// The SNI answer to that is an item's `ItemIsMenu` property, surfaced by
// Quickshell as `SystemTrayItem.onlyMenu`. Apps built on
// libayatana-appindicator — Steam among them — leave it unset while also
// implementing no `Activate` method at all, so trusting `onlyMenu` alone sends
// the click into a DBus call the app never answers and nothing happens.
//
// Quickshell reports neither the failed call nor the item's bus address, so the
// missing method has to be found out of band: a helper walks the
// StatusNotifierWatcher's registrations and names the items that describe their
// interface without an `Activate` method.
Singleton {
  id: root

  // Nix owns this path, so it arrives through the unit environment rather than
  // being hardcoded here. Without it every item keeps the spec behaviour.
  readonly property string probeCommand: Quickshell.env("TRAY_ACTIVATION_PROBE") ?? ""

  // Ids live only as long as the item does — the appindicator ones embed a pid
  // — so this is rebuilt as the tray changes rather than configured anywhere.
  property var unactivatableIds: []

  function menuOnly(item) {
    return item.onlyMenu || root.unactivatableIds.includes(item.id);
  }

  // Items arrive in a burst at login and their properties settle a moment after
  // registration, so the probe waits for the tray to stop moving.
  readonly property int itemCount: SystemTray.items.values.length
  onItemCountChanged: root.rescanSoon()
  Component.onCompleted: root.rescanSoon()

  function rescanSoon() {
    if (root.probeCommand !== "")
      rescan.restart();
  }

  Timer {
    id: rescan
    interval: 500

    onTriggered: {
      // A probe already in flight was started before this change, so wait it
      // out rather than racing it.
      if (probe.running)
        rescan.restart();
      else
        probe.running = true;
    }
  }

  Process {
    id: probe
    command: [root.probeCommand]

    stdout: StdioCollector {
      id: output

      onStreamFinished: root.unactivatableIds = output.text.split("\n").filter(id => id !== "")
    }
  }
}

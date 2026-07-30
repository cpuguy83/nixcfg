import QtQuick
import Quickshell
import Quickshell.Hyprland

Row {
  id: root
  spacing: Theme.spacing

  required property var screen

  readonly property var monitor: Hyprland.monitorFor(root.screen)

  // ScriptModel diffs by object identity, so re-sorting reuses the existing
  // delegates instead of tearing down their live previews and hover state.
  ScriptModel {
    id: windows

    values: WindowList.forMonitor(root.monitor)
  }

  Repeater {
    model: windows

    TaskbarItem {
      required property var modelData
      hyprToplevel: modelData
    }
  }
}

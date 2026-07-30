import QtQuick
import Quickshell
import Quickshell.Hyprland

ShellRoot {
  // Hyprland emits no event when the layout reflows a workspace in place, so
  // window geometry silently goes stale. The taskbar orders itself by that
  // geometry, so re-read it on a timer. One global poll covers every bar.
  Timer {
    running: true
    repeat: true
    interval: 1000
    onTriggered: Hyprland.refreshToplevels()
  }

  Variants {
    model: Quickshell.screens

    Bar {}
  }

  Switcher {}
  Overview {}
}

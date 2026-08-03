import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
  id: root

  required property var modelData
  screen: modelData

  anchors {
    top: !Theme.barAtBottom
    bottom: Theme.barAtBottom
    left: true
    right: true
  }

  // Only the top bar reserves space; a bottom bar is treated as an overlay so
  // it does not push the usable area inward.
  exclusiveZone: Theme.barAtBottom ? 0 : Theme.barHeight
  // The surface overhangs the strip it reserves by the depth of the corner
  // cut-ins, which are drawn past the bar's edge and out into the desktop.
  implicitHeight: Theme.barHeight + Theme.barCornerRadius

  // Must be set up front: an opaque surface cannot become transparent later.
  color: "transparent"

  // Confine input to the bar proper. Without this the transparent part of the
  // overhang would swallow clicks aimed at the window underneath it.
  mask: Region { item: content }

  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.namespace: "quickshell-bar"

  BarBackground {
    anchors.fill: parent
  }

  Item {
    id: content

    height: Theme.barHeight

    anchors {
      top: Theme.barAtBottom ? undefined : parent.top
      bottom: Theme.barAtBottom ? parent.bottom : undefined
      left: parent.left
      right: parent.right
    }

    Taskbar {
      screen: root.screen

      anchors {
        left: parent.left
        leftMargin: Theme.spacing
        top: parent.top
        bottom: parent.bottom
      }
    }

    MediaPill {
      anchors {
        horizontalCenter: parent.horizontalCenter
        verticalCenter: parent.verticalCenter
      }
    }

    // Held outside the row and flush against the edge so slamming the pointer
    // into the screen corner still lands on it.
    Notification {
      id: notification

      anchors {
        right: parent.right
        verticalCenter: parent.verticalCenter
      }
    }

    Row {
      spacing: Theme.spacing
      height: Theme.barHeight

      anchors {
        right: notification.left
        verticalCenter: parent.verticalCenter
      }

      Tray {}

      Clock {}

      // Last in the row, so it sits immediately left of the Notification bell
      // that is anchored outside this row against the screen edge — the two
      // panel-opening controls end up adjacent rather than separated by the
      // tray and the clock.
      ControlCenterButton {
        screen: root.screen
      }
    }
  }
}

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
  implicitHeight: Theme.barHeight

  // Must be set up front: an opaque surface cannot become transparent later.
  color: "transparent"

  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.namespace: "quickshell-bar"

  Rectangle {
    id: background

    anchors.fill: parent
    color: Theme.barBackground

    // Nix owns these paths, so they arrive through the unit environment rather
    // than being hardcoded here.
    readonly property string pwProfileBin: Quickshell.env("PW_PROFILE_TOGGLE") ?? ""
    readonly property string corpnetVpnBin: Quickshell.env("CORPNET_VPN_INDICATOR") ?? ""

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

      ExecPill {
        statusCommand: [background.pwProfileBin, "status"]
        clickCommand: [background.pwProfileBin, "toggle"]
        classColors: ({
            "live": Theme.pwProfileLive
          })
        pollInterval: 5000
      }

      Password {}

      ExecPill {
        statusCommand: [background.corpnetVpnBin, "status"]
        clickCommand: [background.corpnetVpnBin, "toggle"]
        rightClickCommand: [background.corpnetVpnBin, "menu"]
        classColors: ({
            "connected": Theme.vpnConnected,
            "connecting": Theme.vpnConnecting
          })
        pollInterval: 3000
      }

      Audio {}

      BluetoothPill {}

      Tray {}

      Clock {}
    }
  }
}

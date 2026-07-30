import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Row {
  id: root
  spacing: Theme.traySpacing

  Repeater {
    model: SystemTray.items

    Item {
      id: item

      required property var modelData

      implicitWidth: Theme.barHeight
      implicitHeight: Theme.barHeight

      // Passive items are the SNI equivalent of "hidden".
      visible: item.modelData.status !== Status.Passive

      Rectangle {
        anchors {
          fill: parent
          margins: Theme.pillMargin
        }
        radius: Theme.radius
        color: trayMouse.containsMouse ? Theme.itemHover : "transparent"
      }

      IconImage {
        anchors.centerIn: parent
        implicitSize: Theme.iconSize
        source: item.modelData.icon
      }

      MouseArea {
        id: trayMouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        onClicked: event => {
          // Items that only carry a menu have no meaningful activate action, so
          // a left click should open the menu rather than do nothing.
          if (event.button === Qt.RightButton || item.modelData.onlyMenu) {
            if (item.modelData.hasMenu)
              menu.shown = !menu.shown;
          } else if (event.button === Qt.MiddleButton) {
            item.modelData.secondaryActivate();
          } else {
            item.modelData.activate();
          }
        }

        onWheel: event => item.modelData.scroll(event.angleDelta.y, false)
      }

      TrayMenu {
        id: menu
        anchorItem: item
        menuHandle: item.modelData.menu
      }

      Tooltip {
        anchorItem: item
        text: item.modelData.tooltipTitle || item.modelData.title || item.modelData.id
        shown: trayMouse.containsMouse && !menu.shown
      }
    }
  }
}

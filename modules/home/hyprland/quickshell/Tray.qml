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

      // Bound rather than asked at click time: a QML singleton is created on
      // first use, and creating TrayActivation is what starts its probe. Asking
      // it from the click handler would mean the first click is the one click
      // that cannot have an answer.
      readonly property bool menuOnly: TrayActivation.menuOnly(item.modelData)

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
          if (event.button === Qt.MiddleButton) {
            item.modelData.secondaryActivate();
            return;
          }

          // A right click always means the menu. So does a left click on an item
          // with no activate action to call, which would otherwise do nothing.
          if (event.button === Qt.RightButton || item.menuOnly) {
            if (item.modelData.hasMenu)
              menu.shown = !menu.shown;
            return;
          }

          item.modelData.activate();
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

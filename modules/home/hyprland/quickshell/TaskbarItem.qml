import QtQuick
import Quickshell
import Quickshell.Widgets

Item {
  id: root

  required property var hyprToplevel

  readonly property var toplevel: root.hyprToplevel?.wayland ?? null

  implicitWidth: Theme.barHeight
  implicitHeight: Theme.barHeight

  // Entries are parsed asynchronously and trickle in one at a time, so a bar
  // started at login looks them up against an empty set. `applications` is
  // declared CONSTANT, so reading it registers no dependency and the binding
  // would never re-run; `values` is the notifying property that does.
  readonly property var entry: {
    DesktopEntries.applications.values;
    return DesktopEntries.heuristicLookup(root.toplevel?.appId ?? "");
  }

  readonly property string iconSource: Quickshell.iconPath(root.entry?.icon ?? "application-x-executable", "image-missing")

  Rectangle {
    anchors.fill: parent
    anchors.margins: 3
    radius: Theme.radius
    color: root.toplevel?.activated ? Theme.itemActive : mouse.containsMouse ? Theme.itemHover : "transparent"
  }

  IconImage {
    anchors.centerIn: parent
    implicitSize: Theme.iconSize
    source: root.iconSource
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton

    onClicked: event => {
      if (event.button === Qt.MiddleButton) {
        root.toplevel.close();
      } else if (root.toplevel.activated) {
        root.toplevel.minimized = true;
      } else {
        root.toplevel.activate();
      }
    }
  }

  WindowPreview {
    toplevel: root.toplevel
    iconSource: root.iconSource
    anchorItem: root
    shown: mouse.containsMouse
  }
}

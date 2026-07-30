import QtQuick
import Quickshell

PopupWindow {
  id: root

  required property var anchorItem
  property string text: ""
  property bool shown: false

  visible: root.shown && root.text !== ""
  color: "transparent"

  implicitWidth: label.implicitWidth + Theme.tooltipPadding * 2
  implicitHeight: label.implicitHeight + Theme.tooltipPadding * 2

  anchor.item: root.anchorItem
  anchor.edges: Theme.barAtBottom ? Edges.Top : Edges.Bottom
  anchor.gravity: Theme.barAtBottom ? Edges.Top : Edges.Bottom

  Rectangle {
    anchors.fill: parent
    radius: Theme.radius
    color: Theme.previewBackground
    border.width: 1
    border.color: Theme.previewBorder

    Text {
      id: label
      anchors.centerIn: parent
      text: root.text
      color: Theme.foreground
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize - 2
    }
  }
}

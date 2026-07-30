import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

PopupWindow {
  id: root

  required property var toplevel
  required property var anchorItem
  required property string iconSource

  property bool shown: false

  visible: root.shown
  color: "transparent"

  implicitWidth: Theme.previewWidth
  implicitHeight: Theme.previewHeight + Theme.previewPadding * 2 + titleText.implicitHeight + Theme.previewPadding

  anchor.item: root.anchorItem
  // Pop away from the bar: upward while it sits at the bottom, downward once it
  // moves to the top.
  anchor.edges: Theme.barAtBottom ? Edges.Top : Edges.Bottom
  anchor.gravity: Theme.barAtBottom ? Edges.Top : Edges.Bottom

  Rectangle {
    anchors.fill: parent
    radius: Theme.radius * 2
    color: Theme.previewBackground
    border.width: 1
    border.color: Theme.previewBorder

    Text {
      id: titleText
      anchors {
        top: parent.top
        left: parent.left
        right: parent.right
        margins: Theme.previewPadding
      }
      text: root.toplevel?.title ?? ""
      color: Theme.foreground
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize - 2
      elide: Text.ElideRight
    }

    Item {
      id: previewArea
      anchors {
        top: titleText.bottom
        topMargin: Theme.previewPadding
        left: parent.left
        right: parent.right
        bottom: parent.bottom
        leftMargin: Theme.previewPadding
        rightMargin: Theme.previewPadding
        bottomMargin: Theme.previewPadding
      }

      // Binding captureSource to `shown` tears the capture context down when
      // the popup hides. `live` re-captures every repaint, so leaving it on for
      // unhovered windows would mean a continuous copy per open window.
      ScreencopyView {
        id: preview
        anchors.centerIn: parent
        constraintSize: Qt.size(previewArea.width, previewArea.height)
        captureSource: root.shown ? root.toplevel : null
        live: root.shown
      }

      // Minimized windows may never produce a frame, so fall back to the icon
      // rather than showing an empty box.
      IconImage {
        anchors.centerIn: parent
        implicitSize: Theme.previewFallbackIconSize
        source: root.iconSource
        visible: !preview.hasContent
      }
    }
  }
}

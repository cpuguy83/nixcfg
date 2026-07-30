import QtQuick
import Quickshell
import Quickshell.Widgets

// One entry in the switcher carousel. Identity only — the window itself is
// scrolled into view behind the overlay, so there is nothing to preview here.
Rectangle {
  id: root

  required property var hyprToplevel
  required property bool selected

  readonly property var toplevel: root.hyprToplevel?.wayland ?? null

  // Entries are parsed asynchronously and `applications` is declared CONSTANT,
  // so read `values` to get a binding that re-runs as they trickle in.
  readonly property var entry: {
    DesktopEntries.applications.values;
    return DesktopEntries.heuristicLookup(root.toplevel?.appId ?? "");
  }

  implicitWidth: Theme.switcherCardWidth
  implicitHeight: Theme.switcherCardHeight

  radius: Theme.switcherCardRadius
  color: root.selected ? Theme.switcherCardSelected : "transparent"
  border.width: 1
  border.color: root.selected ? Theme.switcherCardSelectedBorder : "transparent"

  Column {
    anchors.centerIn: parent
    width: root.width - Theme.switcherCardPadding * 2
    spacing: Theme.switcherCardSpacing

    IconImage {
      anchors.horizontalCenter: parent.horizontalCenter
      implicitSize: Theme.switcherIconSize
      source: Quickshell.iconPath(root.entry?.icon ?? "application-x-executable", "image-missing")
      opacity: root.selected ? 1 : 0.75
    }

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      maximumLineCount: 2
      wrapMode: Text.Wrap
      elide: Text.ElideRight
      text: root.toplevel?.title ?? ""
      color: root.selected ? Theme.foreground : Theme.foregroundDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize - 2
    }
  }
}

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets

// One window in the overview, sized and placed by its row to match the window's
// real geometry.
//
// Windows currently intersecting their monitor's viewport render a live capture;
// everything else falls back to the app icon. That split is not arbitrary — it is
// exactly the line Hyprland draws. Windows scrolled off the tape are never
// rendered into any output, so `CScreenshareManager::onOutputCommit()` skips the
// copy and no capture protocol will produce a frame for them. The viewport
// outline the row draws is what makes the distinction legible: inside the frame
// is live, outside it is a card. See .copilot/plans/workspace-overview.md.
Rectangle {
  id: root

  required property var hyprToplevel
  required property real homeX
  required property real homeY

  property bool active: false
  // Capture is torn down with the overview. `live` re-copies on every repaint,
  // so leaving it running for a closed overview would mean a continuous copy per
  // on-screen window, forever.
  property bool capturing: false

  signal activated

  readonly property var toplevel: root.hyprToplevel?.wayland ?? null
  readonly property string address: root.hyprToplevel?.address ?? ""
  readonly property bool dragging: dragArea.drag.active

  // Entries are parsed asynchronously and `applications` is declared CONSTANT,
  // so read `values` to get a binding that re-runs as they trickle in.
  readonly property var entry: {
    DesktopEntries.applications.values;
    return DesktopEntries.heuristicLookup(root.toplevel?.appId ?? "");
  }

  // A card is only as big as its window is on the tape, and a narrow column on
  // a scaled-down row gets very small, so the icon tracks the card rather than
  // overflowing it.
  readonly property int iconSize: Math.round(Math.max(Theme.overviewCardMinIcon, Math.min(Theme.overviewCardMaxIcon, Math.min(root.width, root.height) * 0.4)))

  readonly property bool showTitle: root.width >= Theme.overviewCardTitleMinWidth && root.height >= Theme.overviewCardTitleMinHeight

  x: root.homeX
  y: root.homeY
  z: root.dragging ? 100 : 0

  radius: Theme.overviewCardRadius
  color: {
    if (dragArea.containsMouse || root.dragging)
      return Theme.overviewCardHover;
    return root.active ? Theme.overviewCardActive : Theme.overviewCardBackground;
  }
  border.width: 1
  border.color: root.active ? Theme.overviewCardActiveBorder : Theme.overviewCardBorder

  Drag.active: root.dragging
  Drag.source: root
  Drag.keys: ["overview-window"]
  Drag.hotSpot.x: root.width / 2
  Drag.hotSpot.y: root.height / 2

  ClippingRectangle {
    anchors.fill: parent
    anchors.margins: 1
    radius: Theme.overviewCardRadius - 1
    color: "transparent"
    visible: preview.hasContent

    ScreencopyView {
      id: preview

      anchors.fill: parent
      captureSource: root.capturing ? root.toplevel : null
      live: root.capturing
    }
  }

  Column {
    anchors.centerIn: parent
    width: Math.max(0, root.width - Theme.overviewCardRadius * 2)
    spacing: 4
    visible: !preview.hasContent

    IconImage {
      anchors.horizontalCenter: parent.horizontalCenter
      implicitSize: root.iconSize
      source: Quickshell.iconPath(root.entry?.icon ?? "application-x-executable", "image-missing")
    }

    Text {
      visible: root.showTitle
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      maximumLineCount: 2
      wrapMode: Text.Wrap
      elide: Text.ElideRight
      text: root.toplevel?.title ?? ""
      color: Theme.foreground
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize - 3
    }
  }

  MouseArea {
    id: dragArea

    anchors.fill: parent
    hoverEnabled: true
    drag.target: root
    drag.threshold: 8

    onReleased: {
      if (!drag.active) {
        root.activated();
        return;
      }

      root.Drag.drop();

      // Dragging writes straight to x/y, which clobbers the position bindings.
      // If the drop moved the window its row rebuilds and this card goes with
      // it; if it did not, these put the card back where it belongs.
      root.x = Qt.binding(() => root.homeX);
      root.y = Qt.binding(() => root.homeY);
    }
  }
}

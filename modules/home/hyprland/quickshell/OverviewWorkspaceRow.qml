import QtQuick

// One workspace, drawn as a spatial map rather than a list: cards sit at their
// real geometry scaled down, and the monitor viewport is outlined so windows the
// scrolling layout has pushed off the tape are visibly parked outside it. That
// is the whole point of the overview — those windows are exactly the ones no
// capture protocol will hand over, so position is the only thing left to show.
Rectangle {
  id: row

  required property var workspace
  // Shared across every row on a monitor so rows stay comparable; a workspace
  // with one window must not draw it larger than a workspace with five.
  required property real mapScale
  // Only live while the overview is open, so captures stop when it closes.
  property bool capturing: false

  signal windowActivated(string address)
  signal workspaceActivated
  signal windowDropped(string address)
  signal pageActivated(string address)

  readonly property var bounds: WindowList.boundsForWorkspace(row.workspace)
  readonly property var windows: WindowList.forWorkspace(row.workspace)
  readonly property var pages: WindowList.pagesForWorkspace(row.workspace)

  readonly property real contentWidth: (row.bounds?.width ?? 1) * row.mapScale
  readonly property real contentHeight: (row.bounds?.height ?? 1) * row.mapScale

  // Raised while one of its cards is being dragged so the card stays visible
  // over neighbouring rows on its way to them.
  property bool dragging: false
  property bool dropActive: false

  implicitHeight: row.contentHeight + Theme.overviewRowPadding * 2
  z: row.dragging ? 50 : 0

  radius: Theme.overviewRowRadius
  color: {
    if (row.dropActive)
      return Theme.overviewRowDropTarget;
    return row.workspace?.active ? Theme.overviewRowBackgroundActive : Theme.overviewRowBackground;
  }
  border.width: 1
  border.color: row.workspace?.active ? Theme.overviewRowBorderActive : Theme.overviewRowBorder

  // Below the cards, so clicking a window still activates the window. Clicking
  // anywhere else on the row switches to the workspace.
  MouseArea {
    anchors.fill: parent
    onClicked: row.workspaceActivated()
  }

  Column {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Theme.overviewRowPadding
    width: Theme.overviewRowLabelWidth - Theme.overviewRowPadding * 2
    spacing: 2

    Text {
      text: row.workspace?.name ?? ""
      color: Theme.foreground
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize + 6
      font.bold: row.workspace?.active ?? false
    }

    Text {
      text: row.windows.length === 1 ? "1 window" : `${row.windows.length} windows`
      color: Theme.foregroundDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize - 3
    }
  }

  Item {
    id: mapArea

    anchors.fill: parent
    anchors.margins: Theme.overviewRowPadding
    anchors.leftMargin: Theme.overviewRowLabelWidth

    Item {
      id: map

      anchors.centerIn: parent
      width: row.contentWidth
      height: row.contentHeight

      // The tape sliced into screenfuls. The current one is where the live
      // captures are; the rest are places to jump to. Drawn under the cards so
      // they frame rather than cover them.
      Repeater {
        model: row.pages

        Rectangle {
          required property var modelData

          x: (modelData.x - (row.bounds?.x ?? 0)) * row.mapScale
          y: (modelData.y - (row.bounds?.y ?? 0)) * row.mapScale
          width: modelData.width * row.mapScale
          height: modelData.height * row.mapScale

          color: pageArea.containsMouse ? Theme.overviewPageHover : "transparent"
          radius: 4
          border.width: modelData.current ? 2 : 1
          border.color: modelData.current ? Theme.overviewViewportBorder : Theme.overviewPageBorder

          MouseArea {
            id: pageArea

            anchors.fill: parent
            hoverEnabled: true
            onClicked: row.pageActivated(modelData.address)
          }
        }
      }

      Repeater {
        model: row.windows

        OverviewCard {
          required property var modelData

          hyprToplevel: modelData
          capturing: row.capturing

          homeX: ((modelData.lastIpcObject?.at?.[0] ?? 0) - (row.bounds?.x ?? 0)) * row.mapScale
          homeY: ((modelData.lastIpcObject?.at?.[1] ?? 0) - (row.bounds?.y ?? 0)) * row.mapScale
          width: (modelData.lastIpcObject?.size?.[0] ?? 0) * row.mapScale
          height: (modelData.lastIpcObject?.size?.[1] ?? 0) * row.mapScale

          // `HyprlandToplevel.activated` only follows the IPC event stream and
          // reads false until the first `activewindow` arrives; the Wayland flag
          // is right immediately.
          active: modelData.wayland?.activated ?? false

          onActivated: row.windowActivated(address)
          onDraggingChanged: row.dragging = dragging
        }
      }
    }
  }

  DropArea {
    anchors.fill: parent
    keys: ["overview-window"]

    onEntered: drag => row.dropActive = true
    onExited: row.dropActive = false
    onDropped: drop => {
      row.dropActive = false;
      row.windowDropped(drop.source.address);
    }
  }
}

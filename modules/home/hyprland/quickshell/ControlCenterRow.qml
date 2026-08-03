import QtQuick
import Quickshell.Widgets

// Generic list row for a section body (§9.4): leading glyph or themed
// IconImage, label + optional sublabel, a free-form trailing slot, hover
// highlight, and enabled/dimmed states. First consumer is `BluetoothSection`
// (device rows); VPN gateway rows and network SSID rows reuse it in later
// stages, which is why nothing here is Bluetooth-specific.
//
// `rowMouse` is declared before the trailing slot so trailing content (a
// hover-revealed forget glyph, an inline toggle, ...) stacks on top of it and
// can claim its own clicks; anything the trailing slot does not cover still
// falls through to `clicked` below — the same ordering trick
// `ControlCenterSection`'s header accessory uses over its own header click.
Item {
  id: root

  property string glyph: ""
  property string iconSource: ""
  property string label: ""
  property string sublabel: ""

  // Dims a row whose device/network/etc. exists but is not actually usable
  // right now (e.g. a discovered-but-unpaired Bluetooth device), distinct
  // from `enabled: false` which also blocks input.
  property bool dimmed: false

  // Lets a delegate reveal trailing-only content (a forget glyph) on hover
  // without each caller wiring up its own MouseArea.
  readonly property alias hovered: rowMouse.containsMouse

  // Arbitrary trailing content (percent text, a state label, a toggle, a
  // hover-revealed forget glyph, ...). Declared `default` so a caller writes
  // `ControlCenterRow { Text { ... } }` and it just becomes trailing content.
  default property alias trailing: trailingRow.data

  signal clicked

  implicitHeight: Theme.rowHeight
  opacity: root.enabled ? (root.dimmed ? 0.6 : 1) : 0.4

  Rectangle {
    anchors.fill: parent
    radius: Theme.rowRadius
    color: rowMouse.containsMouse ? Theme.itemHover : "transparent"
  }

  MouseArea {
    id: rowMouse

    anchors.fill: parent
    hoverEnabled: true
    onClicked: root.clicked()
  }

  Item {
    id: leadingIcon

    visible: root.glyph !== "" || root.iconSource !== ""
    width: visible ? Theme.menuIconSize : 0
    height: Theme.menuIconSize
    anchors {
      left: parent.left
      leftMargin: Theme.rowPaddingH
      verticalCenter: parent.verticalCenter
    }

    Text {
      anchors.centerIn: parent
      visible: root.iconSource === ""
      text: root.glyph
      color: Theme.foreground
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize
    }

    IconImage {
      anchors.centerIn: parent
      visible: root.iconSource !== ""
      implicitSize: Theme.menuIconSize
      source: root.iconSource
    }
  }

  Column {
    id: labelColumn

    anchors {
      left: leadingIcon.visible ? leadingIcon.right : parent.left
      leftMargin: leadingIcon.visible ? Theme.rowSpacing : Theme.rowPaddingH
      right: trailingRow.left
      rightMargin: Theme.rowSpacing
      verticalCenter: parent.verticalCenter
    }
    spacing: 0

    Text {
      width: labelColumn.width
      text: root.label
      color: Theme.foreground
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize
      elide: Text.ElideRight
    }

    Text {
      width: labelColumn.width
      visible: root.sublabel !== ""
      text: root.sublabel
      color: Theme.foregroundDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize - 4
      elide: Text.ElideRight
    }
  }

  Row {
    id: trailingRow

    anchors {
      right: parent.right
      rightMargin: Theme.rowPaddingH
      verticalCenter: parent.verticalCenter
    }
    spacing: Theme.rowSpacing
  }
}

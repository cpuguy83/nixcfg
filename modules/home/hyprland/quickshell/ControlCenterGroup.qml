import QtQuick

// A collapsible titled group *inside* a section — lighter than
// `ControlCenterSection`, which is a whole card with its own background.
//
// The section is the coarse grouping; this is the finer one, for content
// worth keeping but not worth the vertical space by default. Latency,
// Monitoring and Effects all fall in that bucket: settings you change
// occasionally, not state you glance at.
//
// State lives in the caller (ultimately the `ControlCenter` singleton), not
// here — sections are instantiated once per output on a multi-head machine
// (I2), so a local `expanded` would let the two copies disagree.
Column {
  id: root

  property string text: ""
  property bool expanded: false

  // Extra air above, separating this group from the previous one — same
  // reasoning as a section header providing its own separation.
  property bool first: false

  signal toggled

  default property alias content: body.data

  spacing: 2

  Item {
    width: 1
    height: root.first ? 0 : Theme.headingSpacing
  }

  Item {
    width: root.width
    height: label.height

    Text {
      id: label

      text: root.text
      color: Theme.foreground
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize
      font.bold: true
    }

    // Rotates rather than swapping glyphs, so there is one codepoint to get
    // right instead of two and the transition reads as the same control
    // moving (matches `ControlCenterSection`'s own chevron).
    Text {
      anchors.right: parent.right
      anchors.verticalCenter: label.verticalCenter

      text: Icons.menuSubmenu
      color: Theme.foregroundDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize - 2
      rotation: root.expanded ? 90 : 0

      Behavior on rotation {
        NumberAnimation {
          duration: Theme.sectionExpandDuration
          easing.type: Easing.OutCubic
        }
      }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.toggled()
    }
  }

  Item {
    width: root.width
    height: root.expanded ? body.implicitHeight : 0
    clip: true

    Behavior on height {
      NumberAnimation {
        duration: Theme.sectionExpandDuration
        easing.type: Easing.OutCubic
      }
    }

    Column {
      id: body

      width: parent.width
      spacing: Theme.sectionSpacing
      topPadding: 4
    }
  }
}

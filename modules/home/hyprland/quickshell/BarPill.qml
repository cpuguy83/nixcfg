import QtQuick

// Shared chrome for every text module in the bar: hover highlight, tooltip, and
// the click/scroll gestures Waybar exposed via on-click / on-scroll.
Item {
  id: root

  property alias text: label.text
  property alias textColor: label.color
  property alias textFormat: label.textFormat
  property string tooltipText: ""
  property bool highlighted: false

  signal clicked
  signal rightClicked
  signal scrolled(int steps)

  implicitWidth: label.implicitWidth + Theme.pillPadding * 2
  implicitHeight: Theme.barHeight

  Rectangle {
    anchors {
      fill: parent
      topMargin: Theme.pillMargin
      bottomMargin: Theme.pillMargin
    }
    radius: Theme.radius
    color: root.highlighted ? Theme.itemActive : mouse.containsMouse ? Theme.itemHover : "transparent"
  }

  Text {
    id: label
    anchors.centerIn: parent
    color: Theme.foreground
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    font.bold: true
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onClicked: event => {
      if (event.button === Qt.RightButton)
        root.rightClicked();
      else
        root.clicked();
    }

    // Wheel notches are 120 units each; collapse to a signed step count so
    // consumers can apply their own scroll-step.
    onWheel: event => {
      const steps = event.angleDelta.y / 120;
      if (steps !== 0)
        root.scrolled(steps > 0 ? Math.ceil(steps) : Math.floor(steps));
    }
  }

  Tooltip {
    anchorItem: root
    text: root.tooltipText
    shown: mouse.containsMouse
  }
}

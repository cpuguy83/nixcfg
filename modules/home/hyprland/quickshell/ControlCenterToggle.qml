import QtQuick

// Pill switch (§9.4): track + animated knob. `checked` drives a `Theme.accent`
// fill when on — a dedicated "this control is on" hue, distinct from any
// status colour (O-1), so an enabled toggle never reads as "connected".
Item {
  id: root

  property bool checked: false
  signal toggled(bool value)

  implicitWidth: Theme.toggleWidth
  implicitHeight: Theme.toggleHeight
  opacity: root.enabled ? 1 : 0.4

  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: root.checked ? Theme.accent : Theme.toggleOff

    Behavior on color {
      ColorAnimation {
        duration: Theme.sectionExpandDuration
      }
    }
  }

  Rectangle {
    id: knob
    width: root.height - Theme.toggleKnobMargin * 2
    height: width
    radius: width / 2
    color: Theme.sliderHandle
    anchors.verticalCenter: parent.verticalCenter
    x: root.checked ? root.width - width - Theme.toggleKnobMargin : Theme.toggleKnobMargin

    Behavior on x {
      NumberAnimation {
        duration: Theme.sectionExpandDuration
        easing.type: Easing.OutCubic
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    onClicked: root.toggled(!root.checked)
  }
}

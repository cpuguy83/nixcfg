import QtQuick

// Hand-rolled exclusive segmented control (§9.4): one Rectangle per
// {id,label} entry in `options`, selected entry filled with `Theme.accent`
// (O-1's dedicated "this control is on" hue, so a selected tier never reads
// as "connected"). First (and so far only) consumer is the audio section's
// latency tier (§9.5) - `Quickshell.Widgets` has nothing like this, and
// QtQuick.Controls is not imported anywhere in this directory.
Row {
  id: root

  property var options: [] // [{ id, label }, ...]
  property var currentId: null

  signal selected(var id)

  spacing: 2
  opacity: root.enabled ? 1 : 0.4

  Repeater {
    model: root.options

    Rectangle {
      id: segment

      required property var modelData
      readonly property bool isCurrent: segment.modelData.id === root.currentId

      // Evenly split across the row's own width, accounting for the
      // inter-segment spacing above.
      width: (root.width - (root.options.length - 1) * root.spacing) / root.options.length
      height: Theme.segmentHeight
      radius: Theme.segmentRadius
      color: segment.isCurrent ? Theme.segmentSelected : (segmentMouse.containsMouse ? Theme.itemHover : "transparent")
      border.width: segment.isCurrent ? 0 : 1
      border.color: Theme.sliderTrack

      Text {
        anchors.centerIn: parent
        text: segment.modelData.label
        color: segment.isCurrent ? Theme.foreground : Theme.foregroundDim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
      }

      MouseArea {
        id: segmentMouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.selected(segment.modelData.id)
      }
    }
  }
}

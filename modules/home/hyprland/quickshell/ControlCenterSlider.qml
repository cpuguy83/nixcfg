import QtQuick

// Hand-rolled volume-style slider (§9.4/§9.5): leading clickable glyph (mute
// toggle), horizontal track/fill/handle, trailing percent. Emits `moved`
// rather than writing `value` itself — the caller owns the real PipeWire
// node, so `value` stays a pure binding here and is never severed by an
// imperative assignment from inside this component.
Item {
  id: root

  property real value: 0 // 0..1, driven by the caller
  property bool muted: false
  property string glyph: ""

  signal moved(real value)
  signal muteToggled

  implicitHeight: Theme.sliderHeight
  opacity: root.enabled ? 1 : 0.4

  readonly property real clamped: Math.max(0, Math.min(1, root.value))

  function seek(mouseX: real) {
    if (track.width <= 0)
      return;
    root.moved(Math.max(0, Math.min(1, mouseX / track.width)));
  }

  Row {
    anchors.fill: parent
    spacing: Theme.rowSpacing

    // Bigger than the glyph itself so the mute toggle is comfortable to hit,
    // matching the row height rather than the text's own tight bounds.
    Item {
      id: glyphArea
      width: Theme.sliderHeight
      height: Theme.sliderHeight
      anchors.verticalCenter: parent.verticalCenter

      Text {
        anchors.centerIn: parent
        text: root.glyph
        color: root.muted ? Theme.foregroundDim : Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.muteToggled()
      }
    }

    Item {
      id: track
      width: root.width - glyphArea.width - percentLabel.width - Theme.rowSpacing * 2
      height: parent.height
      anchors.verticalCenter: parent.verticalCenter

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: Theme.sliderTrackHeight
        radius: height / 2
        color: Theme.sliderTrack
      }

      // Muted keeps `value` untouched and only recolours the fill (§9.5), so
      // unmuting restores exactly where the level was.
      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: track.width * root.clamped
        height: Theme.sliderTrackHeight
        radius: height / 2
        color: root.muted ? Theme.sliderFillMuted : Theme.sliderFill
      }

      Rectangle {
        width: Theme.sliderHandleSize
        height: Theme.sliderHandleSize
        radius: width / 2
        color: Theme.sliderHandle
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(track.width - width, track.width * root.clamped - width / 2))
      }

      MouseArea {
        anchors.fill: parent

        // Load-bearing (§9.9): without this, a diagonal drag that starts on
        // the slider is stolen by the panel's own Flickable the moment the
        // pointer moves far enough to look like a vertical flick.
        preventStealing: true

        // Wheel is deliberately NOT handled. The panel is tall enough to
        // scroll, and these sliders span its full width, so any wheel-scroll
        // through the panel passes over one — silently changing a volume the
        // user was only scrolling past. Leaving the event unhandled lets it
        // reach the Flickable and scroll the panel instead, which is what the
        // gesture meant. Deliberate volume-by-wheel still exists on the bar
        // button, where nothing is scrollable underneath it.
        onPressed: mouse => root.seek(mouse.x)
        onPositionChanged: mouse => {
          if (pressed)
            root.seek(mouse.x);
        }
      }
    }

    Text {
      id: percentLabel
      width: 34
      anchors.verticalCenter: parent.verticalCenter
      horizontalAlignment: Text.AlignRight
      text: `${Math.round(root.clamped * 100)}%`
      color: Theme.foregroundDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize - 2
    }
  }
}

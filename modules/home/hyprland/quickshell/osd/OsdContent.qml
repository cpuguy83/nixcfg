import QtQuick
import "Logic.js" as Logic

// Pure presentation: the layer-shell window owns routing and lifetime. Native
// state stays live; completed helper operations retain their own snapshots.
Rectangle {
  id: root

  required property var theme
  property var event: null
  property var sink: null
  property var source: null
  property string outputGlyph: ""

  readonly property string kind: event?.kind ?? ""
  readonly property bool brightness: kind === "brightness" || kind === "brightness-error"
  readonly property bool input: kind === "input"
  readonly property bool microphone: kind === "microphone"
  readonly property bool microphoneSnapshot: microphone && event?.value !== undefined
  readonly property var node: input || microphone ? source : sink
  readonly property bool available: input ? Logic.sourceReady(source, sink) : Logic.audioReady(node)
  readonly property bool failed: microphoneSnapshot ? event.value < 0 : brightness ? kind === "brightness-error" : !available
  readonly property bool muted: microphoneSnapshot ? event.muted : !brightness && !input && available && node.audio.muted
  readonly property bool microphoneOff: microphone && muted && !failed
  readonly property real value: brightness || microphoneSnapshot ? (event?.value ?? -1) : !input && available ? Math.round(node.audio.volume * 100) : -1
  readonly property bool showMeter: !failed && kind !== "output" && !input && !microphoneOff
  readonly property bool showLabel: (kind !== "volume" && !microphone) || failed
  readonly property string label: {
    if (brightness)
      return failed ? event.text : `Brightness ${value}%`;
    if (microphoneSnapshot && failed)
      return event.text;
    if (!available && !microphoneSnapshot)
      return input || microphone ? "Microphone unavailable" : "Output unavailable";
    if (input || kind === "output")
      return node.description || node.name || (input ? "Audio input" : "Audio output");
    return "";
  }

  implicitWidth: showLabel ? theme.osdWidth : theme.osdVolumeWidth
  implicitHeight: content.implicitHeight + theme.osdPadding * 2
  radius: theme.menuRadius
  color: theme.menuBackground
  border.width: 1
  border.color: theme.menuBorder

  Column {
    id: content
    anchors {
      left: parent.left
      right: parent.right
      top: parent.top
      margins: root.theme.osdPadding
    }
    spacing: root.theme.osdPadding

    Item {
      width: parent.width
      height: Math.max(root.theme.osdIconSize, label.visible ? label.implicitHeight : 0)

      Item {
        id: icon
        width: root.showLabel ? root.theme.osdIconSize : parent.width
        height: root.theme.osdIconSize
        anchors.verticalCenter: parent.verticalCenter

        VolumeIcon {
          objectName: "volumeIcon"
          anchors.centerIn: parent
          width: root.theme.osdIconSize
          height: width
          visible: root.kind === "volume"
          volumePercent: root.value
          muted: root.muted
          foreground: root.failed ? root.theme.statusError : root.theme.foreground
        }

        MicrophoneIcon {
          objectName: "microphoneIcon"
          anchors.centerIn: parent
          width: root.theme.osdIconSize
          height: width
          visible: root.input || root.microphone
          muted: root.muted
          foreground: root.failed || root.microphoneOff ? root.theme.statusError : root.theme.foreground
        }

        Text {
          objectName: "glyph"
          anchors.centerIn: parent
          visible: root.kind !== "volume" && !root.input && !root.microphone
          text: root.brightness ? (root.failed ? "!" : "\u2600") : root.outputGlyph
          color: root.failed ? root.theme.statusError : root.theme.foreground
          font.family: root.theme.fontFamily
          font.pixelSize: root.theme.osdIconSize
        }
      }

      Text {
        id: label
        objectName: "label"
        anchors {
          left: icon.right
          leftMargin: root.showLabel ? root.theme.osdPadding : 0
          right: parent.right
          verticalCenter: parent.verticalCenter
        }
        visible: root.showLabel
        text: root.label
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        maximumLineCount: 3
        elide: Text.ElideRight
        color: root.theme.foreground
        font.family: root.theme.fontFamily
        font.pixelSize: root.theme.osdFontSize
      }
    }

    Rectangle {
      id: meter
      objectName: "meter"
      visible: root.showMeter
      width: parent.width
      height: root.theme.osdTrackHeight
      radius: height / 2
      color: root.theme.sliderTrack

      // A short retargetable transition, not a queue of per-key animations.
      property real level: Math.max(0, Math.min(100, root.value))
      property bool completed: false
      Component.onCompleted: completed = true
      Behavior on level {
        enabled: meter.completed && meter.visible
        NumberAnimation {
          duration: root.theme.osdMeterDuration
          easing.type: Easing.OutCubic
        }
      }

      Rectangle {
        objectName: "meterFill"
        width: parent.width * meter.level / 100
        height: parent.height
        radius: parent.radius
        color: root.muted ? root.theme.sliderFillMuted : root.theme.sliderFill
      }
    }
  }
}

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "osd" as State
import "osd/Logic.js" as Logic

Scope {
  id: root

  signal display(string screenName, var event)

  function show(event, requestedScreen) {
    const target = Logic.screenName(Quickshell.screens, requestedScreen, Hyprland.focusedMonitor?.name ?? "");
    if (target)
      root.display(target, event);
  }

  State.AudioFeedback {
    id: audio
    audioState: AudioState
    onNotified: kind => root.show({
        kind: kind
      }, "")
    onMicrophoneRequested: sourceId => microphoneProcess.start(sourceId)
    onMicrophoneNotified: event => root.show(event, "")
  }

  State.MicrophoneProcess {
    id: microphoneProcess
    helper: Quickshell.env("QS_MIC_MUTE_HELPER") ?? ""
    onFinished: (exitCode, output, errorText) => audio.finishMicrophone(exitCode, output, errorText)
  }

  GlobalShortcut {
    appid: "quickshell"
    name: "volumeUp"
    description: "Raise output volume"
    onPressed: audio.control("volume", 1)
  }

  GlobalShortcut {
    appid: "quickshell"
    name: "volumeDown"
    description: "Lower output volume"
    onPressed: audio.control("volume", -1)
  }

  GlobalShortcut {
    appid: "quickshell"
    name: "volumeMute"
    description: "Toggle output mute"
    onPressed: audio.control("volume", 0)
  }

  GlobalShortcut {
    appid: "quickshell"
    name: "micMute"
    description: "Toggle microphone mute"
    onPressed: audio.control("microphone", 0)
  }

  State.BrightnessServer {
    onReceived: event => root.show(event, event.screen)
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: overlay
      required property var modelData

      property State.Entry entry: State.Entry {
        duration: Theme.osdDuration
      }

      readonly property string kind: entry.event?.kind ?? ""
      readonly property bool brightness: kind === "brightness" || kind === "brightness-error"
      readonly property bool microphone: kind === "microphone"

      // Native audio remains live. Virtual microphones and brightness use
      // completed-operation snapshots, not predictions of a successful write.
      readonly property bool microphoneSnapshot: microphone && entry.event?.value !== undefined
      readonly property var node: microphone ? AudioState.source : AudioState.sink
      readonly property bool available: Logic.audioReady(node)
      readonly property bool failed: microphoneSnapshot ? entry.event.value < 0 : brightness ? kind === "brightness-error" : !available
      readonly property bool muted: microphoneSnapshot ? entry.event.muted : !brightness && available && node.audio.muted
      readonly property real value: brightness || microphoneSnapshot ? (entry.event?.value ?? -1) : available ? Math.round(node.audio.volume * 100) : -1
      readonly property bool showMeter: !failed && kind !== "output"

      readonly property string glyph: {
        if (brightness)
          return failed ? "!" : "\u2600";
        if (microphone)
          return muted ? Icons.micMuted : Icons.micOn;
        return AudioState.sinkIcon(node);
      }

      readonly property string label: {
        if (brightness)
          return failed ? entry.event.text : `Brightness ${value}%`;
        if (microphoneSnapshot && failed)
          return entry.event.text;
        if (!available && !microphoneSnapshot)
          return microphone ? "Microphone unavailable" : "Output unavailable";
        if (kind === "output")
          return node.description || node.name || "Audio output";
        return `${microphone ? "Microphone" : "Volume"} ${muted ? "muted" : value + "%"}`;
      }

      Connections {
        target: root
        function onDisplay(screenName, event) {
          if (screenName === overlay.modelData.name)
            overlay.entry.show(event);
        }
      }

      screen: modelData
      visible: entry.active
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      implicitWidth: Theme.osdWidth
      implicitHeight: content.implicitHeight + Theme.osdPadding * 2
      anchors.bottom: true
      margins.bottom: Theme.osdBottomMargin

      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "quickshell-osd"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}

      Rectangle {
        anchors.fill: parent
        radius: Theme.menuRadius
        color: Theme.menuBackground
        border.width: 1
        border.color: Theme.menuBorder

        Column {
          id: content
          anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: Theme.osdPadding
          }
          spacing: Theme.osdPadding

          Row {
            width: parent.width
            spacing: Theme.osdPadding

            Text {
              id: icon
              text: overlay.glyph
              color: overlay.failed ? Theme.statusError : Theme.foreground
              font.family: Theme.fontFamily
              font.pixelSize: Theme.iconSize
            }

            Text {
              width: parent.width - icon.width - parent.spacing
              text: overlay.label
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              maximumLineCount: 3
              elide: Text.ElideRight
              color: Theme.foreground
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSize
            }
          }

          Rectangle {
            visible: overlay.showMeter
            width: parent.width
            height: Theme.sliderTrackHeight
            radius: height / 2
            color: Theme.sliderTrack

            Rectangle {
              width: parent.width * Math.max(0, Math.min(100, overlay.value)) / 100
              height: parent.height
              radius: parent.radius
              color: overlay.muted ? Theme.sliderFillMuted : Theme.sliderFill
            }
          }
        }
      }
    }
  }
}

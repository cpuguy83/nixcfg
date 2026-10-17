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
      implicitWidth: content.implicitWidth
      implicitHeight: content.implicitHeight
      anchors.bottom: true
      // Keep the panel's center one-third up, regardless of its content height.
      margins.bottom: Math.max(0, Math.round(modelData.height / 3 - implicitHeight / 2))

      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "quickshell-osd"
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      mask: Region {}

      State.OsdContent {
        id: content
        anchors.fill: parent
        theme: Theme
        event: overlay.entry.event
        sink: AudioState.sink
        source: AudioState.source
        outputGlyph: AudioState.sinkIcon(AudioState.sink)
      }
    }
  }
}

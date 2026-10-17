import QtQuick
import Quickshell
import Quickshell.Io
import "osd" as State

// Nonvisual integration fixture: production endpoints, fake audio only.
Scope {
  id: root
  property var lastEvent: ({})
  property var microphoneEvents: []
  State.BrightnessServer {
    onReceived: event => root.lastEvent = event
  }
  QtObject {
    id: fakeAudio
    property var sink: ({
        id: 1,
        ready: true,
        audio: {
          volume: 0.5,
          muted: false
        }
      })
    property var source: ({
        id: 42,
        ready: true,
        isSink: false
      })
  }
  State.AudioFeedback {
    id: audio
    audioState: fakeAudio
    onMicrophoneRequested: sourceId => helper.start(sourceId)
    onMicrophoneNotified: event => root.microphoneEvents.push(event)
  }
  State.MicrophoneProcess {
    id: helper
    helper: Quickshell.env("QS_MIC_MUTE_HELPER")
    onFinished: (exitCode, output, errorText) => audio.finishMicrophone(exitCode, output, errorText)
  }
  IpcHandler {
    target: "probe"
    function last(): string {
      return JSON.stringify(root.lastEvent);
    }
    function microphone(id: int, count: int): void {
      fakeAudio.source = {
        id: id,
        ready: true,
        isSink: false
      };
      for (let i = 0; i < count; ++i)
        audio.control("microphone", 0);
    }
    function events(): string {
      return JSON.stringify(root.microphoneEvents);
    }
    function missingHelper(): void {
      helper.helper = "/nonexistent/nixcfg-microphone-helper";
    }
  }
}

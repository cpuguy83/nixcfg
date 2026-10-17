import QtQuick
import "Logic.js" as Logic

// Kept independent of PipeWire imports so lifecycle/failed-write behavior can
// be tested with fake nodes, without touching the running audio session.
QtObject {
  id: root

  required property var audioState
  signal notified(string kind)
  signal microphoneRequested(string sourceId)
  signal microphoneNotified(var event)

  property var microphoneQueue: []
  property bool microphoneBusy: false

  function nextMicrophone() {
    if (root.microphoneBusy || root.microphoneQueue.length === 0)
      return;
    root.microphoneBusy = true;
    root.microphoneRequested(root.microphoneQueue.shift());
  }

  function finishMicrophone(exitCode, output, errorText) {
    if (!root.microphoneBusy)
      return;
    let event;
    try {
      if (exitCode !== 0)
        throw new Error(errorText || `helper exited ${exitCode}`);
      event = Logic.microphoneEvent(output);
    } catch (error) {
      event = {
        kind: "microphone",
        value: -1,
        muted: false,
        text: `Microphone mute failed: ${error}`
      };
    }
    root.microphoneNotified(event);
    root.microphoneBusy = false;
    Qt.callLater(root.nextMicrophone);
  }

  readonly property string outputKey: Logic.outputKey(root.audioState.sink)
  property string lastOutputKey: ""
  property bool initialized: false
  property string requestedKind: "volume"

  // Startup establishes a baseline, not a queued notification. Both settling
  // and the hard deadline read the *current* default, never a captured node.
  property Timer startup: Timer {
    interval: 1000
    running: true
    onTriggered: {
      root.lastOutputKey = root.outputKey;
      root.initialized = true;
    }
  }

  onOutputKeyChanged: {
    if (!root.initialized)
      return;

    settle.restart();
    if (!deadline.running)
      deadline.start();
  }

  function flushOutput() {
    settle.stop();
    deadline.stop();
    if (root.lastOutputKey === root.outputKey)
      return;

    root.lastOutputKey = root.outputKey;
    root.notified("output");
  }

  property Timer settle: Timer {
    interval: 150
    onTriggered: root.flushOutput()
  }

  property Timer deadline: Timer {
    interval: 1000
    onTriggered: root.flushOutput()
  }

  function control(kind, steps) {
    const source = root.audioState.source;
    const node = kind === "microphone" ? (source?.isSink || source?.id === root.audioState.sink?.id ? null : source) : root.audioState.sink;
    // QS 0.3.0 does not expose .audio for Audio/Source/Virtual (EasyEffects).
    // Capture the explicit source id at keypress; never use a sink/default
    // selector in the helper, and never drop repeated presses while it runs.
    if (kind === "microphone" && steps === 0 && node && !node.audio && Number.isInteger(node.id) && node.id > 0) {
      root.microphoneQueue.push(String(node.id));
      root.nextMicrophone();
      return;
    }
    if (Logic.audioReady(node)) {
      if (steps === 0)
        root.audioState.toggleMute(node);
      else
        root.audioState.adjustVolume(node, steps);
    }

    // Even a no-op at the cap or an unavailable device gets feedback. Never
    // compute an expected volume/mute result: the view reads native state.
    root.requestedKind = kind;
    if (!feedback.running)
      feedback.start();
  }

  property Timer feedback: Timer {
    interval: 80
    onTriggered: root.notified(root.requestedKind)
  }
}

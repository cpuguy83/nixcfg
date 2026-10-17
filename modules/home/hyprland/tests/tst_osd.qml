import QtQuick
import QtTest
import "../quickshell/osd" as State
import "../quickshell/osd/Logic.js" as Logic

TestCase {
  id: tests
  name: "Osd"

  Component {
    id: entryComponent
    State.Entry {
      duration: 200
    }
  }

  Component {
    id: audioComponent
    State.AudioFeedback {}
  }

  QtObject {
    id: fakeAudio
    property var sink: null
    property var source: null
    property var calls: []

    // Deliberately reject writes: feedback must not invent a successful state.
    function toggleMute(node) {
      calls.push(["mute", node]);
    }
    function adjustVolume(node, steps) {
      calls.push(["volume", node, steps]);
    }
  }

  SignalSpy {
    id: feedback
    signalName: "notified"
  }
  SignalSpy {
    id: microphoneRequests
    signalName: "microphoneRequested"
  }
  SignalSpy {
    id: microphoneFeedback
    signalName: "microphoneNotified"
  }
  SignalSpy {
    id: visibility
    signalName: "activeChanged"
  }

  function node(id, ready = true) {
    return {
      id: id,
      name: "sink-" + id,
      ready: ready,
      audio: {
        volume: 0.5,
        muted: false
      }
    };
  }

  function observer() {
    const audio = createTemporaryObject(audioComponent, tests, {
      audioState: fakeAudio
    });
    verify(audio !== null);
    feedback.target = audio;
    microphoneRequests.target = audio;
    microphoneFeedback.target = audio;
    return audio;
  }

  function init() {
    fakeAudio.sink = null;
    fakeAudio.source = null;
    fakeAudio.calls = [];
    feedback.clear();
    microphoneRequests.clear();
    microphoneFeedback.clear();
  }

  function test_protocol() {
    compare(Logic.brightnessEvent("DP-1", 42, "").value, 42);
    compare(Logic.brightnessEvent("", -1, "read\nfailed").text, "read\nfailed");
    for (const args of [[null, 50, ""], ["", 101, ""], ["", 0.5, ""], ["", 50, null], ["", 50, "error"], ["", -1, ""], ["", -2, "error"]]) {
      let rejected = false;
      try {
        Logic.brightnessEvent(...args);
      } catch (error) {
        rejected = true;
      }
      verify(rejected, JSON.stringify(args));
    }
  }

  function test_virtual_microphone_queue_and_snapshot() {
    const audio = observer();
    fakeAudio.sink = node(1);
    fakeAudio.source = {
      id: 42,
      name: "easyeffects_source",
      ready: true,
      isSink: false
    };
    audio.control("microphone", 0);
    audio.control("microphone", 0);
    fakeAudio.source = {
      id: 43,
      name: "another_source",
      ready: true,
      isSink: false
    };
    audio.control("microphone", 0);
    compare(microphoneRequests.count, 1);
    compare(microphoneRequests.signalArguments[0][0], "42");
    compare(fakeAudio.calls.length, 0);
    audio.finishMicrophone(0, "Volume: 0.75 [MUTED]\n", "");
    compare(microphoneFeedback.signalArguments[0][0].muted, true);
    compare(microphoneFeedback.signalArguments[0][0].value, 75);
    tryCompare(microphoneRequests, "count", 2);
    compare(microphoneRequests.signalArguments[1][0], "42");
    audio.finishMicrophone(0, "Volume: 0.75\n", "");
    tryCompare(microphoneRequests, "count", 3);
    compare(microphoneRequests.signalArguments[2][0], "43");
    audio.finishMicrophone(0, "Volume: 0.50\n", "");
    compare(microphoneFeedback.count, 3);
    compare(fakeAudio.sink.audio.muted, false);
    compare(fakeAudio.calls.length, 0);
  }

  function test_virtual_microphone_failure_and_sink_isolation() {
    const audio = observer();
    fakeAudio.sink = node(1);
    fakeAudio.source = {
      id: 42,
      isSink: false
    };
    audio.control("microphone", 0);
    audio.control("microphone", 0);
    audio.finishMicrophone(1, "Volume: 0.50 [MUTED]", "permission denied");
    compare(microphoneFeedback.signalArguments[0][0].value, -1);
    verify(microphoneFeedback.signalArguments[0][0].text.includes("permission denied"));
    tryCompare(microphoneRequests, "count", 2); // Failure does not discard the next press.
    audio.finishMicrophone(0, "invalid output", "");
    compare(microphoneFeedback.signalArguments[1][0].value, -1);
    fakeAudio.source = {
      id: 1
    };
    audio.control("microphone", 0);
    fakeAudio.source = {
      id: 7,
      isSink: true
    };
    audio.control("microphone", 0);
    fakeAudio.source = {
      id: "42; bad"
    };
    audio.control("microphone", 0);
    fakeAudio.source = fakeAudio.sink;
    audio.control("microphone", 0);
    compare(microphoneRequests.count, 2);
    compare(fakeAudio.calls.length, 0);
  }

  function test_screen_targeting() {
    const screens = [
      {
        name: "DP-1"
      },
      {
        name: "DP-2"
      }
    ];
    compare(Logic.screenName(screens, "DP-1", "DP-2"), "DP-1");
    compare(Logic.screenName(screens, "HDMI-A-1", "DP-2"), "DP-2");
    compare(Logic.screenName(screens, "", "DP-2"), "DP-2");
    compare(Logic.screenName(screens, "", "missing"), "DP-1");
    compare(Logic.screenName([], "", ""), "");
  }

  function test_repeat_and_monitor_isolation() {
    const first = createTemporaryObject(entryComponent, tests);
    const second = createTemporaryObject(entryComponent, tests);
    first.show({
      kind: "brightness",
      value: 20
    });
    second.show({
      kind: "brightness",
      value: 80
    });
    wait(120);
    first.show({
      kind: "brightness",
      value: 30
    });
    wait(120);
    verify(first.active);
    verify(!second.active);
    compare(first.event.value, 30);
    compare(second.event.value, 80);
    tryCompare(first, "active", false, 400);
  }

  function test_updates_keep_indicator_visible() {
    const entry = createTemporaryObject(entryComponent, tests);
    visibility.target = entry;
    visibility.clear();

    entry.show({
      kind: "volume",
      value: 20
    });
    verify(entry.active);
    compare(visibility.count, 1);
    visibility.clear();

    for (let value = 25; value <= 50; value += 5) {
      wait(40);
      entry.show({
        kind: "volume",
        value: value
      });
      compare(entry.event.value, value);
      verify(entry.active);
      compare(visibility.count, 0, "Updating content must not hide and remap the window");
    }

    wait(120);
    verify(entry.active);
    compare(visibility.count, 0);
    tryCompare(entry, "active", false, 400);
    compare(visibility.count, 1);

    entry.show({
      kind: "volume",
      value: 55
    });
    verify(entry.active);
    compare(visibility.count, 2);
  }

  function test_audio_controls_unavailable_and_rejected_writes() {
    const audio = observer();
    audio.control("volume", 1);
    audio.control("microphone", 0);
    compare(fakeAudio.calls.length, 0);
    feedback.wait();
    compare(feedback.signalArguments[0][0], "microphone");

    fakeAudio.sink = node(1, false);
    audio.control("volume", 1);
    compare(fakeAudio.calls.length, 0);
    fakeAudio.sink = node(1);
    fakeAudio.source = node(2);
    audio.control("volume", 1);
    audio.control("volume", -1);
    audio.control("volume", 0);
    audio.control("microphone", 0);
    compare(fakeAudio.calls.map(call => call[0]), ["volume", "volume", "mute", "mute"]);
    compare(fakeAudio.calls[0][2], 1);
    compare(fakeAudio.calls[1][2], -1);
    compare(fakeAudio.calls[2][1], fakeAudio.sink);
    compare(fakeAudio.calls[3][1], fakeAudio.source);
    compare(fakeAudio.sink.audio.volume, 0.5);
    compare(fakeAudio.source.audio.muted, false);
    feedback.wait();
    compare(feedback.signalArguments[1][0], "microphone");
  }

  function test_default_output_settles_current_state() {
    const audio = observer();
    fakeAudio.sink = node(1);
    tryCompare(audio, "initialized", true, 1500);
    compare(feedback.count, 0); // No startup event replay.
    fakeAudio.sink = node(2, false);
    fakeAudio.sink = node(3);
    feedback.wait();
    compare(feedback.count, 1);
    compare(audio.lastOutputKey, "3:sink-3");

    fakeAudio.sink = null;
    feedback.wait();
    compare(audio.lastOutputKey, "unavailable");
    fakeAudio.sink = node(4);
    feedback.wait();
    compare(audio.lastOutputKey, "4:sink-4");

    // A transient default switch which returns to the same node is silent.
    fakeAudio.sink = node(5);
    fakeAudio.sink = node(4);
    wait(220);
    compare(feedback.count, 3);
  }

  function test_default_output_has_hard_deadline() {
    const audio = observer();
    tryCompare(audio, "initialized", true, 1500);
    for (let i = 1; i <= 12; ++i) {
      fakeAudio.sink = node(i);
      wait(100); // Keep restarting the settle timer.
    }
    verify(feedback.count >= 1);
    compare(feedback.signalArguments[0][0], "output");
    tryCompare(audio, "lastOutputKey", "12:sink-12", 500);
  }

  function test_null_sink_is_unavailable() {
    compare(Logic.audioReady(null), false);
    compare(Logic.audioReady({
      ready: true,
      name: "auto_null",
      audio: {}
    }), false);
    compare(Logic.audioReady({
      ready: true
    }), false);
  }
}

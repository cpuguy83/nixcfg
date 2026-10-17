import QtQuick
import Quickshell.Io

QtObject {
  id: root
  required property string helper
  signal finished(int exitCode, string output, string errorText)
  property bool pending: false

  function start(sourceId) {
    if (!root.helper) {
      root.finished(1, "", "microphone helper is not configured");
      return;
    }
    root.pending = true;
    process.command = [root.helper, sourceId];
    process.running = true;
  }

  function complete(exitCode, errorText) {
    if (!root.pending)
      return;
    root.pending = false;
    root.finished(exitCode, output.text, errorText);
  }

  property Process process: Process {
    id: process
    stdout: StdioCollector {
      id: output
    }
    stderr: StdioCollector {
      id: errors
    }
    onExited: (exitCode, exitStatus) => root.complete(exitStatus === 0 ? exitCode : -1, errors.text)
    // Failed-to-start does not necessarily emit exited. Defer until after
    // normal exit handling and stream collection have had a chance to finish.
    onRunningChanged: {
      if (!running)
        Qt.callLater(() => {
          if (root.pending && !process.running)
            root.complete(-1, "microphone helper failed to start");
        });
    }
  }
}

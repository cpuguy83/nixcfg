import QtQuick
import Quickshell
import Quickshell.Io

// Waybar's custom/<name> with return-type=json: poll a command on an interval,
// read {text, tooltip} off stdout, and fire commands on click.
BarPill {
  id: root

  required property list<string> statusCommand
  property list<string> clickCommand: []
  property list<string> rightClickCommand: []
  property int pollInterval: 5000

  // Waybar coloured these modules from CSS keyed on the payload's `class`.
  // Classes absent from the map keep the default foreground.
  property var classColors: ({})

  property string statusClass: ""

  textColor: root.classColors[root.statusClass] ?? Theme.foreground

  // Nothing to show until the first successful poll, and an empty pill would
  // otherwise sit in the layout as dead space.
  visible: text !== ""

  onClicked: {
    if (root.clickCommand.length > 0)
      Quickshell.execDetached(root.clickCommand);
  }

  onRightClicked: {
    if (root.rightClickCommand.length > 0)
      Quickshell.execDetached(root.rightClickCommand);
  }

  Process {
    id: poll
    command: root.statusCommand

    stdout: StdioCollector {
      id: output

      onStreamFinished: {
        try {
          const parsed = JSON.parse(output.text);
          root.text = parsed.text ?? "";
          root.tooltipText = parsed.tooltip ?? "";
          root.statusClass = parsed.class ?? "";
        } catch (error) {
          // A broken or partial payload should blank the pill rather than
          // freeze the last good value and quietly report stale state.
          root.text = "";
          root.tooltipText = "";
          root.statusClass = "";
        }
      }
    }
  }

  Timer {
    running: root.statusCommand.length > 0 && root.statusCommand[0] !== ""
    repeat: true
    triggeredOnStart: true
    interval: root.pollInterval
    onTriggered: poll.running = true
  }
}

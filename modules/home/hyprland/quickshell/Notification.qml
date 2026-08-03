import QtQuick
import Quickshell
import Quickshell.Io

// swaync streams a JSON line per state change rather than being polled, so this
// holds one long-lived process instead of the poll-on-a-Timer shape most
// other status pills use.
BarPill {
  id: root

  property string alt: "none"

  readonly property string glyph: Icons.notification[root.alt] ?? Icons.bell

  text: ` ${root.glyph}  `
  // Only the dnd/inhibited states carry a red superscript badge; plain states
  // stay PlainText so their padding spaces are not collapsed as HTML.
  textFormat: root.glyph.includes("<") ? Text.RichText : Text.PlainText

  onClicked: Quickshell.execDetached(["swaync-client", "-t", "-sw"])
  onRightClicked: Quickshell.execDetached(["swaync-client", "-d", "-sw"])

  Process {
    running: true
    command: ["swaync-client", "-swb"]

    stdout: SplitParser {
      splitMarker: "\n"

      onRead: data => {
        try {
          root.alt = JSON.parse(data).alt ?? "none";
        } catch (error) {
          // Hold the last known state; a dropped line is not a state change.
        }
      }
    }
  }
}

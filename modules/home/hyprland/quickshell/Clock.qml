import QtQuick
import Quickshell

Text {
  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }

  // Sized to the bar so it centres correctly wherever it is placed.
  height: Theme.barHeight
  leftPadding: Theme.pillPadding
  rightPadding: Theme.pillPadding

  text: Qt.formatDateTime(clock.date, "HH:mm")
  color: Theme.foreground
  font.family: Theme.fontFamily
  font.pixelSize: Theme.fontSize
  font.bold: true
  verticalAlignment: Text.AlignVCenter
}

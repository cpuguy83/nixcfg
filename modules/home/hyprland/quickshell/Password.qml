import QtQuick
import Quickshell

BarPill {
  text: ` ${Icons.password} `

  onClicked: Quickshell.execDetached(["1password", "--quick-access"])
  onRightClicked: Quickshell.execDetached(["1password"])
}

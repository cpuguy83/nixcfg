import QtQuick

// Generic password-style text field (§9.4). Deliberately has no dependency on
// ControlCenter/NetworkState - the first caller (NetworkSection, stage 5)
// wires `text` to `NetworkState.pendingPassphrase` itself. This component
// never persists what is typed into it anywhere beyond its own `text`
// property (I9): nothing here logs it, writes it to a file, or hands it to a
// Process.
Item {
  id: root

  property alias text: input.text
  property string placeholder: ""
  property bool revealed: false

  // Focus only self-heals to whichever ambient item declares `focus: true` at
  // window-activation time; once a nested item such as this field's own
  // `TextInput` explicitly steals activeFocus and later releases it, nothing
  // reclaims it automatically (confirmed against the real compositor while
  // building this stage - releasing via `focus = false` alone leaves nothing
  // with activeFocus at all). A caller whose own Escape/outside-click chain
  // needs that ambient item to work again afterward should set this to it.
  property Item focusFallback: null

  signal accepted

  implicitWidth: 220
  implicitHeight: Theme.fieldHeight

  Rectangle {
    anchors.fill: parent
    radius: Theme.fieldRadius
    color: Theme.fieldBackground
    border.width: input.activeFocus ? 2 : 1
    border.color: input.activeFocus ? Theme.accent : Theme.fieldBorder
  }

  Component.onCompleted: input.forceActiveFocus()

  TextInput {
    id: input

    anchors {
      left: parent.left
      right: revealButton.left
      leftMargin: Theme.rowPaddingH
      rightMargin: Theme.rowSpacing
      verticalCenter: parent.verticalCenter
    }

    echoMode: root.revealed ? TextInput.Normal : TextInput.Password
    color: Theme.foreground
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    clip: true
    selectByMouse: true

    Keys.onReturnPressed: event => {
      event.accepted = true;
      root.accepted();
    }

    // Only ever runs while this field actually holds activeFocus (key events
    // go to whichever item currently has it), so the only extra condition
    // needed here is "non-empty" (§9.4) - an empty field has no text worth
    // preserving, so Escape is left unaccepted and bubbles to whatever
    // dismiss chain hosts this field.
    Keys.onEscapePressed: event => {
      if (input.text.length === 0) {
        event.accepted = false;
        return;
      }
      event.accepted = true;
      input.focus = false;
      if (root.focusFallback)
        root.focusFallback.forceActiveFocus();
    }

    Text {
      anchors.fill: parent
      visible: input.text.length === 0
      text: root.placeholder
      color: Theme.foregroundDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }
  }

  Item {
    id: revealButton

    width: Theme.fieldHeight
    height: Theme.fieldHeight
    anchors {
      right: parent.right
      verticalCenter: parent.verticalCenter
    }

    Text {
      anchors.centerIn: parent
      text: root.revealed ? Icons.revealOff : Icons.reveal
      color: Theme.foregroundDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize - 2
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.revealed = !root.revealed
    }
  }
}

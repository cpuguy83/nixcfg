import QtQuick

// "Current value + expand to a radio list" inline expander (§9.4). Used for
// the output/input device pickers today. Deliberately a plain Column that
// grows the panel's own Flickable rather than a popup — a second xdg_popup
// under an Exclusive-focus layer surface is a focus problem this design does
// not need (§9.1).
Column {
  id: root

  // Identity for the single-open-picker invariant (I7). `ControlCenter.openPicker`
  // holds at most one of these at a time, so opening a picker closes any
  // other one for free — there is only ever one string to hold.
  property string pickerId: ""
  // Optional bold prefix naming what is being selected ("Output", "Input").
  property string title: ""

  property string label: ""
  property var options: [] // [{ id, label }, ...]
  property var currentId: null

  signal selected(var id)

  readonly property bool expandedState: root.pickerId !== "" && ControlCenter.openPicker === root.pickerId

  Rectangle {
    id: header
    width: root.width
    height: Theme.rowHeight
    radius: Theme.rowRadius
    color: headerMouse.containsMouse ? Theme.itemHover : "transparent"

    // Optional leading label, bold, naming what this picker selects — e.g.
    // "Output" ahead of the current sink. Lets a caller fold what used to be
    // a separate heading line into the picker row itself,
    // which both saves a line and ties the name to the control instead of
    // leaving it floating above a slider.
    Text {
      id: title

      visible: root.title !== ""
      anchors {
        left: parent.left
        leftMargin: Theme.rowPaddingH
        verticalCenter: parent.verticalCenter
      }
      text: root.title
      color: Theme.foreground
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize
      font.bold: true
    }

    Text {
      anchors {
        left: title.visible ? title.right : parent.left
        right: chevron.left
        leftMargin: title.visible ? Theme.rowSpacing : Theme.rowPaddingH
        rightMargin: Theme.rowSpacing
        verticalCenter: parent.verticalCenter
      }
      elide: Text.ElideRight
      // Right-aligned when a title is present so the two read as
      // "label ......... value", the same shape the section headers use for
      // their own summaries.
      horizontalAlignment: title.visible ? Text.AlignRight : Text.AlignLeft
      text: root.label
      color: title.visible ? Theme.foregroundDim : Theme.foreground
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize
    }

    Text {
      id: chevron
      anchors {
        right: parent.right
        rightMargin: Theme.rowPaddingH
        verticalCenter: parent.verticalCenter
      }
      text: Icons.menuSubmenu
      rotation: root.expandedState ? 90 : 0
      color: Theme.foregroundDim
      font.family: Theme.fontFamily
      font.pixelSize: Theme.fontSize - 4
    }

    MouseArea {
      id: headerMouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: ControlCenter.openPicker = root.expandedState ? "" : root.pickerId
    }
  }

  Item {
    id: body
    width: root.width
    height: root.expandedState ? list.implicitHeight : 0
    clip: true

    Behavior on height {
      NumberAnimation {
        duration: Theme.sectionExpandDuration
        easing.type: Easing.OutCubic
      }
    }

    Column {
      id: list
      width: body.width

      Repeater {
        model: root.options

        Rectangle {
          id: optionRow

          required property var modelData

          width: list.width
          height: Theme.rowHeight
          radius: Theme.rowRadius
          color: optionMouse.containsMouse ? Theme.itemHover : "transparent"

          Text {
            anchors {
              left: parent.left
              right: check.left
              leftMargin: Theme.rowPaddingH
              rightMargin: Theme.rowSpacing
              verticalCenter: parent.verticalCenter
            }
            elide: Text.ElideRight
            text: optionRow.modelData.label
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
          }

          Text {
            id: check
            anchors {
              right: parent.right
              rightMargin: Theme.rowPaddingH
              verticalCenter: parent.verticalCenter
            }
            visible: optionRow.modelData.id === root.currentId
            text: Icons.menuCheck
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 2
          }

          MouseArea {
            id: optionMouse
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
              root.selected(optionRow.modelData.id);
              ControlCenter.openPicker = "";
            }
          }
        }
      }
    }
  }
}

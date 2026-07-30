import QtQuick
import Quickshell
import Quickshell.Widgets

// A tray menu drawn in QML rather than handed to Qt's platform menu, which
// ignores styling entirely. Frosted glass comes from the translucent background
// plus the `blur_popups` layerrule on the `quickshell-bar` namespace.
PopupWindow {
  id: root

  // What the popup hangs off: the tray icon for a top-level menu, the parent
  // row for a submenu.
  property Item anchorItem: null

  // The QsMenuHandle to list. Connecting an opener to it is what asks the tray
  // application for its contents, so that is deferred until the menu is shown.
  property var menuHandle: null

  // Submenus hand ownership of the popup grab and of closing to the top-level
  // menu, so the whole chain tears down as one.
  property var rootMenu: root
  readonly property bool isRoot: root.rootMenu === root

  property bool shown: false

  visible: root.shown && entries.count > 0
  color: "transparent"

  // An xdg_popup grab: the compositor routes clicks outside the popup back as a
  // dismiss instead of to whatever was under them. Each level of the chain has
  // to take its own grab, or the parent's grab swallows input to the submenu.
  grabFocus: true

  onClosed: {
    if (root.isRoot)
      root.shown = false;
  }

  implicitWidth: column.width + Theme.menuPadding * 2
  implicitHeight: column.height + Theme.menuPadding * 2

  anchor.item: root.anchorItem
  anchor.edges: root.isRoot ? (Theme.barAtBottom ? Edges.Top : Edges.Bottom) : (Edges.Right | Edges.Top)
  anchor.gravity: root.isRoot ? (Theme.barAtBottom ? Edges.Top : Edges.Bottom) : (Edges.Right | Edges.Bottom)

  // Without Flip — the default is Slide alone — a submenu that will not fit to
  // the right of a menu near the screen edge is slid back over its parent
  // rather than opened on the other side.
  anchor.adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide

  onShownChanged: {
    if (!root.shown)
      column.openIndex = -1;
  }

  QsMenuOpener {
    id: opener
    menu: root.shown ? root.menuHandle : null
  }

  Rectangle {
    anchors.fill: parent
    radius: Theme.menuRadius
    color: Theme.menuBackground
    border.width: 1
    border.color: Theme.menuBorder

    // A positioner takes its implicit size from the laid-out width of its
    // children, so the rows must not be sized from the column in turn. They keep
    // their natural width, and anything that has to span the menu — the hover
    // highlight, the hit area, the separator — is sized from `column.width`.
    Column {
      id: column

      // The chain only ever has one submenu open per level. Tracking it by index
      // rather than by hover keeps it open while the pointer is inside it, since
      // that is a separate surface and the row stops reporting a hover.
      property int openIndex: -1

      x: Theme.menuPadding
      y: Theme.menuPadding
      spacing: Theme.menuItemSpacing

      Repeater {
        id: entries
        model: opener.children

        Item {
          id: row

          required property int index
          required property var modelData

          readonly property bool separator: row.modelData.isSeparator
          readonly property bool highlighted: rowMouse.containsMouse || column.openIndex === row.index

          implicitWidth: row.separator ? 0 : content.implicitWidth + Theme.menuItemPaddingH * 2 + (row.modelData.hasChildren ? chevron.implicitWidth + Theme.menuItemPaddingH : 0)
          implicitHeight: row.separator ? 1 : Math.max(Theme.menuItemMinHeight, content.implicitHeight) + Theme.menuItemPaddingV * 2

          Rectangle {
            x: Theme.menuSeparatorMargin
            width: column.width - Theme.menuSeparatorMargin * 2
            height: 1
            visible: row.separator
            color: Theme.menuBorder
          }

          Rectangle {
            width: column.width
            height: row.height
            visible: !row.separator
            radius: Theme.menuItemRadius
            color: row.highlighted ? Theme.menuItemHover : "transparent"
          }

          Row {
            id: content

            anchors {
              left: parent.left
              leftMargin: Theme.menuItemPaddingH
              verticalCenter: parent.verticalCenter
            }
            visible: !row.separator
            spacing: Theme.menuItemPaddingH / 2

            Text {
              anchors.verticalCenter: parent.verticalCenter
              visible: row.modelData.buttonType !== QsMenuButtonType.None
              width: Theme.menuIconSize
              horizontalAlignment: Text.AlignHCenter
              text: row.modelData.buttonType === QsMenuButtonType.RadioButton ? Icons.menuRadio : Icons.menuCheck
              color: row.modelData.enabled ? Theme.foreground : Theme.menuForegroundDisabled
              opacity: row.modelData.checkState === Qt.Unchecked ? 0 : row.modelData.checkState === Qt.PartiallyChecked ? 0.5 : 1
              font.family: Theme.fontFamily
              font.pixelSize: row.modelData.buttonType === QsMenuButtonType.RadioButton ? Theme.fontSize - 5 : Theme.fontSize - 2
            }

            IconImage {
              anchors.verticalCenter: parent.verticalCenter
              visible: row.modelData.icon !== ""
              implicitSize: Theme.menuIconSize
              source: row.modelData.icon
              opacity: row.modelData.enabled ? 1 : 0.35
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: row.modelData.text
              color: row.modelData.enabled ? Theme.foreground : Theme.menuForegroundDisabled
              font.family: Theme.fontFamily
              font.pixelSize: Theme.fontSize
            }
          }

          Text {
            id: chevron

            x: column.width - chevron.implicitWidth - Theme.menuItemPaddingH
            anchors.verticalCenter: parent.verticalCenter
            visible: row.modelData.hasChildren
            text: Icons.menuSubmenu
            color: row.modelData.enabled ? Theme.foregroundDim : Theme.menuForegroundDisabled
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 4
          }

          MouseArea {
            id: rowMouse
            width: column.width
            height: row.height
            enabled: !row.separator && row.modelData.enabled
            hoverEnabled: true

            onEntered: column.openIndex = row.modelData.hasChildren ? row.index : -1

            onClicked: {
              if (row.modelData.hasChildren) {
                column.openIndex = row.index;
                return;
              }
              row.modelData.triggered();
              root.rootMenu.shown = false;
            }
          }

          // A submenu hangs off this rather than off the row, so it clears the
          // menu's padding and border instead of overlapping them. Stretching it
          // up by the same padding lines the submenu's first entry up with the
          // row that opened it.
          Item {
            id: submenuAnchor
            x: -Theme.menuPadding
            y: -Theme.menuPadding
            width: column.width + Theme.menuPadding * 2
            height: row.height + Theme.menuPadding * 2
          }

          Loader {
            id: submenu
            active: row.modelData.hasChildren

            // A QML file cannot name itself, so the recursion goes through the
            // file URL instead of the type.
            source: "TrayMenu.qml"

            onLoaded: {
              submenu.item.anchorItem = submenuAnchor;
              submenu.item.menuHandle = row.modelData;
              submenu.item.rootMenu = root.rootMenu;
            }

            Binding {
              target: submenu.item
              property: "shown"
              value: root.visible && column.openIndex === row.index
              when: submenu.item !== null
            }

            // The compositor can dismiss a submenu on its own — clicking back on
            // this menu, for one — so the open index has to follow it, otherwise
            // the binding above would immediately reopen it.
            Connections {
              target: submenu.item

              function onClosed() {
                if (column.openIndex === row.index)
                  column.openIndex = -1;
              }
            }
          }
        }
      }
    }
  }
}

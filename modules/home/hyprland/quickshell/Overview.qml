import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// SUPER+Tab workspace overview. Per-monitor: every screen shows its own
// workspaces and nothing else. Unlike the Alt+Tab switcher this is a toggle
// rather than a hold, because rearranging windows needs sustained pointer
// interaction — which also means it needs a real input region and real keyboard
// focus, and none of the switcher's submap machinery.
// See .copilot/plans/workspace-overview.md.
Scope {
  id: root

  property bool active: false

  // The monitor that had focus when the overview opened. Only its overlay takes
  // the keyboard; the rest are pointer-only.
  property string primaryScreenName: ""

  function toggle() {
    if (root.active)
      root.close();
    else
      root.open();
  }

  function open() {
    // Hyprland announces nothing when a workspace reflows in place, so the
    // geometry every card is positioned from is stale until this lands.
    Hyprland.refreshToplevels();

    root.primaryScreenName = Hyprland.focusedMonitor?.name ?? "";
    root.active = true;
  }

  function close() {
    root.active = false;
  }

  function focusWindow(address) {
    if (!address)
      return;

    Hyprland.dispatch(`focuswindow address:0x${address}`);
    root.close();
  }

  function activateWorkspace(workspace) {
    if (!workspace)
      return;

    workspace.activate();
    root.close();
  }

  function moveWindow(address, workspaceId) {
    if (!address)
      return;

    // Silent: rearranging windows should not drag the view along behind them.
    Hyprland.dispatch(`movetoworkspacesilent ${workspaceId},address:0x${address}`);

    // A move re-anchors the tape on both the source and destination workspace —
    // every other window's absolute coordinates change even though their order
    // does not — so nothing on screen is trustworthy until this lands.
    Hyprland.refreshToplevels();
  }

  function moveWindowToNewWorkspace(address, monitor) {
    const id = WindowList.firstFreeWorkspaceId();
    if (!address || !monitor || id < 0)
      return;

    Hyprland.dispatch(`movetoworkspacesilent ${id},address:0x${address}`);

    // A workspace conjured up by a move lands on the *focused* monitor, not the
    // moved window's. Without this the new workspace would belong to whichever
    // monitor happened to have focus and vanish from the overview it was
    // created in.
    Hyprland.dispatch(`moveworkspacetomonitor ${id} ${monitor.name}`);
    Hyprland.refreshToplevels();
  }

  function createWorkspace(monitor) {
    const id = WindowList.firstFreeWorkspaceId();
    if (!monitor || id < 0)
      return;

    // `workspace` acts on the focused monitor, so aim the focus first rather
    // than assuming the overview being clicked is the focused one.
    Hyprland.dispatch(`focusmonitor ${monitor.name}`);
    Hyprland.dispatch(`workspace ${id}`);
    root.close();
  }

  GlobalShortcut {
    appid: "quickshell"
    name: "overviewToggle"
    description: "Toggle the workspace overview"
    onPressed: root.toggle()
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: overlay

      required property var modelData

      readonly property var monitor: Hyprland.monitorFor(overlay.modelData)
      readonly property var workspaces: WindowList.forMonitorWorkspaces(overlay.monitor)
      readonly property bool primary: overlay.modelData.name === root.primaryScreenName

      // Derived from the screen rather than from the laid-out content, which
      // would be circular: row heights come from the scale.
      readonly property real innerWidth: overlay.width - (Theme.overviewMargin + Theme.overviewPadding) * 2
      readonly property real innerHeight: overlay.height - (Theme.overviewMargin + Theme.overviewPadding) * 2

      // One scale for every row on this monitor, chosen so the most demanding
      // workspace fits. Per-row scaling would make a workspace holding a single
      // window draw it larger than a workspace holding five, which would read as
      // a size difference that is not there.
      readonly property real mapScale: {
        const list = overlay.workspaces;
        if (list.length === 0)
          return 1;

        const availableWidth = Math.max(1, overlay.innerWidth - Theme.overviewRowLabelWidth - Theme.overviewRowPadding);
        const spacing = Theme.overviewRowSpacing * list.length;
        const perRow = (overlay.innerHeight - Theme.overviewPlusCardHeight - spacing) / list.length;
        const availableHeight = Math.max(1, perRow - Theme.overviewRowPadding * 2);

        // Seeded at 1 so the map is never drawn larger than life. Rows shrink on
        // their own as workspaces are added — each gets a smaller share of the
        // height — so no other cap is needed, and an absolute one only wastes
        // the room a portrait monitor has going spare.
        let scale = 1;
        for (const workspace of list) {
          const bounds = WindowList.boundsForWorkspace(workspace);
          if (!bounds)
            continue;

          scale = Math.min(scale, availableWidth / bounds.width, availableHeight / bounds.height);
        }

        return scale > 0 ? scale : 1;
      }

      visible: root.active
      screen: overlay.modelData
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore

      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }

      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "quickshell-overview"

      // Two layer surfaces cannot meaningfully share a keyboard, so only the
      // monitor that was focused when this opened asks for it. The other still
      // takes pointer input, so its windows remain clickable.
      WlrLayershell.keyboardFocus: overlay.primary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

      Item {
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: root.close()

        // Clicking off the panel dismisses. Declared before the panel so the
        // panel sits above it and keeps its own clicks.
        MouseArea {
          anchors.fill: parent
          onClicked: root.close()
        }

        Rectangle {
          id: panel

          anchors.fill: parent
          anchors.margins: Theme.overviewMargin

          radius: Theme.overviewRowRadius + 8
          color: Theme.overviewBackground
          border.width: 1
          border.color: Theme.overviewBorder

          // Swallows clicks on the panel's own background so they do not fall
          // through to the dismiss handler underneath.
          MouseArea {
            anchors.fill: parent
          }

          Column {
            id: content

            anchors.fill: parent
            anchors.margins: Theme.overviewPadding
            spacing: Theme.overviewRowSpacing

            Repeater {
              model: overlay.workspaces

              OverviewWorkspaceRow {
                required property var modelData

                width: content.width
                workspace: modelData
                mapScale: overlay.mapScale
                capturing: root.active

                onWindowActivated: address => root.focusWindow(address)
                onPageActivated: address => root.focusWindow(address)
                onWorkspaceActivated: root.activateWorkspace(modelData)
                onWindowDropped: address => root.moveWindow(address, modelData.id)
              }
            }

            // An empty workspace, drawn the way the rows above draw a window:
            // one blank card. Clicking it creates the workspace; dropping a
            // window on it creates the workspace around that window.
            Item {
              width: content.width
              height: Theme.overviewPlusCardHeight

              Rectangle {
                x: Theme.overviewRowLabelWidth
                width: Theme.overviewPlusCardWidth
                height: parent.height

                radius: Theme.overviewCardRadius
                color: {
                  if (plusDrop.containsDrag)
                    return Theme.overviewRowDropTarget;
                  return plusArea.containsMouse ? Theme.overviewCardHover : Theme.overviewCardBackground;
                }
                border.width: 1
                border.color: Theme.overviewCardBorder

                Text {
                  anchors.centerIn: parent
                  text: "+"
                  color: Theme.foregroundDim
                  font.family: Theme.fontFamily
                  font.pixelSize: Math.round(parent.height * 0.4)
                }

                MouseArea {
                  id: plusArea

                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: root.createWorkspace(overlay.monitor)
                }

                DropArea {
                  id: plusDrop

                  anchors.fill: parent
                  keys: ["overview-window"]

                  onDropped: drop => root.moveWindowToNewWorkspace(drop.source.address, overlay.monitor)
                }
              }
            }
          }
        }
      }
    }
  }
}

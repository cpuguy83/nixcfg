import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// Alt+Tab switcher. Cards carry identity only; the selected window itself is
// scrolled into view behind the overlay, which is the only way to see windows
// the scrolling layout has pushed off the viewport — those deliver no frames to
// any capture protocol. See .copilot/plans/window-switcher.md.
Scope {
  id: root

  property bool active: false
  property var windows: []
  property int index: 0

  // The window to fall back to when the switcher is cancelled. Hyprland's own
  // focus history is no use: every step pollutes it.
  property string restoreAddress: ""
  property string screenName: ""

  function open(direction) {
    // Ordering comes from window geometry, which Hyprland does not announce
    // when a workspace reflows in place.
    Hyprland.refreshToplevels();

    const list = WindowList.forMonitor(Hyprland.focusedMonitor);
    if (list.length < 2) {
      root.close();
      return;
    }

    const current = WindowList.activeIndex(list);

    root.windows = list;
    root.screenName = Hyprland.focusedMonitor?.name ?? "";
    root.restoreAddress = current < 0 ? "" : list[current].address;
    root.index = Math.max(0, current);
    root.active = true;

    root.step(direction);
  }

  function step(direction) {
    if (!root.active) {
      root.open(direction);
      return;
    }

    const count = root.windows.length;
    root.index = ((root.index + direction) % count + count) % count;
    root.focusSelected();
  }

  function focusSelected() {
    const toplevel = root.windows[root.index];
    if (!toplevel)
      return;

    // `focuswindow` warps the cursor, which rules it out for a pointer-driven
    // peek but is right here: the pointer is not the input device, and this is
    // what Hyprland already does for every keyboard focus change. It also
    // targets an exact window, where `layoutmsg move` only scrolls the tape
    // horizontally and lands on whichever column reaches the centre.
    //
    // The config is native Lua (configType = "lua"), so `Hyprland.dispatch()`
    // -- which sends this string as the IPC `dispatch` request's argument --
    // must be a Lua expression evaluating to a dispatcher, not a legacy
    // hyprlang dispatcher string.
    Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${toplevel.address}" })`);
  }

  function commit() {
    // The Alt release that triggers this is bound submap-universally, because
    // Hyprland resolves a release against the submap that was active when the
    // key went down — and Alt goes down before the switcher's submap is
    // entered. That means this runs on every Alt release on the desktop, so
    // the `active` check is load-bearing, not defensive tidiness.
    if (!root.active)
      return;

    // Stepping already focused the selection, so committing is just teardown.
    root.close();
  }

  function cancel() {
    if (!root.active)
      return;

    const restore = root.restoreAddress;
    root.close();

    if (restore)
      Hyprland.dispatch(`hl.dsp.focus({ window = "address:0x${restore}" })`);
  }

  function close() {
    root.active = false;
    root.windows = [];
    root.restoreAddress = "";

    // The Alt-release bind deliberately does not reset the submap — being
    // submap-universal, it would fire on every Alt release and could kick the
    // keyboard out of an unrelated submap. Resetting here instead scopes it to
    // the case where the switcher was actually open.
    Hyprland.dispatch(`hl.dsp.submap("reset")`);
  }

  GlobalShortcut {
    appid: "quickshell"
    name: "switcherNext"
    description: "Select the next window"
    onPressed: root.step(1)
  }

  GlobalShortcut {
    appid: "quickshell"
    name: "switcherPrev"
    description: "Select the previous window"
    onPressed: root.step(-1)
  }

  GlobalShortcut {
    appid: "quickshell"
    name: "switcherAccept"
    description: "Switch to the selected window"

    // Bound with `bindru`, so Hyprland dispatches this on key release, which
    // reaches the protocol as `released` rather than `pressed`.
    onReleased: root.commit()
  }

  GlobalShortcut {
    appid: "quickshell"
    name: "switcherCancel"
    description: "Dismiss the switcher"
    onPressed: root.cancel()
  }

  PanelWindow {
    id: overlay

    visible: root.active
    screen: Quickshell.screens.find(screen => screen.name === root.screenName) ?? null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-switcher"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // The overlay covers the screen so the carousel can float over it, but it
    // is driven entirely from the keyboard. An empty input region keeps it from
    // swallowing clicks meant for the window showing through.
    mask: Region {}

    Rectangle {
      id: strip

      anchors.horizontalCenter: parent.horizontalCenter
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Theme.switcherBottomMargin

      width: Math.min(cards.width + Theme.switcherPadding * 2, overlay.width - Theme.switcherMargin * 2)
      height: cards.height + Theme.switcherPadding * 2

      radius: Theme.switcherRadius
      color: Theme.switcherBackground
      border.width: 1
      border.color: Theme.switcherBorder

      Item {
        id: viewport

        anchors.fill: parent
        anchors.margins: Theme.switcherPadding
        clip: true

        Row {
          id: cards

          spacing: Theme.switcherSpacing

          // Keeps the selection centred once there are more cards than fit,
          // clamped so the ends of the strip do not pull away from the edges.
          x: {
            if (cards.width <= viewport.width)
              return (viewport.width - cards.width) / 2;

            const stride = Theme.switcherCardWidth + Theme.switcherSpacing;
            const selectedCentre = root.index * stride + Theme.switcherCardWidth / 2;
            return Math.max(viewport.width - cards.width, Math.min(0, viewport.width / 2 - selectedCentre));
          }

          Behavior on x {
            NumberAnimation {
              duration: 140
              easing.type: Easing.OutCubic
            }
          }

          Repeater {
            model: root.windows

            SwitcherCard {
              required property var modelData
              required property int index

              hyprToplevel: modelData
              selected: index === root.index
            }
          }
        }
      }
    }
  }
}

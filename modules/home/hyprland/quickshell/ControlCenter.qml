pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// The macOS-Control-Center-style panel (.copilot/plans/control-center.md §9).
// Stage 1 is the empty shell: the overlay, its dismissal, and the anchoring
// math are validated here in isolation, before any section exists to fill it.
//
// This is `pragma Singleton` rather than a plain Scope (contrast
// Overview.qml/Switcher.qml) because the bar button calls
// `ControlCenter.toggle(buttonItem, screenName)` directly — the alternative,
// threading a reference through Variants -> Bar.qml -> button, is three files
// of plumbing to avoid one singleton. A singleton can legally own a
// PanelWindow: Quickshell.Singleton has the same `children` default property
// as ShellRoot (§9.0).
Singleton {
  id: root

  // Whether the overlay is shown at all. Named `open` rather than `active`
  // (as Overview.qml/Switcher.qml do) because every consumer reads
  // `ControlCenter.open` directly — the cost is that a same-named `open()`
  // method is not available (QML does not allow a property and a method to
  // share a name on one object), so `toggle()` below sets this property
  // directly instead of delegating to one.
  property bool open: false

  // The screen the panel is anchored to, snapshotted by toggle().
  property string screenName: ""

  // x, in overlay-local coordinates, that the panel's *right* edge should
  // line up with. A snapshot taken in toggle(), not a binding: the bar layout
  // shifts as tray icons come and go, and a panel that slides sideways under
  // you while you are reading it is worse than one anchored where you
  // clicked (§9.3).
  property real anchorRight: 0

  // Which accordion member (VPN/Bluetooth/Network, stages 3-5) is expanded.
  // Deliberately persists across close()/open() — see §9.7 — so nothing here
  // ever resets it.
  property string expandedSection: ""

  // Audio is not an accordion member: it is the section you glance at most,
  // so opening VPN or Bluetooth must not collapse it. Open by default,
  // collapsible, and persists across opens like `expandedSection`.
  property bool audioExpanded: true

  // Groups *within* the Audio section. All default closed: they are settings
  // you change occasionally, not state you glance at, and leaving them open
  // was what made the panel tall enough to need scrolling in the first place.
  // Held here rather than in the section because sections are instantiated
  // once per output (I2) and two copies must not disagree.
  property bool samplingExpanded: false
  property bool monitoringExpanded: false
  property bool effectsExpanded: false

  // The gateway region VpnSection's toggle connects to when switched on
  // (§9.6, revised: the gateway rows are a pure selector, never a click that
  // connects). Held here rather than in VpnSection for the same reason as
  // the Audio groups above: sections are instantiated once per output (I2's
  // corollary), and two copies must not disagree about which region is
  // selected. Empty until the first `VpnState.gateways` poll lands (§2.3:
  // singletons populate asynchronously) - see the seeding Connections below.
  property string vpnRegion: ""

  // The single inline picker (stage 5+) allowed open at a time (I7). Empty
  // string means none is open. Also doubles as the first Escape-unwind level
  // below, ahead of the panel itself.
  property string openPicker: ""

  // Each screen's own `ControlCenterButton`, keyed by screen name — populated
  // by the button itself (see that file's `Component.onCompleted`). The click
  // path never needs this; it always has the clicked item in hand. It exists
  // for `toggleGlobal()` below, which is invoked from a keybind with no click
  // event to anchor from, so it borrows whichever button already sits on the
  // focused screen's bar rather than inventing a second anchoring scheme.
  property var buttons: ({})

  // Timestamp of the last close caused specifically by HyprlandFocusGrab
  // clearing — not every close — and the window during which a reopen is
  // ignored. Narrowed to that one source deliberately: only a grab-clear can
  // race the button's own click (below), so a deliberate close-then-reopen
  // (Escape, then the button; or the global shortcut fired twice) must never
  // be swallowed by this guard.
  property real lastGrabClearTime: 0
  readonly property int reopenGuardMs: 250

  function registerButton(screenName, item) {
    root.buttons[screenName] = item;
  }

  function unregisterButton(screenName) {
    delete root.buttons[screenName];
  }

  // If the screen this panel is anchored to gets hot-unplugged while the
  // panel is open, that screen's own `Variants` instance (below) is torn
  // down with it — `open` stays true, `screenName` names a screen that no
  // longer exists, no overlay anywhere is the anchor, and nothing left on
  // screen could ever close it. Meanwhile NetworkState's `scannerEnabled`
  // and BluetoothState's `discoveryRequested`-gated `discovering` stay live
  // off that stale `open` (I2). Watching `Quickshell.screens` and closing
  // whenever the anchor screen disappears closes that hole.
  Connections {
    target: Quickshell
    function onScreensChanged() {
      if (root.open && !Quickshell.screens.some(screen => screen.name === root.screenName))
        root.close();
    }
  }

  // Keeps `vpnRegion` truthful with no action from VpnSection at all (§9.6,
  // revised). Two independent jobs share one Connections block because they
  // both react to VpnState and both only ever write vpnRegion:
  //   - onGatewaysChanged seeds it once, from whichever gateway the
  //     descriptor marks `default: true`, the moment `gateways` is first
  //     non-empty (it starts `[]` - singletons populate asynchronously,
  //     §2.3 - so this can't be a component-completion assignment).
  //   - onRegionChanged tracks the live region whenever the daemon reports
  //     one (connected or connecting), so a connect issued from outside the
  //     panel (a terminal, the waybar rollback) is reflected here too, and
  //     so toggling off then back on reconnects to wherever you actually
  //     were rather than silently reverting to the configured default.
  // Whichever fires first on a given poll wins for that poll: if already
  // connected the moment the first gateway list lands, `region` is set in
  // the same JS pass as `gateways`, so onRegionChanged's write happens first
  // and the seed guard below (`vpnRegion === ""`) then correctly skips.
  Connections {
    target: VpnState
    function onGatewaysChanged() {
      if (root.vpnRegion === "") {
        const def = VpnState.gateways.find(g => g.default);
        if (def)
          root.vpnRegion = def.region;
      }
    }
    function onRegionChanged() {
      if (VpnState.region)
        root.vpnRegion = VpnState.region;
    }
  }

  // Called by the bar button. A re-invocation while already open is a real,
  // common path now that the input mask (below) leaves the button clickable
  // while the panel is open: this closes it, exactly like any other toggle —
  // the reopen guard a few lines down is what stops that same click's
  // focus-grab side effect from immediately reopening it again.
  //
  // `anchorItem` is nullable: the click path always passes the clicked
  // button, but `toggleGlobal()` below may have no registered button to pass
  // for the focused screen, in which case this anchors to that screen's own
  // top-right corner instead (§9.8/§12 stage 7) rather than special-casing
  // the keyboard path with a second positioning scheme.
  function toggle(anchorItem, screenName) {
    if (root.open) {
      root.close();
      return;
    }

    // Clicking the bar button while the panel is open now does two things at
    // once, because the button is reachable again (the input mask no longer
    // covers it): the compositor clears the focus grab, which closes the
    // panel, and the button receives the click, which would toggle it
    // straight back open. Whichever lands first, this suppresses the second
    // so the button reads as a plain toggle rather than flickering closed and
    // open again. `lastGrabClearTime` is stamped only by that grab-clear (see
    // `HyprlandFocusGrab.onCleared` below) and never by close() itself, so a
    // deliberate close-then-reopen — Escape then the button, or the global
    // shortcut fired twice — is never mistaken for this race and blocked.
    if (Date.now() - root.lastGrabClearTime < root.reopenGuardMs)
      return;

    root.anchorRight = anchorItem ? anchorItem.mapToItem(null, anchorItem.width, 0).x : root.fallbackAnchorRight(screenName);
    root.screenName = screenName;
    root.open = true;
  }

  // Top-right corner of the named screen: an `anchorRight` of exactly the
  // screen's width lands the panel flush against that corner once toggle()'s
  // clamp math (see the Rectangle below) runs the same way it does for any
  // on-screen click — no separate fallback formula to keep in sync.
  function fallbackAnchorRight(screenName) {
    const screen = Quickshell.screens.find(candidate => candidate.name === screenName);
    return screen ? screen.width : 0;
  }

  // Entry point for the global shortcut (§12 stage 7), which — unlike a bar
  // click — has no item and no particular screen to hand in. Hyprland's own
  // focused monitor stands in for "the screen the click would have been on";
  // falling back to the first known screen keeps this from anchoring nowhere
  // in the one case `Hyprland.focusedMonitor` is unset.
  function toggleGlobal() {
    const screenName = Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name ?? "";
    root.toggle(root.buttons[screenName] ?? null, screenName);
  }

  function close() {
    root.open = false;
    // A picker left open (stage 5+) should not reappear on the next open;
    // expandedSection is the one piece of state that is meant to (§9.7).
    root.openPicker = "";
  }

  // Escape unwinds one level at a time, most-local first: a focused,
  // non-empty passphrase field (NetworkSection's inline WiFi PSK entry,
  // stage 5) drops focus but keeps its text; then any open inline picker
  // collapses; only then does the panel itself close.
  //
  // Not named `escape`: QML rejects that at load time with "Illegal method
  // name" because it shadows the JavaScript global of the same name, and the
  // failure only appears when the shell actually loads — never at build time.
  function dismiss(focusItem) {
    if (root.passphraseFocused(focusItem)) {
      // Reclaim focus explicitly rather than trusting it to fall back here
      // on its own — releasing a nested item's focus does not automatically
      // hand it to this ambient item, confirmed against the real compositor
      // while building this stage, so nothing here can rely on that
      // happening for free.
      focusItem.forceActiveFocus();
      return;
    }

    if (root.openPicker !== "") {
      root.openPicker = "";
      return;
    }

    root.close();
  }

  // True while an open passphrase field still holds real keyboard focus and
  // has unsaved text. `pendingPassphrase` alone is not enough to tell that:
  // it stays non-empty across a deliberate release (I9 only clears it on a
  // row collapsing or the panel closing), so this also has to distinguish
  // "still focused" from "already released, nothing left to release" —
  // `focusItem` only regains real activeFocus once something upstream (this
  // function, or the outside-click handler below) has explicitly reclaimed
  // it. `focusItem` is per-screen local state, never a shared singleton
  // property, so reading it here carries none of `scannerEnabled`'s Binding
  // sharing risk (§10 I2).
  function passphraseFocused(focusItem) {
    return NetworkState.pendingPassphrase !== "" && !focusItem.activeFocus;
  }

  // Only reachable now because stage 1 chose a fullscreen `PanelWindow`
  // rather than a grabbing `PopupWindow` (§9.1) — a grabbing popup can only
  // be opened from a click on the bar. The matching Hyprland `bind` lives in
  // `modules/home/hyprland/settings.nix`.
  GlobalShortcut {
    appid: "quickshell"
    name: "controlCenterToggle"
    description: "Toggle the Control Center panel"
    onPressed: root.toggleGlobal()
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: overlay

      required property var modelData
      readonly property bool isAnchorScreen: overlay.modelData.name === root.screenName

      screen: overlay.modelData
      // Stays mapped through the close animation, or the surface would be
      // destroyed the instant `open` goes false and the panel would vanish
      // rather than shrink back toward the button.
      visible: root.open || panel.opacity > 0
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore

      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }

      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.namespace: "quickshell-control-center"

      // The input region is the panel itself, not the whole output.
      //
      // This surface has to span the output so the panel can be positioned
      // anywhere on it, but accepting input across all of that meant every
      // click outside the panel was swallowed to dismiss it: the window
      // underneath never received the click (so dismissing cost two clicks),
      // and the bar button underneath could not be clicked to toggle the
      // panel closed at all. Masking input to the panel lets all of those
      // clicks through; `HyprlandFocusGrab` below is what tells us the user
      // clicked away, without us having to eat the click to find out.
      //
      // A default-constructed Region is empty, which is what the non-anchor
      // screens want — they draw nothing and must stay fully click-through
      // (same idiom as Switcher.qml).
      mask: Region {
        item: overlay.isAnchorScreen ? panel : null
      }

      // OnDemand rather than Exclusive: paired with the focus grab below this
      // was measured to take real keyboard focus immediately, with no prior
      // click, while leaving the compositor free to hand focus back the
      // instant the grab clears. Exclusive would keep the keyboard captive
      // for as long as the panel is open, which is wrong for a surface that
      // now deliberately lets clicks through to whatever is behind it.
      WlrLayershell.keyboardFocus: overlay.isAnchorScreen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

      // Dismissal. The compositor tells us the pointer went elsewhere instead
      // of us intercepting it, so the click that dismisses the panel also
      // reaches whatever the user actually meant to click.
      HyprlandFocusGrab {
        windows: [overlay]
        active: root.open && overlay.isAnchorScreen

        // Stamped here, not inside close() itself, so the reopen guard in
        // toggle() narrows to exactly the race it exists for — this grab
        // clearing and the bar button's own click firing from the same
        // physical click — and never suppresses a deliberate close from
        // Escape or the button's own toggle-closed branch.
        onCleared: {
          root.lastGrabClearTime = Date.now();
          root.close();
        }
      }

      Item {
        id: focusItem
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: root.dismiss(focusItem)

        // No fullscreen dismiss MouseArea any more: the input mask above
        // stops this surface receiving anything outside the panel at all, so
        // such an area could never fire, and `HyprlandFocusGrab` handles
        // click-away instead.
        //
        // The two-step passphrase dismissal that used to live here goes with
        // it — we no longer see the outside click, so we cannot choose to
        // absorb the first one. `pendingPassphrase` is cleared on close (I9),
        // so a stray click costs a retype rather than leaking a credential,
        // which is the safer side of that trade anyway.

        Rectangle {
          id: panel

          // Only the anchor screen draws the panel; every other output's
          // overlay mask is empty (see the mask above), so it captures no
          // input at all and stays fully click-through. It exists only to
          // hold WlrKeyboardFocus.None so that screen's own apps keep real
          // keyboard focus while the panel is open on another screen.
          visible: overlay.isAnchorScreen

          // Grow out of the corner the panel is attached to, so it reads as
          // coming from the bar button rather than from the screen. The
          // compositor cannot do this for us: the layer surface is the whole
          // output, so a Hyprland layer animation animates the entire screen
          // (see the `animation none` layerrule in settings.nix). Scaling the
          // Rectangle is free — the surface never resizes.
          transformOrigin: Theme.barAtBottom ? Item.BottomRight : Item.TopRight
          opacity: root.open ? 1 : 0
          scale: root.open ? 1 : 0.92

          Behavior on opacity {
            NumberAnimation {
              duration: Theme.controlCenterAnimDuration
              easing.type: Easing.OutCubic
            }
          }

          Behavior on scale {
            NumberAnimation {
              duration: Theme.controlCenterAnimDuration
              easing.type: Easing.OutCubic
            }
          }

          width: Theme.controlCenterWidth
          height: Math.min(content.implicitHeight + Theme.controlCenterPadding * 2, overlay.height - Theme.barHeight - Theme.controlCenterMargin * 2, Theme.controlCenterMaxHeight)

          // Clamped between the screen margins so a click near either edge
          // never pushes the panel off-screen; otherwise anchored so its
          // right edge lines up with wherever the button was clicked (§9.3).
          x: Math.max(Theme.controlCenterMargin, Math.min(root.anchorRight - panel.width, overlay.width - panel.width - Theme.controlCenterMargin))
          y: Theme.barAtBottom ? overlay.height - Theme.barHeight - panel.height - Theme.controlCenterMargin : Theme.barHeight + Theme.controlCenterMargin

          radius: Theme.controlCenterRadius
          color: Theme.controlCenterBackground
          border.width: 1
          border.color: Theme.controlCenterBorder

          // Absorbs presses on the panel's own chrome — the padding ring
          // around the Flickable below, where nothing else claims the event
          // — so they are inert rather than left unhandled. There is no
          // fullscreen dismiss area left underneath to protect against (the
          // input mask above already keeps every other click off this
          // surface entirely); this just keeps a click on the panel's own
          // background from doing anything at all.
          MouseArea {
            anchors.fill: parent
          }

          Flickable {
            id: flick

            anchors.fill: parent
            anchors.margins: Theme.controlCenterPadding
            clip: true

            contentWidth: flick.width
            contentHeight: content.implicitHeight

            // Sliders (stage 2+) are horizontal drags, so restricting the
            // flick direction to vertical leaves them alone entirely;
            // `preventStealing` on the slider's own MouseArea is what covers
            // the diagonal-drag case this does not (§9.9).
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            interactive: flick.contentHeight > flick.height

            Column {
              id: content

              width: flick.width
              spacing: Theme.controlCenterSpacing

              // Audio is pinned open and always first (§9.5/§9.9). VPN and
              // Bluetooth follow as an accordion below; Network joins in a
              // later stage.
              AudioSection {
                width: content.width
              }

              // Accordion members (§9.7, stages 3-4). Network (stage 5) joins
              // them below, each keying its own `expanded` off
              // `ControlCenter.expandedSection` the same way. This `content`
              // column is instantiated once per screen (it lives inside the
              // per-screen `Variants` above), even though only the anchor
              // screen's copy is ever visible - but neither section holds any
              // state the extra copies could race over: VpnState and
              // BluetoothState (§10 I2) are singletons, constructed exactly
              // once regardless of screen count, and these sections are pure
              // views over them.
              VpnSection {
                width: content.width
              }

              BluetoothSection {
                width: content.width
              }

              // Highest-risk member (§9.7/§9.9): scanner latch, passphrase
              // focus, SSID dedup. `focusFallback` threads this screen's own
              // `focusItem` down to whatever inline passphrase field is open,
              // so it has something concrete to reclaim focus onto when it
              // gives up its own (see ControlCenterField's doc for why that
              // cannot happen implicitly).
              NetworkSection {
                width: content.width
                focusFallback: focusItem
              }
            }
          }

          // Hand-rolled: Quickshell.Widgets ships no scrollbar, and
          // QtQuick.Controls would be the first import of it anywhere in
          // this directory (§9.9).
          Item {
            id: scrollTrack

            visible: flick.contentHeight > flick.height

            anchors {
              top: flick.top
              bottom: flick.bottom
              right: parent.right
              rightMargin: 2
            }
            width: Theme.scrollBarWidth

            Rectangle {
              width: parent.width
              radius: Theme.scrollBarRadius
              color: Theme.foregroundDim

              y: flick.visibleArea.yPosition * scrollTrack.height
              height: flick.visibleArea.heightRatio * scrollTrack.height

              opacity: flick.moving ? 0.8 : 0

              Behavior on opacity {
                NumberAnimation {
                  duration: 250
                }
              }
            }
          }
        }
      }
    }
  }
}

pragma Singleton

import QtQuick
import Quickshell

Singleton {
  // Bar placement. At the top the bar reserves space and window previews drop
  // downward; flip to true to move it to the bottom (previews then rise).
  readonly property bool barAtBottom: false

  readonly property int barHeight: 34
  // Concave cut-ins at the bar's two desktop-facing corners, drawn as the
  // inverse of the curve Hyprland rounds a window with.
  //
  // The exponent must track `decoration.rounding_power` in settings.nix: it is
  // what makes the cut-in the same *kind* of curve as a window corner, and the
  // two only read as a matched pair while they agree.
  //
  // The radius deliberately does not track `decoration.rounding` (16). At a
  // power of 4 the superellipse hugs the corner, so its inverse is a crescent
  // covering only ~7% of a radius-by-radius box — at 16 that is 2.5px at its
  // thickest, which against a dark wallpaper is a ~6/255 difference and simply
  // is not visible. Scaling the radius up stretches the same curve into
  // something the eye can actually pick up.
  readonly property int barCornerRadius: 32
  readonly property real barCornerPower: 4
  readonly property int spacing: 3
  readonly property int radius: 8
  readonly property int iconSize: 20

  // Horizontal breathing room inside a text pill, and the gap that keeps its
  // hover highlight from touching the bar edges.
  readonly property int pillPadding: 6
  readonly property int pillMargin: 3
  readonly property int tooltipPadding: 8
  readonly property int traySpacing: 2

  // Percentage points per scroll notch on the audio modules.
  readonly property int volumeStep: 5

  readonly property string fontFamily: "AdwaitaMono Nerd Font"
  readonly property int fontSize: 14

  // rgba(0, 0, 0, 0.5), matching the Waybar background. Hyprland blurs behind
  // it via the `quickshell-bar` layerrule.
  readonly property color barBackground: "#80000000"
  readonly property color foreground: "#fefefe"
  readonly property color foregroundDim: "#a0fefefe"

  readonly property color itemHover: "#14ffffff"
  readonly property color itemActive: "#26ffffff"

  // Tray menus, carried over from the `#tray menu` rules in waybar.css. The
  // translucent background is only frosted because Hyprland blurs popups of the
  // `quickshell-bar` layer; see the `blur_popups` layerrule.
  readonly property int menuRadius: 16
  readonly property int menuPadding: 8
  readonly property int menuItemRadius: 10
  readonly property int menuItemPaddingH: 12
  readonly property int menuItemPaddingV: 8
  readonly property int menuItemMinHeight: 24
  readonly property int menuItemSpacing: 4
  readonly property int menuSeparatorMargin: 12
  readonly property int menuIconSize: 16
  readonly property color menuBackground: "#8c16161a"
  readonly property color menuBorder: "#14ffffff"
  readonly property color menuItemHover: "#14ffffff"
  readonly property color menuForegroundDisabled: "#59fefefe"

  // Window preview popup.
  readonly property int previewWidth: 320
  readonly property int previewHeight: 180
  readonly property int previewPadding: 8
  readonly property int previewFallbackIconSize: 64
  readonly property color previewBackground: "#8c16161a"
  readonly property color previewBorder: "#14ffffff"

  // Alt+Tab switcher. The strip sits low on the screen so it does not cover the
  // window it is scrolling into view behind itself.
  readonly property int switcherCardWidth: 140
  readonly property int switcherCardHeight: 116
  readonly property int switcherCardRadius: 12
  readonly property int switcherCardPadding: 10
  readonly property int switcherCardSpacing: 8
  readonly property int switcherIconSize: 48
  readonly property int switcherPadding: 12
  readonly property int switcherSpacing: 8
  readonly property int switcherRadius: 20
  readonly property int switcherMargin: 64
  readonly property int switcherBottomMargin: 120
  // Frosted via the `quickshell-switcher` blur layerrule, so this has to stay
  // translucent enough for the blur to read through — see docs/frosted-glass.md.
  // It also has to stay above the rule's 0.3 ignore_alpha threshold, or the
  // strip would be skipped along with the transparent overlay around it.
  readonly property color switcherBackground: "#8c16161a"
  readonly property color switcherBorder: "#14ffffff"
  readonly property color switcherCardSelected: "#26ffffff"
  readonly property color switcherCardSelectedBorder: "#33ffffff"

  // SUPER+Tab workspace overview. Rows are workspaces; within a row, cards sit
  // at their true scaled coordinates with the monitor viewport drawn as a frame,
  // so windows the scrolling layout has pushed off the tape read as parked
  // outside it. Frosted via the `quickshell-overview` layerrule, so the same
  // translucency constraints as the switcher apply — see docs/frosted-glass.md.
  readonly property int overviewMargin: 64
  readonly property int overviewPadding: 20
  readonly property int overviewRowSpacing: 16
  readonly property int overviewRowRadius: 16
  readonly property int overviewRowPadding: 12
  readonly property int overviewRowLabelWidth: 116
  // The "new workspace" affordance is drawn as a single blank window card rather
  // than a full-width bar, so it reads as an empty workspace waiting for a
  // window instead of a giant button.
  readonly property int overviewPlusCardWidth: 168
  readonly property int overviewPlusCardHeight: 112
  readonly property int overviewCardRadius: 8
  readonly property int overviewCardMinIcon: 16
  readonly property int overviewCardMaxIcon: 64
  // Below these the card has no room for a title and shows only its icon.
  readonly property int overviewCardTitleMinWidth: 96
  readonly property int overviewCardTitleMinHeight: 56

  readonly property color overviewBackground: "#8c16161a"
  readonly property color overviewBorder: "#14ffffff"
  readonly property color overviewRowBackground: "#14ffffff"
  readonly property color overviewRowBackgroundActive: "#26ffffff"
  readonly property color overviewRowBorder: "transparent"
  readonly property color overviewRowBorderActive: "#40ffffff"
  readonly property color overviewRowDropTarget: "#3344dd88"
  // The monitor viewport outline. Deliberately dashed-looking via low contrast
  // rather than a solid box, so it reads as a frame and not another window.
  // Pages the tape is sliced into. The current one is outlined brightly since it
  // is the only one with live content; the others are jump targets.
  readonly property color overviewViewportBorder: "#59fefefe"
  readonly property color overviewPageBorder: "#26ffffff"
  readonly property color overviewPageHover: "#14ffffff"
  // Cards have to read as solid surfaces sitting on the blurred panel. At low
  // alpha they disappear into whatever the overlay is covering and leave the
  // icon looking like it is floating loose on the desktop.
  readonly property color overviewCardBackground: "#b31e1e24"
  readonly property color overviewCardBorder: "#33ffffff"
  readonly property color overviewCardActive: "#cc26332c"
  readonly property color overviewCardActiveBorder: "#b344dd88"
  readonly property color overviewCardHover: "#cc2c2c36"

  // Control Center (§9.10). A dedicated interactive/"on" hue — distinct from
  // the status colour below — so "this control is on" never reads as an
  // error state (O-1).
  readonly property color accent: "#4d8ff5"
  readonly property color statusError: "#ff4444"

  // Panel frame. Frosted via the `quickshell-control-center` layerrule, so
  // the same translucency floor as the switcher/overview applies — the
  // background must stay above that rule's `ignore_alpha 0.3` threshold, see
  // docs/frosted-glass.md.
  readonly property int controlCenterWidth: 360
  readonly property int controlCenterMaxHeight: 720
  readonly property int controlCenterMargin: 12
  readonly property int controlCenterRadius: 20
  readonly property int controlCenterPadding: 16
  readonly property int controlCenterSpacing: 12
  readonly property color controlCenterBackground: "#8c16161a"
  readonly property color controlCenterBorder: "#14ffffff"

  // Expandable section tiles (Audio pinned open; VPN/Bluetooth/Network as an
  // accordion, §9.7).
  readonly property int sectionRadius: 14
  readonly property int sectionPadding: 12
  readonly property int sectionSpacing: 10
  // Air above a group heading inside a section, separating it from the
  // previous group's controls.
  readonly property int headingSpacing: 10
  readonly property int sectionHeaderHeight: 44
  readonly property color sectionBackground: "#14ffffff"
  readonly property color sectionBackgroundExpanded: "#1effffff"
  // Matches Switcher.qml's carousel timing, so every animated surface in the
  // shell moves at the same rate.
  readonly property int sectionExpandDuration: 140
  // Panel grow-in. Client-side, since the layer surface spans the whole
  // output and cannot be animated usefully by the compositor.
  readonly property int controlCenterAnimDuration: 130

  // Generic row inside a section body (device rows, gateway rows, ...).
  readonly property int rowHeight: 40
  readonly property int rowRadius: 10
  readonly property int rowPaddingH: 10
  readonly property int rowSpacing: 8

  // Volume-style slider: track/fill/handle plus a leading mute glyph.
  readonly property int sliderHeight: 32
  readonly property int sliderTrackHeight: 6
  readonly property int sliderHandleSize: 16
  readonly property color sliderTrack: "#26ffffff"
  readonly property color sliderFill: accent
  // Muted keeps the level and dims the fill instead of zeroing it, so
  // unmuting restores exactly where it was (§9.5).
  readonly property color sliderFillMuted: "#40ffffff"
  readonly property color sliderHandle: "#fefefe"

  // Pill switch (Bluetooth power, WiFi enable, monitor on/off, ...) and the
  // exclusive segmented control (latency tier).
  readonly property int toggleWidth: 40
  readonly property int toggleHeight: 22
  readonly property int toggleKnobMargin: 2
  readonly property color toggleOff: "#40ffffff"
  readonly property int segmentHeight: 28
  readonly property int segmentRadius: 8
  readonly property color segmentSelected: accent

  // WiFi passphrase field.
  readonly property int fieldHeight: 36
  readonly property int fieldRadius: 10
  readonly property color fieldBackground: "#14ffffff"
  readonly property color fieldBorder: "#33ffffff"

  // Hand-rolled Flickable scroll indicator (§9.9) — Quickshell.Widgets ships
  // no scrollbar.
  readonly property int scrollBarWidth: 4
  readonly property int scrollBarRadius: 2
}

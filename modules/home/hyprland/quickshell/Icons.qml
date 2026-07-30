pragma Singleton

import QtQuick
import Quickshell

// Nerd Font glyphs lifted from the Waybar config. They live in the Private Use
// Area, so they are written as escapes rather than literals — invisible
// characters in source are hostile to diffs and easy to corrupt in transit.
Singleton {
  // Media controls (only shown while paused, matching Waybar).
  readonly property string mediaPlaying: "\uf04b"
  readonly property string mediaPaused: "\uf04c"
  readonly property string mediaStopped: "\uf04d"

  // Audio sink, indexed by volume from quietest to loudest.
  readonly property list<string> volumeLevels: ["\uf026", "\uf027", "\uf027", "\uf028", "\uf028 "]
  readonly property string volumeMuted: "\u{f0581}"
  readonly property string headphones: "\uf025"

  // Audio source.
  readonly property string micOn: "\uf130"
  readonly property string micMuted: "\uf131"

  readonly property string password: "\u{f1575}"

  readonly property string bluetoothOn: "\u{f00af}"
  readonly property string bluetoothOff: "\u{f00b2}"
  readonly property string badge: "\uf444"

  readonly property string bell: "\uf0a2"
  readonly property string bellDnd: "\uf1f7"

  // Tray menu decorations.
  readonly property string menuSubmenu: "\uf054"
  readonly property string menuCheck: "\uf00c"
  readonly property string menuRadio: "\uf111"

  // swaync reports its state in the `alt` field; Waybar mapped each value to a
  // glyph. Pango's `foreground=` is translated to Qt rich text's `color:`.
  readonly property var notification: ({
      "notification": "\uf444 \uf0a2",
      "none": "\uf0a2",
      "none-cc-open": "\uf0a2",
      "dnd-none": "\uf1f7",
      "dnd-notification": "\uf1f7<span style='color:red'><sup>\uf444</sup></span>",
      "inhibited-notification": "\uf0a2<span style='color:red'><sup>\uf444</sup></span>",
      "inhibited-none": "\uf0a2",
      "dnd-inhibited": "\uf1f7<span style='color:red'><sup>\uf444</sup></span>",
      "dnd-inhibited-none": "\uf1f7"
    })
}

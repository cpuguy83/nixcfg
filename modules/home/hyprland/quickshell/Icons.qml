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


  // Control Center (nf-fa-sliders). Deliberately neutral: this button owns
  // audio, VPN, Bluetooth and network, so showing any one subsystem's glyph
  // as the resting state misrepresents what clicking it does. Abnormal
  // states are reported as prefix badges instead.
  readonly property string controlCenter: "\uf1de"

  readonly property string bluetoothOn: "\u{f00af}"
  readonly property string bluetoothOff: "\u{f00b2}"
  readonly property string badge: "\uf444"

  // Bluetooth section (control-center.md sec. 9.7). Codepoints checked
  // directly against AdwaitaMonoNerdFont's cmap before landing here
  // (nf-md-magnify, nf-md-delete_outline, nf-md-cog) - the same
  // verification the header comment above demands.
  readonly property string scan: "\u{f0349}"
  readonly property string forget: "\u{f09e7}"
  readonly property string settings: "\u{f0493}"

  // VPN section (control-center.md sec. 9.6). Extracted byte-exact from
  // `corpnet-vpn-indicator.sh`'s own `status`/`state` output rather than
  // retyped (nf-md-vpn, verified against AdwaitaMonoNerdFont's cmap).
  readonly property string vpn: "\u{f0582}"

  // Network section (control-center.md sec. 9.7). Codepoints checked against
  // AdwaitaMonoNerdFont's cmap the same way as the Bluetooth set above
  // (nf-md-wifi_strength_outline/_1/_2/_3/_4, nf-md-wifi_off, nf-md-ethernet,
  // nf-md-lock, nf-md-eye, nf-md-eye_off). `wifiLevels` runs weakest to
  // strongest, matching `volumeLevels`'s ordering above.
  readonly property list<string> wifiLevels: ["\u{f092f}", "\u{f091f}", "\u{f0922}", "\u{f0925}", "\u{f0928}"]
  readonly property string wifiOff: "\u{f05aa}"
  readonly property string ethernet: "\u{f0200}"
  readonly property string lock: "\u{f033e}"
  readonly property string reveal: "\u{f0208}"
  readonly property string revealOff: "\u{f0209}"

  // ControlCenterButton prefix badge (control-center.md sec. 9.8, stage 7):
  // shown only for an abnormal state, never for a healthy one.
  // nf-md-wifi_strength_alert_outline, verified against AdwaitaMonoNerdFont's
  // cmap.
  readonly property string networkOffline: "\u{f092b}"

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

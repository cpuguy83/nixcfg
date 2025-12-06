{ ... }:

{
  imports = [
    ./shared.nix
  ];

  mine.desktop.hyprland.monitors = [
    "DP-1,preferred,auto-right,auto"
    "DP-2,preferred,auto-left,auto"

    # These are used as backchannels to DP-1 and DP-2 for DDC/CI
    "HDMI-A-1,disable"
    "HDMI-A-3,disable"
  ];
  mine.desktop.hyprland.lockScreenMonitor = "DP-1";
}

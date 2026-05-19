{ ... }:

{
  imports = [
    ./shared.nix
  ];

  mine.desktop.hyprland.monitors = [
    "DP-1,preferred,2160x840,1"
    "DP-2,preferred,0x0,1,transform,3"

    # These are used as backchannels to DP-1 and DP-2 for DDC/CI
    "HDMI-A-1,disable"
    "HDMI-A-3,disable"
  ];
  mine.desktop.hyprland.lockScreenMonitor = "DP-1";
}

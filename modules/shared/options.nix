{ lib, ... }:
let
  inherit (lib) mkEnableOption types;
in
{
  options.mine.desktop.hyprland.enable = mkEnableOption "Enable Hyprland profile";
  options.mine.desktop.hyprland.monitors = lib.mkOption {
    type = with types; listOf str;
    default = [ ];
    description = "Hyprland monitor directives for this machine.";
    example = [
      "DP-1,preferred,auto-right,auto"
      "HDMI-A-1,disable"
    ];
  };
}

{ lib, ... }:
let
  inherit (lib) mkEnableOption;
in
{
  options.mine.desktop.hyprland.enable = mkEnableOption "Enable Hyprland profile";
}

{
  pkgs,
  pkgs-unstable,
  lib,
  config,
  ...
}:
let
  cfg = config.mine.desktop.hyprland;
in
{
  config = lib.mkIf cfg.enable {
    xdg.portal.extraPortals = [
      pkgs-unstable.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
      pkgs-unstable.xdg-desktop-portal-termfilechooser
    ];
    xdg.portal.config.common.default = "*";
  };
}

{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
let
  cfg = config.mine.desktop.hyprland;
  hyprPkgs = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  config = lib.mkIf cfg.enable {
    xdg.portal.extraPortals = [
      hyprPkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
    ];
    xdg.portal.config.common.default = "*";
  };
}

{
  pkgs,
  pkgs-unstable,
  lib,
  config,
  inputs,
  ...
}:
let
  cfg = config.mine.desktop.hyprland;
  # hyprPkgs = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  config = lib.mkIf cfg.enable {
    xdg.portal.extraPortals = [
      pkgs-unstable.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-termfilechooser
    ];
    xdg.portal.config.common.default = "*";
    # xdg.portal.config.common."org.freedesktop.impl.portal.FileChooser" = "termfilechooser";
  };
}

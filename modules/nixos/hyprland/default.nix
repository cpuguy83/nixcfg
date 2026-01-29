{
  pkgs,
  pkgs-unstable,
  inputs,
  lib,
  config,
  ...
}:
let
  cfg = config.mine.desktop.hyprland;
in
{
  imports = [
    ./greetd.nix
  ];
  config = lib.mkIf cfg.enable {
    nix.settings = {
      substituters = lib.mkAfter [
        "https://hyprland.cachix.org"
      ];

      trusted-substituters = lib.mkAfter [
        "https://hyprland.cachix.org"
      ];

      trusted-public-keys = lib.mkAfter [
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];
    };

    programs.uwsm = {
      enable = true;
      waylandCompositors.hyprland = {
        binPath = lib.mkForce "${pkgs-unstable.hyprland}/bin/start-hyprland";
        prettyName = "Hyprland";
        comment = "Hyprland compositor managed by UWSM";
      };
    };

    programs.hyprland = with pkgs-unstable; {
      package = hyprland;
      portalPackage = xdg-desktop-portal-hyprland;
      enable = true;
      withUWSM = true;
      xwayland.enable = true;
    };
  };
}

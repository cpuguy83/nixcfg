{
  pkgs,
  inputs,
  lib,
  config,
  ...
}:
let
  cfg = config.mine.desktop.hyprland;
  hyprPkg = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};
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
      # waylandCompositors.hyprland = {
      #   prettyName = "Hyprland";
      #   binPath = "${hyprPkg.hyprland}/bin/hyprland";
      # };
    };

    programs.hyprland = with hyprPkg; {
      package = hyprland;
      portalPackage = xdg-desktop-portal-hyprland;
      enable = true;
      withUWSM = true;
      xwayland.enable = true;
    };

    systemd.user.services.xdg-desktop-portal-termfilechooser = {
      description = "Portal service (terminal file chooser implementation)";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      after = [ "graphical-session.target" ];
    };
  };
}

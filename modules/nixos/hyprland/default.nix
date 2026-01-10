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
  hyprlandUWSMSession = pkgs.stdenvNoCC.mkDerivation {
    pname = "hyprland-uwsm-session";
    version = "1";

    dontUnpack = true;

    installPhase = ''
      mkdir -p $out/share/wayland-sessions
      cat > $out/share/wayland-sessions/hyprland-uwsm.desktop <<'EOF'
      [Desktop Entry]
      Name=Hyprland (UWSM)
      Comment=Hyprland compositor managed by UWSM
      Type=Application
      DesktopNames=Hyprland
      Exec=${pkgs.uwsm}/bin/uwsm start -e -D Hyprland ${hyprPkg.hyprland}/bin/start-hyprland
      EOF
    '';

    passthru.providedSessions = [ "hyprland-uwsm" ];
  };
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
      waylandCompositors.hyprland.binPath = lib.mkForce "${hyprPkg.hyprland}/bin/start-hyprland";
    };

    services.displayManager.sessionPackages = [ hyprlandUWSMSession ];

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

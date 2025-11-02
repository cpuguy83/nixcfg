{
  pkgs,
  cfg,
  lib,
  ...
}:
{
  xdg.portal.extraPortals = lib.mkAfter [ pkgs.xdg-desktop-portal-termfilechooser ];
  xdg.portal.config = lib.mkMerge [
    { common."org.freedesktop.impl.portal.FileChooser" = "termfilechooser"; }

    (lib.mkIf cfg.mine.hyprland.enable {
      Hyprland.default = [
        "hyprland"
        "gtk"
      ];
      "uwsm-hyprland".default = [
        "hyprland"
        "gtk"
      ];

    })
    # other desktops get their own mkIf block here…
  ];
}

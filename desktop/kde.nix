{
  pkgs,
  lib,
  config,
  ...
}:

with lib;
{
  config = mkIf (config.desktop.de == "kde") {
    services.displayManager.sddm.enable = true;
    services.desktopManager.plasma6.enable = true;

    programs.kdeconnect.enable = true;
    users.users.cpuguy83 = {
      packages = with pkgs.kdePackages; [
        kate
        kdepim-addons
        merkuro
        korganizer
      ];
    };
  };
}

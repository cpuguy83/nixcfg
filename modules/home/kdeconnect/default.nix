{ pkgs, ... }:
{
  systemd.user.services.kdeconnectd = {
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
    Unit = {
      Description = "KDE Connect Daemon";
      After = [
        "graphical-session.target"
        "xdg-desktop-autostart.target"
      ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.kdePackages.kdeconnect-kde}/bin/kdeconnectd";
      Restart = "on-failure";
    };
  };

  systemd.user.services.kdeconnect-indicator = {
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
    Unit = {
      Description = "KDE Connect Indicator";
      After = [
        "graphical-session.target"
        "xdg-desktop-autostart.target"
      ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${pkgs.kdePackages.kdeconnect-kde}/bin/kdeconnect-indicator";
      Restart = "on-failure";
    };
  };
}

{ config
, lib
, pkgs
, ...
}:

let
  cfg = config.services.tether;
in
{
  options.services.tether = {
    enable = lib.mkEnableOption "tether iPhone bridge (clipboard sync and iMessage/SMS)";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.tether ];

    systemd.user.services.tetherd = {
      Unit = {
        Description = "Tether daemon";
        # Reads the Wayland clipboard via wlr-data-control and execs
        # tether-dialog for pairing approval, so it needs the graphical
        # session's environment.
        PartOf = [ "graphical-session.target" ];
        After = [
          "graphical-session.target"
          "xdg-desktop-autostart.target"
        ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.tether}/bin/tetherd";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # tether-gtk publishes a StatusNotifierItem the Quickshell bar already
    # hosts. --tray starts it hidden, so it costs a tray icon and nothing else.
    systemd.user.services.tether-gtk = {
      Unit = {
        Description = "Tether tray application";
        PartOf = [ "graphical-session.target" ];
        Wants = [ "tetherd.service" ];
        After = [
          "graphical-session.target"
          "xdg-desktop-autostart.target"
          "tetherd.service"
        ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${pkgs.tether}/bin/tether-gtk --tray";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}

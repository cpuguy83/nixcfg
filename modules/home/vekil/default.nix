{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.vekil;
in
{
  options.services.vekil = {
    enable = lib.mkEnableOption "vekil, a proxy for GitHub Copilot APIs";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.vekil ];

    systemd.user.services.vekil = {
      Unit = {
        Description = "Vekil - GitHub Copilot API proxy";
        After = [ "network-online.target" ];
      };

      Service = {
        Type = "simple";
        ExecStart = "${pkgs.vekil}/bin/vekil --host 127.0.0.1";
        Restart = "on-failure";
        RestartSec = 5;
      };

      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}

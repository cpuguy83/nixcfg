{ config
, lib
, pkgs
, ...
}:

let
  cfg = config.services.vekil;
in
{
  options.services.vekil = {
    enable = lib.mkEnableOption "vekil tray app";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.vekil ];
  };
}

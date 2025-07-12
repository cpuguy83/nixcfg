{ pkgs, config, lib, ... }:

with lib; let
  cfg = config.msft-corp;
in {
  options.msft-corp = {
    enable = mkEnableOption {
      description = "Microsoft services integration";
      default = false;
    };
  };
  config = mkIf cfg.enable {
    services.intune.enable = true;
    environment.systemPackages = [
      pkgs.microsoft-edge
      pkgs.intune-portal
      pkgs.microsoft-identity-broker
    ];
  };
}

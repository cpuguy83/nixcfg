{ pkgs, pkgs-unstable, config, lib, ... }:

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
    # Make sure that the unstable channel is used for these packages
    # I think this is necessary because `services.intune.enable` is referencing
    # the stable channel otherwise.
    # 
    # Unstable is needed to pick up a few fixes that are not currently in stable
    # such that stable is non-functional.
    nixpkgs.overlays = lib.mkAfter [
      (final: prev: {
        microsoft-identity-broker = pkgs-unstable.microsoft-identity-broker;
        intune-portal = pkgs-unstable.intune-portal;
      })
    ];

    services.intune.enable = true;
    environment.systemPackages = [
      pkgs.microsoft-edge
      pkgs-unstable.intune-portal
      pkgs-unstable.microsoft-identity-broker
    ];
  };
}

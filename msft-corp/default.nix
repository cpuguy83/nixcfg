{ pkgs, pkgs-unstable, config, lib, ... }:

with lib; let
  cfg = config.msft-corp;
  call = pkgs.lib.callPackageWith pkgs;
  entra-sso = call ./entra-sso.nix { };
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
      entra-sso
    ];


    # NixOS is not a supported OS for Intune and this is part of the compliance
    # checks. This is a workaround to make it look like we are running Ubuntu.
    environment.etc."intune-fake-os-release".text = ''
PRETTY_NAME="Ubuntu 24.04.2 LTS"
NAME="Ubuntu"
VERSION_ID="24.04"
VERSION="24.04.2 LTS (Noble Numbat)"
VERSION_CODENAME=noble
ID=ubuntu
ID_LIKE=debian
HOME_URL="https://www.ubuntu.com/"
SUPPORT_URL="https://help.ubuntu.com/"
BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
UBUNTU_CODENAME=noble
LOGO=ubuntu-logo
    '';

    systemd.user.services.intune-agent = {
      serviceConfig = {
        BindReadOnlyPaths = [
          "/etc/intune-fake-os-release:/etc/os-release"
        ];
      };
    };

  environment.etc."mozilla/native-messaging-hosts/linux_entra_sso.json".source =
    "${entra-sso}/lib/mozilla/native-messaging-hosts/linux_entra_sso.json";
  };
}

{ lib, ... }:
let
  inherit (lib) mkEnableOption types;
in
{
  options.mine.desktop.hyprland.enable = mkEnableOption "Enable Hyprland profile";
  options.mine.desktop.hyprland.monitors = lib.mkOption {
    type = with types; listOf str;
    default = [ ];
    description = "Hyprland monitor directives for this machine.";
    example = [
      "DP-1,preferred,auto-right,auto"
      "HDMI-A-1,disable"
    ];
  };

  options.mine.desktop.hyprland.lockScreenMonitor = lib.mkOption {
    type = with types; nullOr str;
    default = null;
    description = "Monitor to target for hyprlock widgets; null uses Hyprlock defaults.";
    example = "eDP-1";
  };

  options.mine.msft-corp = {
    enable = mkEnableOption {
      description = "Microsoft services integration";
      default = false;
    };

    authStack = lib.mkOption {
      type = types.enum [
        "intune"
        "himmelblau"
      ];
      default = "intune";
      description = "Corporate identity/compliance backend to use.";
    };

    himmelblau = {
      localUser = lib.mkOption {
        type = types.str;
        default = "cpuguy83";
        description = "Local user to map to an Entra ID user for Himmelblau.";
      };

      upn = lib.mkOption {
        type = types.str;
        description = "Entra ID UPN to map to the local user for Himmelblau.";
      };
    };
  };
}

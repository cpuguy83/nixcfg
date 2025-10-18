{ lib, ... }:

with lib;
{
  options.desktop.de = mkOption {
    type = types.nullOr (
      types.enum [
        "gnome"
        "kde"
        "hyprland"
      ]
    );
    default = null;
    description = "WHich desktop environment to enable";
  };
}

{ lib, ... }:

with lib;
{
  imports = [
    # ./options.nix
    ./gnome.nix
    ./kde.nix
    ./hyprland
  ];

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

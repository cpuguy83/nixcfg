{ inputs, ... }:
{
  imports = [
    ./hyprland
    ./osd
    inputs.lanzaboote.nixosModules.lanzaboote
    ./boot.nix
    ./msft-corp
    ./1password.nix
  ];
}

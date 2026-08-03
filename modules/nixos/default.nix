{ inputs, ... }:
{
  imports = [
    ./audio
    ./hyprland
    ./osd
    inputs.lanzaboote.nixosModules.lanzaboote
    ./boot.nix
    ./msft-corp
    ./1password.nix
  ];
}

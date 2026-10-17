{ inputs, ... }:
{
  imports = [
    ./audio
    ./hyprland
    inputs.lanzaboote.nixosModules.lanzaboote
    ./boot.nix
    ./msft-corp
    ./1password.nix
    ./tether
  ];
}

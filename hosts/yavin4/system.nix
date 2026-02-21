{ ... }:
{
  imports = [
    ./hardware.nix
    ./shared.nix
    ../../modules/nixos/audio/id4
  ];

  networking.hostName = "yavin4";

  hardware.i2c.enable = true;
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}

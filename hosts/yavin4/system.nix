{ ... }:
{
  imports = [
    ./hardware.nix
    ./shared.nix
  ];

  networking.hostName = "yavin4";

  hardware.i2c.enable = true;
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
}

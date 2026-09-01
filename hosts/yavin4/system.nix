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

  mine.tether.enable = true;

  # Wanted explicitly for iMessage/SMS mirroring, which is unreachable without
  # the A/V Hands-Free Class of Device. Fully reversible: bluetoothd resets the
  # class to its own default on every start, so disabling this and restarting
  # bluetooth.service is a complete back-out.
  mine.tether.bluetoothAccessory.enable = true;
}

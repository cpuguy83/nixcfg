{pkgs, lib, ...}:
{
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.initrd.systemd.enable = true;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
  };

  boot.binfmt = {
    emulatedSystems = [
      "aarch64-linux"
      "armv7l-linux"
      "riscv64-linux"
      "wasm32-wasi"
      "wasm64-wasi"
    ];
    preferStaticEmulators = true;
  };

  boot.supportedFilesystems = [ "btrfs" "ext4" "vfat" "ntfs" "f2fs" "xfs" "ntfs-3g" ];

  # per GPT, may help with BT firmware issue where the device just quit working
  # after suspend and I had to completely pull the power to get it working again
  # boot.extraModprobeConfig = ''
  #   options btusb enable_autosuspend=0
  # '';
}

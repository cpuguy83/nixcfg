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

  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "riscv64-linux"
  ];

  boot.kernelParams = [ "amdgpu.sg_display=0" "amd_iommu=on" ];
  boot.kernelModules = [ "amdgpu" "kvm_amd" ];

  # per GPT, may help with BT firmware issue where the device just quit working
  # after suspend and I had to completely pull the power to get it working again
  boot.extraModprobeConfig = ''
    options btusb enable_autosuspend=0
  '';

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  hardware.firmware = [ pkgs.linux-firmware ];
}

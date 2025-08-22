{ pkgs, config, ... }:
{
  imports = [ ./hardware-configuration.nix ];

  services.xserver.videoDrivers = [ "amdgpu" ];

  hardware.firmware = [ pkgs.linux-firmware ];
  hardware.amdgpu.initrd.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;

    settings = {
      General = {
        Experimental = true;
      };
    };
  };

  hardware.cpu.amd.updateMicrocode = true;

  boot.kernelParams = [
    "amdgpu.sg_display=0"
    "amd_iommu=on"
    "amd_pstate=active"
  ];
  boot.kernelModules = [
    "amdgpu"
    "kvm_amd"
    "zenpower"
  ];
  boot.blacklistedKernelModules = [ "k10temp" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.zenpower ];

  services.fstrim.enable = true;
}

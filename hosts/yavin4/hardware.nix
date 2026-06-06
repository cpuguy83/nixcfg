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
        KernelExperimental = true;
      };
    };
    disabledPlugins = [
      "StatusIcon"
      "ShowConnected"
      "ConnectionNotifier"
      "DhcpClient"
      "NetUsage"
      "PPPSupport"
      "StatusNotifierItem"
    ];
  };

  services.blueman.enable = true;
  hardware.cpu.amd.updateMicrocode = true;

  boot.kernelParams = [
    "amdgpu.sg_display=0"
    "amd_iommu=on"
    "amd_pstate=active"

    "mem_sleep_default=deep"
    "usbcore.autosuspend=-1"
  ];
  boot.kernelModules = [
    "amdgpu"
    "kvm_amd"
    "zenpower"
  ];
  boot.blacklistedKernelModules = [ "k10temp" ];
  boot.extraModulePackages = [ config.boot.kernelPackages.zenpower ];

  environment.variables.AMD_VULKAN_ICD = "RADV";

  # Pin webkit2gtk's GPU render device to the discrete RX 7900 (renderD128).
  # This webkit build (2.52.x) has no WEBKIT_DRM_* selection vars; it honors
  # WEBKIT_WEB_RENDER_DEVICE_FILE. Without this, WebKitWebProcess defaults to
  # the weaker integrated GPU (renderD129). by-path keeps it stable across boots.
  environment.sessionVariables.WEBKIT_WEB_RENDER_DEVICE_FILE =
    "/dev/dri/by-path/pci-0000:03:00.0-render";

  # Force all Mesa GL/EGL/GBM clients (WebKitGTK, Electron/Chromium, etc.) to
  # render on the discrete RX 7900 XTX (0000:03:00.0 / renderD128). The
  # compositor already runs on it; clients otherwise default to the iGPU
  # (renderD129). Mesa PCI-tag form (underscores) takes precedence over the GBM
  # default and the compositor's dmabuf feedback. PCI tag is stable across boots.
  environment.sessionVariables.DRI_PRIME = "pci-0000_03_00_0";

  # AMD GPU controller
  services.lact.enable = true;

  services.fstrim.enable = true;
}

# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, pkgs-unstable, lib, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';


  # Bootloader.
  # Lanzaboote currently replaces the systemd-boot module.
  # This setting is usually set to true in configuration.nix
  # generated at installation time. So we force it to false
  # for now.
  # boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;
  # networking.bridges = {
  #   br0 = {
  #     interfaces = [ "enp8s0" ];
  #   };
  # };

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "amdgpu" ];

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.cpuguy83 = {
    isNormalUser = true;
    description = "Brian Goff";
    extraGroups = [ "networkmanager" "wheel" "docker" "libvirtd" "kvm"];
    packages = with pkgs; [
      kdePackages.kate
      kdePackages.kdepim-addons
      pkgs-unstable.kdePackages.korganizer
      ghostty
      stow
      fzy
      fzf
      starship
      hey-mail
      nil # nix language server
      go
      azure-cli
      zoom-us
      thunderbird
      remmina
      vulkan-tools
      direnv
    ];
  };

  users.groups.libvirtd.members = ["cpuguy83"];
  users.groups.docker.members = ["cpuguy83"];


  programs.firefox.enable = true;
  programs.kdeconnect.enable = true;

  nixpkgs.config.allowUnfree = true;

  virtualisation = {
    docker = {
      enable = true;
      daemon.settings = {
        experimental = true;
        features = {
          containerd-snapshotter = true;
        };
      };
    };

    libvirtd = {
      enable = true;
      allowedBridges = [ "birbr0" "br0" ];
    };

    spiceUSBRedirection = {
      enable = true;
    };
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = 
    (with pkgs; [
      git
      vim
      curl
      docker
      tpm2-tss
      sbctl
      pam_u2f
      slack
      wl-clipboard
      waypipe
      vscode
      htop
      ddcutil
      socat
    ])

    ++

    (with pkgs-unstable; [
      pkgs-unstable.firefox
      pkgs-unstable.qemu_kvm
      pkgs-unstable.qemu
      pkgs-unstable.virglrenderer
      pkgs-unstable.mesa
      pkgs-unstable.libglvnd
      pkgs-unstable.libGL
      pkgs-unstable.virt-manager
      pkgs-unstable.libvirt
    ]);

  # Sets proper link paths for packages using binaries not compiled against nix
  # (i.e. vscode's nodejs).
  programs.nix-ld.enable = true;

  environment.sessionVariables.NIXOS_OZONE_WL = "1";
  programs.virt-manager.enable = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  # Enable the OpenSSH daemon.
  # services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ]-;
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?

  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    # Certain features, including CLI integration and system authentication support,
    # require enabling PolKit integration on some desktop environments (e.g. Plasma).
    polkitPolicyOwners = [ "cpuguy83" ];
  };

  security.polkit.enable = true;
  security.pam = {
    services = {
      login.u2fAuth = true;
    };

    u2f = {
      enable = true;
      settings = {
        cue = true;
      };
    };
  };


  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

    systemd.user.services.msft-vm = {
    description = "Microsoft in-tuned VM";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        ExecStart = ''
          ${pkgs.qemu}/bin/qemu-system-x86_64 \
            -m 16384 \
            -enable-kvm \
            -cpu host \
            -smp 4 \
          -vga none \
            -M q35,accel=kvm \
            -netdev user,id=net0,hostfwd=tcp::2222-:22,hostfwd=tcp::13389-:3389,hostfwd=udp::13389-:3389 \
            -device virtio-net-pci,netdev=net0 \
            -device vhost-vsock-pci,guest-cid=3 \
            -audio driver=pipewire,model=virtio \
            -audiodev pipewire,id=snd0,in.channels=1,out.channels=2,in.frequency=48000,out.frequency=48000 \
            -device virtio-sound,audiodev=snd0 \
            -display gtk,gl=on \
            -device virtio-gpu-rutabaga,gfxstream-vulkan=on,cross-domain=on,hostmem=16G,wsi=surfaceless \
            -chardev socket,path=%t/msft-vm-mon.sock,server,nowait,id=qmp0 \
            -mon chardev=qmp0,mode=control \
            -drive file=/home/cpuguy83/VMs/ubuntu-msft.qcow2
      '';
        Restart = "on-failure";
      ExecStop = let
        qemuStopScript = pkgs.writeScript "stop-qemu-vm" ''
          #!{pkgs.runtimeShell}
        ${pkgs.socat}/bin/socat - UNIX-CONNECT=%t/msft-vm-mon.sock <<EOF
{ "execute": "qmp_capabilities" }
{ "execute": "system_powerdown" }
EOF
      '';
      in 
        "${qemuStopScript}";
      };
    };

  programs.steam.enable = true;
  programs.nh.enable = true;
  hardware.i2c.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.graphics.enable = true;

  # Make sure the systemd unit uses dockerd from our overlay instead of the
  # main pkgs.docker
  systemd.services.docker.serviceConfig.ExecStart = [
    ""
    "${pkgs.docker.moby}/bin/dockerd"
  ];

  boot.binfmt.emulatedSystems = [
    "aarch64-linux"
    "riscv64-linux"
  ];
}

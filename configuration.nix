# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ pkgs, pkgs-unstable, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  networking.hostName = "nixos"; # Define your hostname.

  # Enable networking
  networking.networkmanager.enable = true;

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
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.

  home-manager.users.cpuguy83 = {
    home.stateVersion = "25.05";
  };
  users.users.cpuguy83 = {
    isNormalUser = true;
    description = "Brian Goff";
    extraGroups = [ "networkmanager" "wheel" "docker" "kvm" "video" "audio" "render" ];
    packages = with pkgs; [
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
      gh
      jq
      vial
      via
      qmk
      qmk_hid
    ];
  };

  users.groups.docker.members = ["cpuguy83"];

  programs.firefox.enable = true;

  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = 
    (with pkgs; [
      git
      vim
      curl
      tpm2-tss
      sbctl
      pam_u2f
      slack
      wl-clipboard
      waypipe
      htop
      ddcutil
      socat

      v4l-utils

      # Just needed for copilot
      nodejs_24
    ])

    ++

    (with pkgs-unstable; [
      firefox
      vscode
      (pkgs.vscode.override { isInsiders = true; })
    ]);

  # Sets proper link paths for packages using binaries not compiled against nix
  # (i.e. vscode's nodejs).
  programs.nix-ld.enable = true;

  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?

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


  # Add support for airprint devices
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  programs.nh.enable = true;

  # Steamy stuff
  programs.steam.enable = true;
  hardware.i2c.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.graphics.enable = true;

  services.udev = {
    packages = with pkgs; [
      qmk
      qmk-udev-rules
      qmk_hid
      vial
    ];
  };
}

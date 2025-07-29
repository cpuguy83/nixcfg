{pkgs, lib, config, ...}:

with lib; {
  config = mkIf (config.desktop.de == "gnome") {
    services.xserver = {
      enable = true;
      displayManager = {
        gdm.enable = true;
      };
      desktopManager.gnome.enable = true;
    };

    services.gnome.gnome-keyring.enable = true;
    services.udev = {
      packages = with pkgs; [
        gnome-settings-daemon
      ];
    };

    # programs.ssh.askPassword = pkgs.lib.mkForce "${pkgs.seahorse.out}/libexec/seahorse/ssh-askpass";
    programs.kdeconnect.package = pkgs.gnomeExtensions.gsconnect;
    security.pam.services.gdm.enableGnomeKeyring = true;
    security.pam.services.login.enableGnomeKeyring = true;


    environment.systemPackages = with pkgs;
    (with gnomeExtensions; [
      gsconnect
      blur-my-shell
      just-perfection
      media-controls
      appindicator
    ])
    ++ [
      whitesur-gtk-theme
      gnome-tweaks
    ];
  };
}

{ pkgs, pkgs-unstable, lib, config, inputs, ... }:
with lib;
let
  inherit (lib) mkIf mkMerge;
  plugin-packages = inputs.hyprland-plugins.packages.${pkgs.stdenv.hostPlatform.system};
  hyprland-packages = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};
  hyprland = hyprland-packages.hyprland;
in
{
  config = mkIf (config.desktop.de == "hyprland") (
    mkMerge [
      (import ./login.nix { inherit lib pkgs hyprland; })
      (import ./osd.nix   { inherit pkgs-unstable; })
      (import ./shell.nix   { inherit home-manager pkgs inputs lib; })
      (import ./lockscreen.nix   { inherit pkgs home-manager; })
      (import ./settings.nix   { inherit pkgs plugin-packages inputs; })
      ({
        services.gnome.gnome-keyring.enable = true;
        security.pam.services.login.enableGnomeKeyring = true;
        security.pam.services.su.enableGnomeKeyring = true;
        security.pam.services.sudo.enableGnomeKeyring = true;

        programs.hyprland = {
          package = hyprland;
          portalPackage = hyprland-packages.xdg-desktop-portal-hyprland;
          enable = true;
          withUWSM = true;
          xwayland.enable = true;
        };


        services.gnome.glib-networking.enable = true;
        services.hypridle.enable = true;
        services.blueman.enable = true;

        programs.uwsm.enable = true;

        systemd.user.services.mpris-proxy = {
            description = "Mpris proxy";
            after = [ "network.target" "sound.target" ];
            wantedBy = [ "default.target" ];
        };

        environment.systemPackages = with pkgs; [
          # Needed because hyprland uses kitty as the default terminal
          kitty
          ghostty

          cliphist

          pavucontrol
          fuzzel
          hyprpolkitagent
          kdePackages.dolphin
          brightnessctl
          playerctl
          glib-networking
          hyprshot
          qimgv
          gnome-font-viewer

          seahorse # gnome-keyring GUI
        ];

        services.udisks2.enable = true;

        programs.kdeconnect.enable = true;
        services.dbus.packages = with pkgs; [
          kdePackages.kdeconnect-kde
        ];

        systemd.user.services.kdeconnectd = {
          enable = true;
          description = "KDE Connect Daemon";
          wantedBy = [ "graphical-session.target" ];
          after = [
            "graphical-session.target"
            "xdg-desktop-autostart.target"
          ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.kdePackages.kdeconnect-kde}/bin/kdeconnectd";
            Restart = "on-failure";
          };
        };

        systemd.user.services.kdeconnect-indicator = {
          enable = true;
          description = "KDE Connect Indicator";
          wantedBy = [ "graphical-session.target" ];
          after = [
            "graphical-session.target"
            "xdg-desktop-autostart.target"
          ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.kdePackages.kdeconnect-kde}/bin/kdeconnect-indicator";
            Restart = "on-failure";
          };
        };

        systemd.user.services.hyprpolkitagent = {
          enable = true;
          description = "Hyprland Polkit Agent";
          wantedBy = [ "graphical-session.target" ];
          after = [
            "graphical-session.target"
            "xdg-desktop-autostart.target"
          ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
            Restart = "on-failure";
          };
        };

        environment.sessionVariables = {
          WLR_NO_HARDWARE_CURSORS = "1";
          NIXOS_OZONE_WL = "1";
          GDK_BACKEND = "wayland"; # Essential for GTK apps in Wayland
          QT_QPA_PLATFORM = "wayland"; # For Qt apps in Wayland
          MOZ_ENABLE_WAYLAND = "1"; # For Firefox in Wayland
          _JAVA_AWT_WM_NONREPARENTING = "1"; # For Java apps compatibility
        };

        xdg.portal = {
          enable = true;
          extraPortals = with hyprland-packages; [
            xdg-desktop-portal-hyprland
            pkgs.xdg-desktop-portal-gtk
          ];
        };

        home-manager.users.cpuguy83.services.hypridle = {
          enable = true;
          settings = {
            general = {
              lock_cmd = "pidof xhyprlock || hyprlock";
              before_sleep_cmd = "loginctl lock-session";
              after_sleep_cmd = "hyprctl dispatch dpms on && uwsm app -S both -- ashell";
            };

            listener = [
              {
                timeout = 150; # 2.5 minutes
                on-timeout = "brightnessctl -s set 10";
                on-resume = "brightnessctl -r";
              }
              {
                timeout = 600; # 10 minutes
                on-timeout = "loginctl lock-session";
              }
              {
                timeout = 1800; # 30 minutes
                on-timeout = "hyprctl dispatch dpms off";
                on-resume = "hyprctl dispatch dpms on && brightnessctl -r";
              }
            ];
          };
        };
      })
    ]
  );
}

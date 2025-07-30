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
      (import ./osd.nix   { inherit pkgs; })
      (import ./settings.nix   { inherit pkgs plugin-packages home-manager; })
      ({
        nix.settings = {
          substituters = lib.mkAfter["https://hyprland.cachix.org"];
          trusted-substituters = lib.mkAfter["https://hyprland.cachix.org"];
          trusted-public-keys = lib.mkAfter["hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="];
        };

        services.gnome.gnome-keyring.enable = true;
        security.pam.services.login.enableGnomeKeyring = true;
        security.pam.services.su.enableGnomeKeyring = true;
        security.pam.services.sudo.enableGnomeKeyring = true;
        security.pam.services.hyprlock.u2fAuth = true;

        programs.hyprland = {
          package = hyprland;
          portalPackage = hyprland-packages.xdg-desktop-portal-hyprland;
          enable = true;
          withUWSM = true;
          xwayland.enable = true;
        };


        services.gnome.glib-networking.enable = true;


        programs.hyprlock.enable = true;
        programs.uwsm.enable = true;

        services.hypridle.enable = true;
        services.blueman.enable = true;

        systemd.user.services.mpris-proxy = {
            description = "Mpris proxy";
            after = [ "network.target" "sound.target" ];
            wantedBy = [ "default.target" ];
        };

        environment.systemPackages = with pkgs; [
          # Needed because hyprland uses kitty as the default terminal
          kitty
          ghostty

          plugin-packages.hyprbars
          hyprlandPlugins.hyprspace

          swaynotificationcenter

          pkgs-unstable.ashell

          pavucontrol
          fuzzel
          hyprpolkitagent
          kdePackages.dolphin
          brightnessctl
          playerctl
          glib-networking
          hyprshot

          seahorse # gnome-keyring GUI
        ];

        systemd.user.services.hyprpolkitagent = {
          description = "Hyprland Polkit Agent";
          wantedBy = [ "graphical-session.target" ];
          after = [ "graphical-session.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
            Restart = "on-failure";
          };
        };

        systemd.user.services.ashell = {
          description = "Ashell - Hyprland Shell";
          wantedBy = [ "graphical-session.target" ];
          after = [ "graphical-session.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs-unstable.ashell}/bin/ashell";
            Restart = "on-failure";
          };
        };

        systemd.user.services.swaync = {
          description = "Sway Notification Center";
          wantedBy = [ "graphical-session.target" ];
          after = [ "graphical-session.target" ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "${pkgs.swaynotificationcenter}/bin/swaync";
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

        home-manager.users.cpuguy83.programs.hyprlock = {
          package = pkgs.hyprlock;
          enable = true;
          settings = {
            general = {
              hide_cursor = true;
            };
            label = [
              {
                monitor = "DP-1";
                color = "rgba(242, 243, 244, 0.75)";
                text = "$TIME";
                position = "0, 300";
                font_size = 95;
                font_family = "JetBrains Mono Nerd Font";
                halign = "center";
                valign = "center";
              }
            ];
            background = [
              {
                monitor = "";
                path = "screenshot";
                blur_passes = 3;
                blur_size = 7;
                brightness = 0.5;
                vibrancy = 0.2;
                vibrancy_darkness = 0.2;
              }
            ];
            input-field = {
              monitor = "DP-1";
              hide_input = false;
              placeholder_text = "Enter password";
              fade_on_empty = false;
            };
          };
        };

        home-manager.users.cpuguy83.services.hypridle = {
          enable = true;
          settings = {
            general = {
              lock_cmd = "pidof xhyprlock || hyprlock";
              before_sleep_cmd = "loginctl lock-session";
              after_sleep_cmd = "hyprctl dispatch dpms on";
            };

            listener = [
              {
                timeout = 150; # 2.5 minutes
                on-timeout = "brightnessctl -s set 10";
                on-resume = "brightnessctl -r";
              }
              {
                timeout = 300; # 5 minutes
                on-timeout = "loginctl lock-session";
              }
              {
                timeout = 1800; # 10 minutes
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

{ pkgs, lib, config, inputs, ... }:
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
        nix.settings = lib.mkMerge [
          {
            substituters = ["https://hyprland.cachix.org"];
            trusted-substituters = ["https://hyprland.cachix.org"];
            trusted-public-keys = ["hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="];
          }
        ];

        services.gnome.gnome-keyring.enable = true;

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

          pavucontrol
          fuzzel
          hyprpolkitagent
          kdePackages.dolphin
          brightnessctl
          playerctl
          glib-networking

          seahorse # gnome-keyring GUI
        ];


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

        home-manager.users.cpuguy83.programs.hyprpanel = {
          enable = true;
          systemd.enable = true;

          settings = {
            theme.bar.taransparent = true;
            # theme.bar.opacity = 80;
            menus.clock = {
              time = {
                military = true;
                hideSeconds = true;
              };
            };
            bar = {
              battery.label = false;
              customModules = {
                hypridle = {
                  isActiveCommand = "systemctl --user status hypridle.service | grep -q 'Active: active (running)' && echo 'yes' || echo 'no'";
                  startCommand = "systemctl --user start hypridle.service";
                  stopCommand = "systemctl --user stop hypridle.service";
                };
              };
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

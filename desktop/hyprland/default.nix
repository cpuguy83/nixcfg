{
  pkgs,
  pkgs-unstable,
  lib,
  config,
  inputs,
  ...
}:
with lib;
let
  inherit (lib) mkIf mkMerge;
  plugin-packages = inputs.hyprland-plugins.packages.${pkgs.stdenv.hostPlatform.system};
  hyprland-packages = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};
  hyprland = hyprland-packages.hyprland;
  fix_hyprlock_path = ".local/bin/fix-hyprlock.sh";
  yaziFilepickerConfig = pkgs.writeTextDir "yazi/config/yazi.toml" ''
    [manager]
    show_hidden = false
  '';
in
{
  config = mkIf (config.desktop.de == "hyprland") (mkMerge [
    (import ./login.nix { inherit lib pkgs hyprland; })
    (import ./osd.nix { inherit pkgs-unstable; })
    (import ./shell.nix {
      inherit
        home-manager
        pkgs
        inputs
        lib
        ;
    })
    (import ./lockscreen.nix { inherit pkgs home-manager; })
    (import ./settings.nix { inherit pkgs plugin-packages inputs; })
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
      # services.blueman.enable = true;

      programs.uwsm.enable = true;

      systemd.user.services.mpris-proxy = {
        description = "Mpris proxy";
        after = [
          "network.target"
          "sound.target"
        ];
        wantedBy = [ "default.target" ];
      };

      home-manager.users.cpuguy83.home.packages = with pkgs; [
        # Needed because hyprland uses kitty as the default terminal
        kitty
        ghostty

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

        dragon-drop # CLI drag-and-drop utility

        seahorse # gnome-keyring GUI

        xdg-desktop-portal-termfilechooser
      ];

      home-manager.users.cpuguy83.home.file.".config/xdg-desktop-portal-termfilechooser/ghostty-wrapper.sh" =
        {
          text = ''
            #!${pkgs.bash}/bin/bash
            set -eo pipefail

            export PATH="${
              lib.makeBinPath [
                pkgs.bash
                pkgs.coreutils
                pkgs.yazi
                pkgs.ghostty
              ]
            }:$PATH"
            export YAZI_CONFIG_HOME="${yaziFilepickerConfig}/yazi"
            export XDG_CONFIG_HOME="''${HOME}/.config"

            export TERMCMD="${lib.getExe pkgs.ghostty} --class=com.mitchellh.ghostty.filepicker --title='Yazi File Picker' -e"

            exec ${pkgs.xdg-desktop-portal-termfilechooser}/share/xdg-desktop-portal-termfilechooser/yazi-wrapper.sh "$@"
          '';
          executable = true;
        };

      home-manager.users.cpuguy83.home.file.".config/xdg-desktop-portal-termfilechooser/config" = {
        text = ''
          [filechooser]
          cmd=ghostty-wrapper.sh
          default_dir=$HOME/Downloads
          open_mode=suggested
          save_mode=suggested
        '';
      };

      services.udisks2.enable = true;

      programs.kdeconnect.enable = true;
      services.dbus.packages = with pkgs; [
        kdePackages.kdeconnect-kde
      ];

      systemd.user.services.xdg-desktop-portal-termfilechooser = {
        description = "Portal service (terminal file chooser implementation)";
        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
      };

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
          pkgs.xdg-desktop-portal-termfilechooser
        ];
        config = {
          common."org.freedesktop.impl.portal.FileChooser" = "termfilechooser";
          Hyprland = {
            default = [
              "hyprland"
              "gtk"
            ];
            "org.freedesktop.impl.portal.FileChooser" = "termfilechooser";
          };
          "uwsm-hyprland" = {
            default = [
              "hyprland"
              "gtk"
            ];
            "org.freedesktop.impl.portal.FileChooser" = "termfilechooser";
          };
        };
      };

      environment.variables = {
        GTK_USE_PORTAL = "1";
        GDK_DEBUG = "portals";
      };

      home-manager.users.cpuguy83.home.file.${fix_hyprlock_path} = {
        text = ''
          #!${pkgs.bash}/bin/bash

          # This script attempts to fix hyprlock after resuming from suspend
          # Frequently hyprlock has crashed or is not running after resume
          # This script will check if the session is locked and if so
          # restart hyprlock if it is not running.

          # Wait for Hyprland to be ready
          echo "Waiting for Hyprland to be ready..." >&2
          for i in {1..100}; do
            if hyprctl monitors --instance 0 >/dev/null 2>&1; then
              break
            fi
            sleep 0.2
          done

          # Check one more time if hyprland is ready
          if ! hyprctl monitors --instance 0 >/dev/null 2>&1; then
            echo "Hyprland is not running. Exiting." >&2
            exit
          fi

          echo "Hyprland is ready." >&2

          # If hyprlock is already running there is nothing to do
          if pidof hyprlock >/dev/null 2>&1; then
            echo "hyprlock is already running." >&2
            exit
          fi

          # Determine if the current session is locked
          sid="$(loginctl | awk -v user="$USER" '$3 == user {print $1; exit}')"
          [ -z "$sid" ] && exit
          locked="$(loginctl show-session "$sid" -p LockedHint | cut -d= -f2)"

          # If the session is not locked there is nothing to do
          if [ "$locked" != "yes" ]; then
            echo "Session is not locked. Exiting." >&2
            exit
          fi

          # restore hyprlock
          echo "Session is locked. Restarting hyprlock..." >&2
          hyprctl --instance 0 'keyword misc:allow_session_lock_restore=1' && \
          hyprctl --instance 0 'dispatch exec hyprlock'
        '';
        executable = true;
      };

      home-manager.users.cpuguy83.systemd.user.services.fix-hyprlock = {
        Unit = {
          Description = "Fix hyprlock after resume";
          After = [ "suspend.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "%h/${fix_hyprlock_path}";
        };
        Install = {
          WantedBy = [ "suspend.target" ];
        };
      };

      home-manager.users.cpuguy83.services.hypridle = {
        enable = true;
        settings = {
          general = {
            lock_cmd = "pidof hyprlock || hyprlock";
            before_sleep_cmd = "loginctl lock-session";
            after_sleep_cmd = "hyprctl dispatch dpms";
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
  ]);
}

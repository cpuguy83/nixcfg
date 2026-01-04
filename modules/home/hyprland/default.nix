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
  hyprland-packages = inputs.hyprland.packages.${pkgs.stdenv.hostPlatform.system};
  fix_hyprlock_path = ".local/bin/fix-hyprlock.sh";
  brightnessScript = pkgs.writeScriptBin "hyprland-brightness" (builtins.readFile ./brightness.sh);
  brightnessPath = pkgs.lib.getExe brightnessScript;
  getMonitorScript = pkgs.writeScriptBin "hyprland-get-monitor" (
    builtins.readFile ./get_active_monitor.sh
  );
  getMonitorPath = pkgs.lib.getExe getMonitorScript;
  dpmsRestoreScript = pkgs.writeScriptBin "hyprland-dpms-brightness-restore" ''
    #!${pkgs.bash}/bin/bash

    for i in 1 2 3 4 5; do
      if ${pkgs.hyprland}/bin/hyprctl monitors -j | ${pkgs.jq}/bin/jq -e 'all(.dpmsStatus == true)' >/dev/null; then
        break
      fi
      ${pkgs.hyprland}/bin/hyprctl dispatch dpms on
      ${pkgs.coreutils}/bin/sleep 5
    done

    ${brightnessPath} restore ALL
  '';
  dpmsRestorePath = pkgs.lib.getExe dpmsRestoreScript;
  yaziFilepickerConfig = pkgs.writeTextDir "yazi/config/yazi.toml" ''
    [manager]
    show_hidden = false
  '';
  cfg = config.mine.desktop.hyprland;
in
{
  config = mkIf (cfg.enable) (mkMerge [
    (import ./shell.nix {
      inherit
        pkgs
        inputs
        lib
        ;
    })
    (import ./lockscreen.nix {
      inherit
        pkgs-unstable
        lib
        config
        ;
    })
    (import ./settings.nix {
      inherit
        pkgs
        config
        lib
        inputs
        hyprland-packages
        brightnessPath
        getMonitorPath
        ;
    })
    ({
      systemd.user.services.gnome.gnome-keyring.enable = true;
      systemd.user.services.gnome.glib-networking.enable = true;
      systemd.user.services.polkit-gnome = {
        Unit.Description = "Polkit GNOME authentication agent";
        Service = {
          ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };

      xdg.portal.extraPortals = [
        hyprland-packages.xdg-desktop-portal-hyprland
        pkgs.xdg-desktop-portal-gtk
      ];

      home.packages = with pkgs; [
        # Needed because hyprland uses kitty as the default terminal
        kitty
        ghostty

        pavucontrol
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

      programs.fuzzel = {
        enable = true;
        settings.main = {
          terminal = "ghostty";
          launch-prefix = "uwsm app --";
        };
      };

      home.file.".config/xdg-desktop-portal-termfilechooser/ghostty-wrapper.sh" = {
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

      home.file.".config/xdg-desktop-portal-termfilechooser/config" = {
        text = ''
          [filechooser]
          cmd=ghostty-wrapper.sh
          default_dir=$HOME/Downloads
          open_mode=suggested
          save_mode=suggested
        '';
      };

      home.sessionVariables = {
        WLR_NO_HARDWARE_CURSORS = "1";
        NIXOS_OZONE_WL = "1";
        GDK_BACKEND = "wayland"; # Essential for GTK apps in Wayland
        QT_QPA_PLATFORM = "wayland"; # For Qt apps in Wayland
        MOZ_ENABLE_WAYLAND = "1"; # For Firefox in Wayland
        _JAVA_AWT_WM_NONREPARENTING = "1"; # For Java apps compatibility
      };

      home.sessionVariables = {
        GTK_USE_PORTAL = "1";
        GDK_DEBUG = "portals";
      };

      home.file.${fix_hyprlock_path} = {
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
          # locked="$(loginctl show-session "$sid" -p LockedHint | cut -d= -f2)"

          # If the session is not locked there is nothing to do
          # if [ "$locked" != "yes" ]; then
          #   echo "Session is not locked. Exiting." >&2
          #   exit
          # fi

          # restore hyprlock
          echo "Session is locked. Restarting hyprlock..." >&2
          hyprctl --instance 0 'keyword misc:allow_session_lock_restore 1' && \
          hyprctl --instance 0 'dispatch exec hyprlock'
        '';
        executable = true;
      };

      systemd.user.services.fix-hyprlock = {
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

      services.hypridle = {
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
              on-timeout = "${brightnessPath} set ALL 10";
              on-resume = dpmsRestorePath;
            }
            {
              timeout = 600; # 10 minutes
              on-timeout = "loginctl lock-session";
            }
            {
              timeout = 1800; # 30 minutes
              on-timeout = "hyprctl dispatch dpms off";
              on-resume = "hyprctl dispatch dpms on";
            }
          ];
        };
      };
    })
  ]);
}

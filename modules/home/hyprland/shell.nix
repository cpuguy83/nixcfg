{ pkgs, config, lib, ... }:

let
  corpnet = config.mine.msft-corp.corpnet;
  corpnet-vpn-switch = pkgs.writeShellApplication {
    name = "corpnet-vpn-switch";
    runtimeInputs = with pkgs; [ systemd gawk ];
    text = builtins.readFile ./corpnet-vpn-switch.sh;
  };
  corpnet-vpn-indicator = pkgs.writeShellApplication {
    name = "corpnet-vpn-indicator";
    runtimeInputs = with pkgs; [
      systemd
      fuzzel
      libnotify
      gawk
      gnugrep
      coreutils
      jq
    ];
    text = ''
      DEFAULT_UNIT="corpnet-vpn"
      DEFAULT_GATEWAY=${lib.escapeShellArg corpnet.gateway}
      GATEWAY_DOMAIN=${lib.escapeShellArg corpnet.gatewayDomain}
      GATEWAYS=${lib.escapeShellArg (lib.concatStringsSep "\n" corpnet.gateways)}
      SYSTEMCTL=/run/current-system/sw/bin/systemctl
      SWITCH=${corpnet-vpn-switch}/bin/corpnet-vpn-switch
    '' + builtins.readFile ./corpnet-vpn-indicator.sh;
  };
  tray-activation-probe = pkgs.writeShellApplication {
    name = "tray-activation-probe";
    runtimeInputs = [
      pkgs.systemd
      pkgs.gnugrep
      pkgs.gnused
      pkgs.coreutils
    ];
    text = builtins.readFile ./tray-activation-probe.sh;
  };
in
{
  services.swaync = {
    enable = true;
    settings = {
      cssPriority = "user";
      notification-2fa-action = true;
      notification-inline-replies = true;
      keyboard-shortcuts = false;
      notification-window-width = 420;
      notification-icon-size = 48;
      notification-body-image-height = 120;
      notification-body-image-width = 200;
      max-visible = 5;
      timeout = 8;
      timeout-low = 5;
      timeout-critical = 0;
      fit-to-screen = true;
      widgets = [
        "title"
        "dnd"
        "notifications"
        "mpris"
        "volume"
        "inhibitors"
      ];

      widget-config = {
        title = {
          text = "Notifications";
          clear-all-button = true;
          button-text = "Clear";
        };

        mpris = {
          autohide = true;
        };

        volume = {
          show-per-app = true;
          show-per-app-icon = true;
          label = " ";
        };
      };
    };
  };

  home.file.".config/swaync/style.css" = {
    source = ./swaync-style.css;
    onChange = "${pkgs.systemd}/bin/systemctl --user restart swaync.service || true";
  };

  programs.yazi = {
    enable = true;
    plugins = with pkgs.yaziPlugins; {
      mount = mount;
      git = git;
      chmod = chmod;
    };
    shellWrapperName = "yy";

    initLua = ''
      require("git"):setup()
    '';

    keymap = {
      mgr = {
        prepend_keymap = [
          {
            on = "M";
            run = "plugin mount";
            desc = "Mount stuff";
          }
          {
            on = [
              "c"
              "m"
            ];
            run = "plugin chmod";
            desc = "chmod";
          }
          {
            on = "<C-n>";
            run = "shell -- dragon-drop --all -x -T \"$1\"";
            desc = "Drag and drop";
          }
        ];
      };
    };

    settings = {
      mgr = {
        show_hidden = true;
        sort_by = "mtime";
        sort_reverse = true;
      };
    };
  };

  # Superseded by the Quickshell bar below. Kept configured (not removed) so it
  # can be brought back with a one-line change if the Quickshell bar regresses.
  programs.waybar = {
    enable = false;
    systemd.enable = true;
    style = builtins.readFile ./waybar.css;
    settings = {
      main = {
        height = 34;
        exclusive = true;
        passthrough = false;
        position = "top";
        spacing = 3;
        fixed-center = true;
        margin-top = 0;
        margin-bottom = 0;
        margin-left = 0;
        margin-right = 0;
        layer = "top";

        modules-left = [
          "wlr/taskbar"
        ];
        modules-center = [
          "mpris"
        ];
        modules-right = [
          "custom/audio-mode"
          "custom/corpnet-vpn"
          "group/audio"
          "bluetooth"
          "tray"
          "clock"
          "custom/notification"
        ];

        "hyprland/workspaces" = {
          active-only = false;
          all-outputs = false;
          format = "{icon}";
          on-click = "activate";
        };

        clock = {
          interval = 30;
          format = " {:%H:%M} ";
        };

        tray = {
          spacing = 2;
        };

        mpris = {
          interval = 1;
          format = " {title} | {artist} ";
          format-paused = " {title} | {artist} {status_icon} ";
          on-click = "playerctl play-pause";
          on-scroll-up = "playerctl next";
          on-scroll-down = "playerctl previous";
          status-icons = {
            playing = "";
            paused = "";
            stopped = "";
          };
        };

        wireplumber = {
          format = " {volume}% {icon} ";
          format-bluetooth = " {volume}% {icon}    ";
          format-muted = " {volume}% 󰖁 ";
          format-icons = {
            default = [
              ""
              ""
              ""
              ""
              " "
            ];
            headphones = "";
          };
          on-click = "pavucontrol";
          on-click-right = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          scroll-step = 5;
        };

        "wireplumber#source" = {
          node-type = "Audio/Source";
          format = " {volume}%  ";
          format-muted = " {volume}%   ";
          on-click-right = "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
          scroll-step = 5;
          on-click = "pavucontrol -t 4";
        };

        "group/audio" = {
          orientation = "horizontal";
          modules = [
            "wireplumber"
            "wireplumber#source"
          ];
        };

        # Superseded by AudioSection's latency tier control in the Quickshell
        # panel; kept only so the documented one-line rollback
        # (programs.waybar.enable = true) still shows something real instead
        # of a dead pw-profile-toggle reference. `audio-mode status`'s `text`
        # deliberately carries no glyph (unlike the old script's own "LIVE"
        # payload), so `format` supplies one here.
        "custom/audio-mode" = {
          format = "󰝱 {}";
          return-type = "json";
          exec = "${config.mine.audio.package}/bin/audio-mode status";
          on-click = "${config.mine.audio.package}/bin/audio-mode cycle";
          interval = 5;
          tooltip = true;
        };

        "custom/corpnet-vpn" = {
          format = "{}";
          return-type = "json";
          exec = "${corpnet-vpn-indicator}/bin/corpnet-vpn-indicator status";
          on-click = "${corpnet-vpn-indicator}/bin/corpnet-vpn-indicator toggle";
          on-click-right = "${corpnet-vpn-indicator}/bin/corpnet-vpn-indicator menu";
          interval = 3;
          tooltip = true;
        };

        "custom/azvpn" = {
          format = "AzureVPN ";
          exec = "echo '{\"class\": \"connected\"}'";
          exec-if = "test -d /proc/sys/net/ipv4/conf/MSFT-AzVPN-Temp";
          return-type = "json";
          interval = 10;
        };

        "custom/notification" = {
          tooltip = false;
          format = " {icon}  ";
          format-icons = {
            notification = " ";
            none = "";
            none-cc-open = "";
            dnd-none = "";
            dnd-notification = "<span foreground='red'><sup></sup></span>";
            inhibited-notification = "<span foreground='red'><sup></sup></span>";
            inhibited-none = "";
            dnd-inhibited = "<span foreground='red'><sup></sup></span>";
            dnd-inhibited-none = "";
          };
          return-type = "json";
          exec = "swaync-client -swb";
          on-click = "swaync-client -t -sw";
          on-click-right = "swaync-client -d -sw";
          escape = true;
        };

        "custom/clipboard" = {
          format = "  ";
          interval = "once";
          return-type = "json";
          on-click = "cliphist list | fuzzel --dmenu | cliphist decode | wl-copy";
          tooltip = false;
        };

        "wlr/taskbar" = {
          format = "{icon}";
          tooltip-format = "{name} | {title}";
          on-click = "activate";
        };

        bluetooth = {
          format-on = " 󰂯 ";
          format-off = " 󰂲 ";
          format-disabled = " 󰂲 ";
          format-connected = "  󰂯 ";
          tooltip-format = "{controller_alias}\t{controller_address}";
          tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{num_connections} connected\n\n{device_enumerate}";
          tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
          tooltip-format-enumerate-connected-battery = "{device_alias}\t{device_address}\t{device_battery_percentage}%";
          on-click = "blueman-manager";
          on-click-right = "rfkill toggle bluetooth";
        };
      };
    };
  };

  systemd.user.services.waybar = lib.mkIf config.programs.waybar.enable {
    Unit = {
      After = [
        "pipewire.service"
        "wireplumber.service"
      ];
      Requires = [
        "pipewire.service"
        "wireplumber.service"
      ];
    };
  };

  # The bar. Replaces Waybar, whose taskbar cannot show window previews;
  # see .copilot/plans/quickshell-bar.md.
  home.packages = [ pkgs.quickshell ];

  xdg.configFile."quickshell/bar" = {
    source = ./quickshell;
    # home-manager only restarts a unit when its *definition* changes, so a pure
    # QML change would otherwise leave the running bar on the old config until
    # the next login — the same reason the swaync stylesheet above needs a hook.
    onChange = "${pkgs.systemd}/bin/systemctl --user restart quickshell-bar.service || true";
  };

  systemd.user.services.quickshell-bar = {
    Unit = {
      Description = "Quickshell bar";
      PartOf = [ "graphical-session.target" ];
      After = [
        "graphical-session.target"
        "pipewire.service"
        "wireplumber.service"
      ];
      # The audio modules render nothing without PipeWire.
      Requires = [
        "pipewire.service"
        "wireplumber.service"
      ];
    };
    Service = {
      ExecStart = "${pkgs.quickshell}/bin/qs -c bar";
      Environment = [
        # Qt does not read the GTK icon theme, so window icons fall back to
        # unthemed names without this.
        "QS_ICON_THEME=${config.gtk.iconTheme.name}"
        # Store paths for the status scripts, which are not on PATH.
        "TRAY_ACTIVATION_PROBE=${tray-activation-probe}/bin/tray-activation-probe"
        "AUDIO_MODE_BIN=${config.mine.audio.package}/bin/audio-mode"
        "AUDIO_MODE_CONFIG=${config.mine.audio.configFile}"
      ]
      # Gated, so a host without the corporate integration gets no VPN
      # section at all rather than one whose Connect button starts a
      # `corpnet-vpn` unit that does not exist. `VpnState.available` keys off
      # this variable being absent, which is the mechanism its own comment
      # always described but which nothing previously enforced -- every
      # `mine.msft-corp.corpnet.*` option has a default, so the indicator
      # always built and the variable was always set.
      ++ lib.optional config.mine.msft-corp.enable
        "CORPNET_VPN_INDICATOR=${corpnet-vpn-indicator}/bin/corpnet-vpn-indicator"
      # Gated on the `easyeffects` user service actually being defined --
      # the honest signal that EasyEffects is in use on this host, rather
      # than a redundant `mine.audio.easyeffects.enable` flag duplicating
      # it. `EffectsState.available` keys off this variable being absent, the
      # same pattern `VpnState`/`CORPNET_VPN_INDICATOR` use just above.
      ++ lib.optional (config.systemd.user.services ? easyeffects)
        "EASYEFFECTS_PRESET=${config.mine.audio.easyeffectsPresetPackage}/bin/easyeffects-preset";
      Restart = "on-failure";
      RestartSec = 2;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}

{ pkgs, ... }:

{
  services.swaync = {
    enable = true;
    settings = {
      notification-2fa-action = true;
      notification-inline-replies = true;
      keyboard-shortcuts = false;
      widgets = [
        "inhibitors"
        "title"
        "dnd"
        "notification"
        "mpris"
        "volume"
      ];

      widget-config = {
        mpris = {
          autohide = true;
        };

        volume = {
          show-per-app = true;
          show-per-app-icon = true;
        };
      };
    };
  };

  home.file.".config/swaync/style.css".source = ./swaync-style.css;

  programs.yazi = {
    enable = true;
    plugins = with pkgs.yaziPlugins; {
      mount = mount;
      git = git;
      chmod = chmod;
    };

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
      plugin.prepend_fetchers = [
        {
          id = "git";
          name = "*";
          run = "git";
        }
        {
          id = "git";
          name = "*/";
          run = "git";
        }
      ];
      mgr = {
        show_hidden = true;
      };
    };
  };

  programs.waybar = {
    enable = true;
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

        modules-left = [
          "wlr/taskbar"
        ];
        modules-center = [
          "mpris"
        ];
        modules-right = [
          "custom/password"
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

        "custom/password" = {
          format = " 󱕵 ";
          on-click = "1password --quick-access";
          on-click-right = "1password";
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

  systemd.user.services.waybar = {
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
}

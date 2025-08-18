{ pkgs, ... }:

{
  environment.systemPackages = [
    pkgs.networkmanagerapplet
    pkgs.nwg-look
    pkgs.whitesur-gtk-theme
  ];

  systemd.user.services.nm-applet = {
    enable = true;
    description = "NetworkManager Applet";
    wantedBy = [ "graphical-session.target" ];
    after = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.networkmanagerapplet}/bin/nm-applet";
      Restart = "on-failure";
    };
  };

  home-manager.users.cpuguy83.home.pointerCursor = {
    package = pkgs.whitesur-gtk-theme;
    name = "WhiteSur-cursors";
    size = 24;
  };

  home-manager.users.cpuguy83.services.swaync = {
    enable = true;
    settings = {
      notification-2fa-action = true;
      notification-inline-replies = true;
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

  home-manager.users.cpuguy83.programs.waybar = {
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
          "custom/menu"
          "custom/clipboard"
          "pulseaudio"
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

        pulseaudio = {
          format = " {volume}% {icon}  {format_source} ";
          format-bluetooth = " {volume}% {icon}   {format_source} ";
          format-icons = {
            default = [ "" "" "" "" " " ];
            headphones = "";
          };
          format-source = "{volume}% ";
          format-source-muted = "";
          on-click  = "pavucontrol";
        };

        "custom/notification" = {
          tooltip = false;
          format = " {icon}  ";
          format-icons = {
            notification = "<span foreground='red'></span>";
            none = "";
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

        "tray" = {
          spacing = 10;
        };
      };
    };
  };
}

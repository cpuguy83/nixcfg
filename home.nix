{
  pkgs,
  pkgs-unstable,
  inputs,
  lib,
  ...
}:

let
  darkMode = true;
  themeSuffix = if darkMode then "Dark" else "Light";
  colorScheme = if darkMode then "prefer-dark" else "prefer-light";
in
{
  home.stateVersion = "24.11";

  imports = [
    inputs.nixvim.homeModules.nixvim
    inputs.handy.homeManagerModules.default
    inputs.calbar.homeManagerModules.default

    ./modules/home
    ./modules/shared
  ];

  home.pointerCursor = {
    enable = true;
    package = pkgs.whitesur-cursors;
    name = "WhiteSur-cursors";
    size = 24;
    gtk.enable = true;
  };

  home.packages = with pkgs; [
    whitesur-gtk-theme
    whitesur-icon-theme
    whitesur-cursors

    gcr

    pkgs-unstable.codex
    pkgs-unstable.claude-code
    opencode

    yubioath-flutter
    teams-for-linux

    protonup-qt
    gamescope

    go
    gcc
    gnumake

    signal-desktop

    pkgs-unstable.docker-buildx
    pkgs-unstable.docker-client

    libnotify # for notify-send (send system notifications)

    easyeffects
  ];

  gtk = {
    enable = true;
    theme = {
      package = pkgs.whitesur-gtk-theme;
      name = "WhiteSur-${themeSuffix}";
    };

    iconTheme = {
      package = pkgs.whitesur-icon-theme;
      name = "WhiteSur-${lib.toLower themeSuffix}";
    };
    cursorTheme = {
      package = pkgs.whitesur-cursors;
      name = "WhiteSur-cursors";
    };
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = colorScheme;
    };
  };

  programs.bash.enable = true;
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
  };

  services.gnome-keyring.enable = true;
  mine.desktop.hyprland.enable = true;
  programs.command-not-found.enable = true;

  services.handy.enable = true;

  services.calbar = {
    enable = true;
    settings = {
      sync = {
        interval = "5m";
        output = "~/.local/share/calbar/calendar.ics";
      };
      sources = [
        {
          name = "CNCF";
          type = "ics";
          url = "https://calendar.google.com/calendar/ical/linuxfoundation.org_o5avjlvt2cae9bq7a95emc4740%40group.calendar.google.com/public/basic.ics";
          filters = {
            mode = "or";
            rules = [
              {
                field = "title";
                contains = "containerd";
                case_insensitive = true;
              }
            ];
          };
        }
        {
          name = "OCI";
          type = "ics";
          url = "https://calendar.google.com/calendar/ical/linuxfoundation.org_i0sado0i37eknar51vsu8md5hg%40group.calendar.google.com/public/basic.ics";
        }
        {
          name = "MSFT";
          type = "ms365";
          filters = {
            rules = [
              {
                field = "title";
                contains = "DTO";
                exclude = true;
                case_insensitive = true;
              }
              {
                field = "title";
                contains = "HHTO";
                exclude = true;
                case_insensitive = true;
              }
              {
                field = "title";
                contains = "OOO";
                exclude = true;
                case_insensitive = true;
              }
              {
                field = "title";
                contains = "OOF";
                exclude = true;
                case_insensitive = true;
              }
            ];
          };
        }
      ];
      notifications = {
        enabled = true;
        before = [
          "15m"
          "5m"
        ];
      };
      ui = {
        time_range = "168h";
        max_events = 20;
        theme = "system";
      };
    };
  };
}

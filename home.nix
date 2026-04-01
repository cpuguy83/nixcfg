{
  config,
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
    inputs.handy-mine.homeManagerModules.default
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
    (pkgs.symlinkJoin {
      name = "opencode-wrapped";
      paths = [ pkgs.opencode ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/opencode \
          --prefix PATH : "${
            pkgs.lib.makeBinPath [
              pkgs.python3
              pkgs.file
              pkgs.ripgrep
              pkgs.fd
              pkgs.jq
              pkgs.tree
              pkgs.curl
              pkgs.bat
            ]
          }"
      '';
    })
    (pkgs.symlinkJoin {
      name = "github-copilot-cli-wrapped";
      paths = [ pkgs-unstable.github-copilot-cli ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/copilot \
          --prefix LD_LIBRARY_PATH : "${
            pkgs.lib.makeLibraryPath [
              pkgs.libsecret
              pkgs.glib
              pkgs.stdenv.cc.cc.lib
              pkgs.openssl
            ]
          }"
      '';
    })

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
    helvum

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

  programs.ghostty = {
    enable = true;
    enableBashIntegration = true;
  };

  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
  };

  services.gnome-keyring.enable = true;
  mine.desktop.hyprland.enable = true;
  programs.command-not-found.enable = true;

  systemd.user.sessionVariables.GITSIGN_CREDENTIAL_CACHE = "${config.xdg.cacheHome}/sigstore/gitsign/cache.sock";

  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Brian Goff";
        email = "cpuguy83@gmail.com";
      };
      commit.gpgsign = false;
      tag.gpgsign = false;
      gpg.format = "x509";
      gpg."x509".program = "${pkgs.gitsign}/bin/gitsign";
      gitsign.connectorID = "https://github.com/login/oauth";
      safe.directory = "/etc/nixos";
      init.defaultBranch = "main";
      grep.linenumber = true;
      branch.sort = "-committerdate";
      url."ssh://git@github.com/".insteadOf = "https://github.com/";
    };
  };

  programs.diff-so-fancy = {
    enable = true;
    enableGitIntegration = true;
  };

  systemd.user.services.gitsign-credential-cache = {
    Unit.Description = "Gitsign credential cache";
    Install.WantedBy = [ "default.target" ];
    Service = {
      ExecStart = "${pkgs.gitsign}/bin/gitsign-credential-cache";
      Restart = "on-failure";
      Environment = "HOME=%h";
    };
  };

  services.handy.enable = true;

  services.calbar = {
    enable = true;
    settings = {
      sync = {
        interval = "10m";
        output = "~/.local/share/calbar/calendar.ics";
      };
      sources = [
        {
          name = "iCloud";
          type = "icloud";
          username_cmd = "op read op://calbar/icloud/username";
          password_cmd = "op read op://calbar/icloud/password";
        }
        {
          name = "Gmail Personal";
          type = "ics";
          url_cmd = "op read op://calbar/gmail-personal/url";
        }
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
              {
                field = "title";
                contains = "maternity";
                exclude = true;
                case_insensitive = true;
              }
              {
                field = "title";
                contains = "paternity";
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

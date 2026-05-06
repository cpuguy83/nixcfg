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
  opRead = ref: "op read ${lib.escapeShellArg ref}";
  calbarExec = pkgs.writeShellScript "calbar-start" ''
    op signin >/dev/null
    # Keep this in ExecStart, not ExecStartPre, to avoid a second 1Password auth prompt.
    exec ${pkgs.calbar}/bin/calbar
  '';
in
{
  home.stateVersion = "24.11";
  news.display = "silent";

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
    mactahoe-gtk-theme
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

    pkgs-unstable.go
    pkgs-unstable.golangci-lint
    gcc
    gnumake

    signal-desktop

    pkgs-unstable.docker-buildx
    pkgs-unstable.docker-client

    libnotify # for notify-send (send system notifications)

    easyeffects
    helvum

    nix-unwrap
  ];

  gtk = {
    enable = true;
    theme = {
      package = pkgs.mactahoe-gtk-theme;
      name = "MacTahoe-${themeSuffix}";
    };

    iconTheme = {
      package = pkgs.whitesur-icon-theme;
      name = "WhiteSur-${lib.toLower themeSuffix}";
    };
    cursorTheme = {
      package = pkgs.whitesur-cursors;
      name = "WhiteSur-cursors";
    };

    gtk3.extraCss = builtins.readFile ./gtk-3.0.css;
    gtk4.extraCss = builtins.readFile ./gtk-4.0.css;

  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = colorScheme;
      font-antialiasing = "grayscale";
    };
  };

  programs.bash.enable = true;

  programs.ghostty = {
    enable = true;
    enableBashIntegration = true;
    systemd.enable = false;
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

      # hack used for fetching private go mods
      # url."ssh://git@github.com/".insteadOf = "https://github.com/";
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
  services.vekil.enable = true;

  systemd.user.services."1password" = {
    Unit = {
      Description = "1Password desktop app";
      PartOf = [ "graphical-session.target" ];
      After = [
        "graphical-session.target"
        "xdg-desktop-autostart.target"
      ];
    };
    Service = {
      ExecStart = "${pkgs._1password-gui}/bin/1password --silent";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.easyeffects = {
    Unit = {
      Description = "EasyEffects audio effects";
      PartOf = [ "graphical-session.target" ];
      After = [
        "graphical-session.target"
        "xdg-desktop-autostart.target"
      ];
    };
    Service = {
      ExecStart = "${pkgs.easyeffects}/bin/easyeffects --hide-window";
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  services.calbar = {
    enable = true;
    css = builtins.readFile ./calbar-style.css;
    settings = {
      sync = {
        interval = "10m";
        output = "~/.local/share/calbar/calendar.ics";
      };
      sources = [
        {
          name = "iCloud";
          type = "icloud";
          username_cmd = opRead "op://calbar/icloud/username";
          password_cmd = opRead "op://calbar/icloud/password";
        }
        {
          name = "Gmail Personal";
          type = "ics";
          url_cmd = opRead "op://calbar/gmail-personal/url";
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
          "5m"
          "0s"
        ];
      };
      ui = {
        time_range = "168h";
        max_events = 20;
        theme = "system";
      };
    };
  };

  systemd.user.services.calbar = {
    Unit = {
      Wants = [ "1password.service" ];
      After = lib.mkAfter [
        "1password.service"
        "xdg-desktop-autostart.target"
        "waybar.service"
      ];
      StartLimitIntervalSec = 0;
    };
    Service = {
      ExecStart = lib.mkForce calbarExec;
      Restart = lib.mkForce "always";
      RestartSec = lib.mkForce 30;
    };
  };

  programs.obs-studio = {
    enable = true;
    plugins = with pkgs.obs-studio-plugins; [
      wlrobs
      obs-pipewire-audio-capture
      obs-backgroundremoval
      obs-mute-filter
      obs-vkcapture
    ];
  };
}

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

  # The GitHub Copilot desktop app's "Open in app" feature invokes a custom
  # app as `<binary> <path>`. ghostty is not in the app's built-in launcher
  # catalog and its CLI only accepts the working directory as
  # `--working-directory=<path>`, so this wrapper adapts the positional path
  # into the flag ghostty expects.
  ghostty-open = pkgs.writeShellApplication {
    name = "ghostty-open";
    runtimeInputs = [ pkgs.ghostty ];
    text = ''
      dir="''${1:-$PWD}"
      exec ghostty --working-directory="$dir"
    '';
  };

  # Run claude/codex against the local vekil proxy (GitHub Copilot backend)
  # instead of the real Anthropic/OpenAI APIs. vekil listens on localhost:1337
  # and doesn't check the API key, so a dummy value is used.
  codex-proxied = pkgs.writeShellApplication {
    name = "codex-proxied";
    runtimeInputs = [ pkgs-unstable.codex ];
    text = ''
      exec codex \
        -c 'model_provider="proxy"' \
        -c 'model_providers.proxy.name="Local Proxy"' \
        -c 'model_providers.proxy.base_url="http://localhost:1337/v1"' \
        "$@"
    '';
  };

  # The Codex Claude Code plugin hardcodes the binary name `codex` (it runs
  # `codex app-server` and `codex --version`) and offers no setting to point at
  # a different one, so under plain claude-proxied it would bypass vekil and hit
  # the real OpenAI API. Expose the proxied wrapper under that name instead.
  # Deliberately kept out of home.packages: this only shadows `codex` inside
  # claude-proxied's PATH, so a normal shell still gets the unproxied CLI.
  codex-proxied-shim = pkgs.runCommand "codex-proxied-shim" { } ''
    mkdir -p "$out/bin"
    ln -s ${codex-proxied}/bin/codex-proxied "$out/bin/codex"
  '';

  claude-proxied = pkgs.writeShellApplication {
    name = "claude-proxied";
    runtimeInputs = [
      pkgs-unstable.claude-code
      codex-proxied-shim
    ];
    text = ''
      export ANTHROPIC_BASE_URL="http://localhost:1337"
      export ANTHROPIC_API_KEY="dummy"
      exec claude "$@"
    '';
  };
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

    github-copilot
    ghostty-open

    # discord
    # legcord

    # Just needed for copilot
    nodejs_24

    pkgs-unstable.codex
    pkgs-unstable.claude-code
    claude-proxied
    codex-proxied
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

    # Handy looks up its text-input tool via PATH at runtime. Its "launch at
    # login" feature writes an autostart entry pointing at the unwrapped binary,
    # bypassing the wtype-in-PATH wrapper, so keep wtype on the ambient PATH too.
    wtype

    easyeffects
    crosspipe

    nix-unwrap

    cider-2 # Apple music player

    lmstudio
  ];

  programs.vscodium = {
    enable = true;
    # Store secrets in the GNOME keyring via libsecret instead of the
    # plaintext "basic" store, so tokens (e.g. sign-in) are encrypted.
    #
    # enable-crash-reporter must be set explicitly: on first run VSCodium tries
    # to inject this key (plus a generated crash-reporter-id) into argv.json,
    # but home-manager makes that file a read-only /nix/store symlink, so the
    # write fails and is surfaced as "argv.json contains errors". Pinning it
    # (false, matching VSCodium's telemetry-off default) skips that rewrite.
    argvSettings = {
      password-store = "gnome-libsecret";
      enable-crash-reporter = false;
    };
    profiles.default.extensions = with pkgs.vscode-extensions; [
      golang.go
      vscodevim.vim
      rust-lang.rust-analyzer
      github.vscode-github-actions
      redhat.vscode-yaml
      ms-kubernetes-tools.dalec-vscode-tools
    ];
  };

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
    gtk4 = {
      theme = config.gtk.theme;
      extraCss = builtins.readFile ./gtk-4.0.css;
    };

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

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."github.com" = {
      ControlMaster = "auto";
      ControlPath = "~/.ssh/cm-%r@%h:%p";
      ControlPersist = "10m";
    };

    settings."*" = {
      IdentityAgent = "~/.1password/agent.sock";
    };
  };

  programs.git = {
    enable = true;
    ignores = [
      ".vscode"
      ".idea"
      ".vim-lsp-settings"
      ".zed"
      ".cache"
      ".opencode"
      ".copilot"
      ".claude"
    ];

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
      extracConfig = {
        credential = {
          helper = "manager-core";
          azreposCredentialType = "oauth";
          msauthFlow = "browser";
        };

        "credential \"https://dev.azure.com\"" = {
          useHttpPath = true;
        };
      };
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
          name = "containerd";
          type = "ics";
          url = "https://webcal.prod.itx.linuxfoundation.org/lfx/a092M00001IV436QAD";
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
        "quickshell-bar.service"
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

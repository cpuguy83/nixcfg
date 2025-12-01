{
  pkgs,
  pkgs-unstable,
  inputs,
  ...
}:

{
  home.stateVersion = "24.11";

  imports = [
    inputs.nixvim.homeModules.nixvim
    ./modules/home
    ./modules/shared
  ];

  # config.desktop.de = "hyprland";

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

    yubioath-flutter
    teams-for-linux

    protonup-qt
    gamescope
  ];

  programs.starship = {
    enable = true;
    enableBashIntegration = true;
    settings = {
      add_newline = true;
      palette = "lcars";

      palettes = {
        lcars = {
          panel = "#1b1d2b";
          amber = "#ffb869";
          rose = "#ff80aa";
          cyan = "#8cf0ff";
          text = "#f8f6f2";
          dim = "#5e6272";
          alert = "#ff5f56";
          success = "#8cf08c";
        };
      };

      format = ''
        $nix_shell$directory$git_branch$fill$cmd_duration$status$time
        $line_break$character
      '';

      fill.symbol = " ";

      nix_shell = {
        heuristic = true;
        symbol = " ";
        style = "fg:panel bg:amber";
        format = "[](fg:amber)[ $symbol$name ]($style)[](fg:amber bg:rose)";
      };

      directory = {
        truncation_length = 3;
        truncate_to_repo = false;
        style = "fg:panel bg:rose";
        repo_root_style = "fg:panel bg:rose";
        format = "[  $path ]($style)[](fg:rose)";
      };

      git_branch = {
        symbol = "";
        style = "fg:panel bg:cyan";
        format = "[](fg:rose bg:cyan)[ $symbol $branch ]($style)[](fg:cyan)";
      };

      status = {
        disabled = false;
        style = "fg:panel bg:alert";
        map_symbol = true;
        pipestatus = true;
        recognize_signal_code = true;
        format = "[](fg:alert)[ ✖ $status ]($style)[](fg:alert)";
        pipestatus_format = "[](fg:alert)[ ✖ $pipestatus ]($style)[](fg:alert)";
      };

      cmd_duration = {
        min_time = 750;
        style = "fg:panel bg:dim";
        format = "[](fg:dim)[  $duration ]($style)[](fg:dim bg:amber)";
      };

      time = {
        disabled = false;
        use_12hr = false;
        time_format = "%H:%M";
        style = "fg:panel bg:amber";
        format = "[  $time ]($style)[](fg:amber)";
      };

      character = {
        format = "$symbol ";
        success_symbol = "[❯](bold fg:success)";
        error_symbol = "[❯](bold fg:alert)";
        vicmd_symbol = "[❮](bold fg:rose)";
      };
    };
  };

  gtk = {
    enable = true;
    theme = {
      package = pkgs.whitesur-gtk-theme;
      name = "WhiteSur-Light";
    };

    iconTheme = {
      package = pkgs.whitesur-icon-theme;
      name = "WhiteSur-Light";
    };
    cursorTheme = {
      package = pkgs.whitesur-cursors;
      name = "WhiteSur-cursors-light";
    };
  };

  services.gnome-keyring.enable = true;
  mine.desktop.hyprland.enable = true;
}

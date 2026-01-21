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
  ];

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

  programs.bash.enable = true;
  programs.fzf = {
    enable = true;
    enableBashIntegration = true;
  };

  services.gnome-keyring.enable = true;
  mine.desktop.hyprland.enable = true;
  programs.command-not-found.enable = true;
}

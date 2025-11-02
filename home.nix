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

    pkgs-unstable.codex
    pkgs-unstable.claude-code
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

  services.gnome-keyring.enable = true;
  mine.desktop.hyprland.enable = true;
}

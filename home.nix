{ pkgs, pkgs-unstable, ... }:

{
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
}

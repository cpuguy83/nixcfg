{ pkgs-unstable, ... }:

{
  programs.hyprlock = {
    package = pkgs-unstable.hyprlock;
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
      };
      label = [
        {
          monitor = "DP-1";
          color = "rgba(242, 243, 244, 0.75)";
          text = "$TIME";
          position = "0, 300";
          font_size = 95;
          font_family = "JetBrains Mono Nerd Font";
          halign = "center";
          valign = "center";
        }
      ];
      background = [
        {
          monitor = "";
          path = "screenshot";
          blur_passes = 3;
          blur_size = 7;
          brightness = 0.5;
          vibrancy = 0.2;
          vibrancy_darkness = 0.2;
        }
      ];
      input-field = {
        monitor = "DP-1";
        hide_input = false;
        placeholder_text = "Enter password";
        fade_on_empty = false;
      };
    };
  };
}

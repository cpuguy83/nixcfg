{
  pkgs-unstable,
  lib,
  config,
  ...
}:
let
  cfg = config.mine.desktop.hyprland;
  lockMonitorAttrs = lib.optionalAttrs (cfg.lockScreenMonitor != null) { monitor = cfg.lockScreenMonitor; };
in
{
  programs.hyprlock = {
    package = pkgs-unstable.hyprlock;
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
      };
      label = [
        ({
          color = "rgba(242, 243, 244, 0.75)";
          text = "$TIME";
          position = "0, 300";
          font_size = 95;
          font_family = "JetBrains Mono Nerd Font";
          halign = "center";
          valign = "center";
        } // lockMonitorAttrs)
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
      input-field =
        {
          hide_input = false;
          placeholder_text = "Enter password";
          fade_on_empty = false;
        }
        // lockMonitorAttrs;
    };
  };
}

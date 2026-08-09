{ ... }:

{
  imports = [
    ./shared.nix
  ];

  mine.desktop.hyprland.monitors = [
    {
      output = "DP-1";
      mode = "preferred";
      position = "2160x840";
      scale = "1";
    }
    {
      output = "DP-2";
      mode = "preferred";
      position = "0x0";
      scale = "1";
      transform = 3;
    }

    # These are used as backchannels to DP-1 and DP-2 for DDC/CI
    {
      output = "HDMI-A-1";
      disabled = true;
    }
    {
      output = "HDMI-A-3";
      disabled = true;
    }
  ];

  mine.desktop.hyprland.lockScreenMonitor = "DP-1";

  mine.desktop.hyprland.workspaces = [
    {
      workspace = "m[DP-2]";
      layout_opts = {
        direction = "down";
      };
    }
  ];

  mine.desktop.hyprland.layout = "scrolling";

  home.sessionVariables = {
    PROTON_ENABLE_WAYLAND = "1";
    PROTON_ENABLE_HDR = "1";
    ENABLE_HDR_WSI = "1";
  };
}

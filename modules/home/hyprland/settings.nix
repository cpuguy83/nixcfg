{
  pkgs,
  pkgs-unstable,
  lib,
  config,
  brightnessPath,
  getMonitorPath,
  ...
}:
let
  # plugins = inputs.hyprland-plugins.packages.${pkgs.stdenv.hostPlatform.system};
  cfg = config.mine.desktop.hyprland;
in
{
  home.file.".local/bin/exec_yazi" = {
    text = ''
      #!/usr/bin/env bash
      source ~/.bashrc
      exec ${pkgs.yazi}/bin/yazi "$@"
    '';
    executable = true;
  };

  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;

    plugins = with pkgs-unstable.hyprlandPlugins; [
      # hyprbars
      pkgs.hyprtasking
    ];

    settings = {
      ecosystem = {
        no_donation_nag = true;
      };
      "$mod" = "SUPER";

      "$terminal" = "ghostty +new-window";
      # ghostty +new-windows does not work with `-e` in GTK-land.
      # Instead just execute a new ghostty.
      # See https://github.com/ghostty-org/ghostty/issues/8862
      "$file_manager" = "uwsm app -- ghostty --class=yazi --title=yazi -e ~/.local/bin/exec_yazi";

      "$cursor" = "WhiteSur-cursors-light";
      "$cursor_size" = "24";
      exec-once = [
        "$terminal"
        "hyprctl setcursor $cursor $cursor_size"
        # "uwsm app -- wl-paste --type text --watch cliphist store"
        # "uwsm app -- wl-paste --type image --watch cliphist store"
      ];
      general = {
        resize_on_border = true;
        hover_icon_on_border = true;
        gaps_out = 6;
        gaps_in = 4;
      };
      monitor = lib.mkDefault cfg.monitors;

      render = {
        cm_auto_hdr = 2;
      };

      "$menu" = "uwsm app -- fuzzel";
      bind = [
        "$mod SHIFT, Q, exec, $terminal"
        "$mod, Q, killactive,"
        "$mod, M, exit,"
        "$mod, SPACE, exec, $menu"
        "$mod, P, pseudo,"
        "$mod, J, togglesplit,"
        "$mod, E, exec, $file_manager"
        "$mod, L, exec, hyprlock"
        # "$mod, TAB, hyprexpo:expo, toggle"
        "$mod, TAB, hyprtasking:toggle, all"
        "SHIFT $mod, 4, exec, hyprshot -m region --clipboard-only --silent -z"
        "CTRL SHIFT $mod, 4, exec, hyprshot -m region -o ~/Pictures/Screenshots --silent -z -- xdg-open"
        "SHIFT $mod, m, exec, swaync-client -t"
        "SHIFT $mod, v, exec, hyprctl dispatch togglefloating"
        "SHIFT $mod, p, exec, 1password --quick-access"
        "$mod, F11, fullscreen"
        "$mod SHIFT, SPACE, exec, pkill -USR2 -n handy"
      ];

      bindm = [
        "SUPER, mouse:272, movewindow" # SUPER+left click to drag windows
        "SUPER, mouse:273, resizewindow" # SUPER+right click to resize
      ];

      env = [
        "HYPRCURSOR_THEME,$cursor"
        "HYPRCURSOR_SIZE,$cursor_size"
        "XCURSOR_THEME,$cursor"
        "XCURSOR_SIZE,$cursor_size"
        "XDG_CURRENT_DESKTOP,Hyprland"
      ];

      bindle = [
        ", XF86AudioRaiseVolume, exec, swayosd-client --output-volume raise"
        ", XF86AudioLowervolume, exec, swayosd-client --output-volume lower"
        ", XF86AudioMute, exec, swayosd-client --output-volume mute-toggle"
        ", XF86AudioMicMute, exec, swayosd-client --input-volume mute-toggle"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86MonBrightnessUp, exec, ${brightnessPath} up $(${getMonitorPath}) 4"
        ", XF86MonBrightnessDown, exec, ${brightnessPath} down $(${getMonitorPath}) 4"
      ];

      windowrule = [
        "match:title ^(yazi)$, float on, size (monitor_w*0.4) (monitor_h*0.4)"
        "match:class ^com\\.mitchellh\\.ghostty\\.filepicker$, float on, size (monitor_w*0.4) (monitor_h*0.4)"
        "match:class (microsoft-azurevpnclient), float on"
        "match:class ^(steam)$, match:title ^(Steam)$, float on, size (monitor_w*0.4) (monitor_h*0.6)"
        "match:class ^(Intune-portal)$, float on, size (monitor_w*0.35) (monitor_h*0.35)"
        "match:class ^(org\\.hyprland\\.xdg-desktop-portal-hyprland)$, float on, size (monitor_w*0.4) (monitor_h*0.4)"

        # NOTE: The zoom app sucks, and so do these rules...
        # Zoom Meeting windows
        "match:class ^(zoom)$, match:initial_title ^(Meeting)$, float on, size (monitor_w*0.4) (monitor_h*0.4)"
        # Stupid Zoom workplace window that always comes up when you open zoom...
        "match:class ^(zoom)$ match:initial_title ^(Zoom Workplace - Free account)$, float on, size (monitor_w*40) (monitor_h*0.4)"
        "no_vrr match:class ^(steam|zoom|Zoom|teams|discord)"
      ];

      layerrule = [
        "animation popin 90%, match:namespace launcher"
        "animation slide right, match:namespace swaync-notification-window"
        "animation slide right, match:namespace swaync-control-center"
        "blur on, match:namespace swaync-control-center"
        "ignore_alpha 0.3, match:namespace swaync-control-center"
        "blur on, match:namespace swaync-notification-window"
        "ignore_alpha 0.3, match:namespace swaync-notification-window"
        "blur on, match:namespace waybar"
        "blur_popups on, match:namespace waybar"
        "ignore_alpha 0.3, match:namespace waybar"
      ];

      # Bezier curves
      bezier = [
        "smoothOut, 0.36, 0, 0.66, -0.56"
        "smoothIn, 0.25, 1, 0.5, 1"
        "overshot, 0.05, 0.9, 0.1, 1.05"
        "softSnap, 0.4, 0, 0.2, 1"
        "fluent, 0.0, 0.0, 0.2, 1.0"
        "easeInOutExpo, 0.87, 0, 0.13, 1"
      ];

      animation = [
        # Windows
        "windows, 1, 3, overshot, popin 80%"
        "windowsIn, 1, 3, overshot, popin 80%"
        "windowsOut, 1, 2, softSnap, popin 95%"
        "windowsMove, 1, 2, softSnap"
        # Layers - defaults; swaync overridden to slide right via layerrule
        "layersIn, 1, 3, smoothIn"
        "layersOut, 1, 4, softSnap"
        # Fade
        "fade, 1, 2, smoothIn"
        "fadeIn, 1, 2, smoothIn"
        "fadeOut, 1, 2, softSnap"
        "fadeSwitch, 1, 2, smoothIn"
        "fadeShadow, 1, 2, smoothIn"
        "fadeDim, 1, 2, smoothIn"
        "fadeDpms, 1, 2, smoothIn"
        "fadeLayers, 1, 2, softSnap"
        # Workspaces
        "workspaces, 1, 5, softSnap, slidefade 30%"
        "specialWorkspace, 1, 5, softSnap, slidefadevert 30%"
      ];

      decoration = {
        rounding = 16;
        rounding_power = 4;
        active_opacity = 1.0;
        inactive_opacity = 1.0;

        shadow = {
          enabled = true;
          range = 4;
          render_power = 3;
          color = "rgba(1a1a1aee)";
        };

        blur = {
          enabled = true;

          size = 4;
          passes = 2;
          vibrancy = "0.1696";
          popups = true;
          popups_ignorealpha = 0.3;
        };
      };

      plugin.hyprbars = {
        bar_blur = true;
        bar_part_of_window = true;
        bar_precedence_over_border = true;
      };

      plugin.hyprexpo = {
        workspace_method = "current";
        skip_empty = true;
      };

      misc = {
        focus_on_activate = true;
        vrr = 3;
      };
    };
  };
}

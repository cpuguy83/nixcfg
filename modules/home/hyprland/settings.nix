{
  pkgs,
  lib,
  config,
  brightnessPath,
  getMonitorPath,
  ...
}:
let
  # plugins = inputs.hyprland-plugins.packages.${pkgs.stdenv.hostPlatform.system};
  cfg = config.mine.desktop.hyprland;

  # swayosd-client --input-volume mute-toggle is broken in swayosd 0.3.1:
  # it reads the source mute state correctly but writes the toggle to the
  # output (sink) device due to a bug in the pulsectl-rs SourceController, so
  # the mic mute never actually flips. Toggle directly via wpctl instead and
  # reuse swayosd's custom-message OSD for the on-screen indicator.
  micMuteToggle = pkgs.writeShellApplication {
    name = "swayosd-mic-mute-toggle";
    runtimeInputs = [
      pkgs.wireplumber
      pkgs.swayosd
      pkgs.gnugrep
    ];
    text = ''
      wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
      if wpctl get-volume @DEFAULT_AUDIO_SOURCE@ | grep -q MUTED; then
        swayosd-client --custom-icon microphone-sensitivity-muted-symbolic --custom-message "Microphone muted"
      else
        swayosd-client --custom-icon microphone-sensitivity-high-symbolic --custom-message "Microphone on"
      fi
    '';
  };
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
    configType = "hyprlang";

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
      ];

      general = {
        resize_on_border = false;
        hover_icon_on_border = false;
        gaps_out = 6;
        gaps_in = 6;

        layout = lib.mkDefault cfg.layout;
      };

      monitor = lib.mkDefault cfg.monitors;

      workspace = lib.mkDefault cfg.workspaces;

      scrolling = {
        fullscreen_on_one_column = false;
      };

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
        "$mod, J, layoutmsg, togglesplit,"
        "$mod, E, exec, $file_manager"
        "$mod, L, exec, hyprlock"
        # Alt+Tab enters a submap so that releasing Alt can be bound without
        # capturing Alt globally: a bare `bind = , Alt_L` consumes the key for
        # every application. The submap itself lives in extraConfig.
        "ALT, TAB, global, quickshell:switcherNext"
        "ALT, TAB, submap, switcher"
        "ALT SHIFT, TAB, global, quickshell:switcherPrev"
        "ALT SHIFT, TAB, submap, switcher"
        # The overview is a toggle rather than a hold, so it needs none of the
        # switcher's submap handling — nothing here has to survive a key release.
        "$mod, TAB, global, quickshell:overviewToggle"
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

      binds = {
        drag_threshold = 8;
      };

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
        ", XF86AudioMicMute, exec, ${lib.getExe micMuteToggle}"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86MonBrightnessUp, exec, ${brightnessPath} up $(${getMonitorPath}) 4"
        ", XF86MonBrightnessDown, exec, ${brightnessPath} down $(${getMonitorPath}) 4"
      ];

      windowrule = [
        "match:title ^(yazi)$, float on, size (monitor_w*0.4) (monitor_h*0.4)"
        "match:class ^com\\.mitchellh\\.ghostty\\.filepicker$, float on, size (monitor_w*0.4) (monitor_h*0.4)"
        "match:class (microsoft-azurevpnclient), float on"
        "match:class ^(steam)$, match:title ^(Steam)$, size (monitor_w*0.4) (monitor_h*0.6)"
        "match:class ^(Intune-portal)$, float on, size (monitor_w*0.35) (monitor_h*0.35)"
        "match:class ^(org\\.hyprland\\.xdg-desktop-portal-hyprland)$, float on, size (monitor_w*0.4) (monitor_h*0.4)"
        "opacity 0.85 0.85, match:class ^(polkit-gnome-authentication-agent-1)$"
        "opacity 0.85 0.85, match:class ^(1password)$, match:float true"

        # NOTE: The zoom app sucks, and so do these rules...
        # Zoom Meeting windows
        "match:class ^(zoom)$, match:initial_title ^(Meeting)$, float on, size (monitor_w*0.4) (monitor_h*0.4)"
        # Stupid Zoom workplace window that always comes up when you open zoom...
        "match:class ^(zoom)$ match:initial_title ^(Zoom Workplace - Free account)$, float on, size (monitor_w*40) (monitor_h*0.4)"
        "no_vrr match:class ^(steam|zoom|Zoom|teams|discord)"
      ];

      layerrule = [
        "animation popin 90%, match:namespace launcher"
        "blur on, match:namespace launcher"
        "ignore_alpha 0.3, match:namespace launcher"
        "animation slide right, match:namespace swaync-notification-window"
        "animation slide right, match:namespace swaync-control-center"
        "blur on, match:namespace swaync-control-center"
        "ignore_alpha 0.3, match:namespace swaync-control-center"
        "blur on, match:namespace swaync-notification-window"
        "ignore_alpha 0.3, match:namespace swaync-notification-window"
        # Waybar is disabled in favour of the Quickshell bar; these are kept so
        # re-enabling it is a one-line change.
        "blur on, match:namespace waybar"
        "blur_popups on, match:namespace waybar"
        "ignore_alpha 0.3, match:namespace waybar"
        "blur on, match:namespace quickshell-bar"
        "blur_popups on, match:namespace quickshell-bar"
        "ignore_alpha 0.3, match:namespace quickshell-bar"
        # The switcher's layer surface covers the whole screen so the carousel
        # can float over it, so ignore_alpha is doing real work here: without it
        # blur would apply to the entire output rather than just the card strip.
        "blur on, match:namespace quickshell-switcher"
        "ignore_alpha 0.3, match:namespace quickshell-switcher"
        # Same deal for the overview: its surface covers the whole output, so
        # without the threshold every pixel of the screen would be blurred
        # instead of just the panel.
        "blur on, match:namespace quickshell-overview"
        "ignore_alpha 0.3, match:namespace quickshell-overview"
        "blur on, match:namespace calbar-popup"
        "ignore_alpha 0.3, match:namespace calbar-popup"
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

      misc = {
        focus_on_activate = true;
        vrr = 3;
      };
    };

    # Submaps are order-sensitive — every bind between `submap = switcher` and
    # `submap = reset` belongs to it — so they cannot be expressed through the
    # unordered `settings` attrset.
    extraConfig = ''
      submap = switcher
      bind    = ALT, TAB, global, quickshell:switcherNext
      bind    = ALT SHIFT, TAB, global, quickshell:switcherPrev
      # `u` (submapUniversal) is required, not cosmetic. handleKeybinds matches a
      # bind's submap against `key.submapAtPress.name` — the submap recorded when
      # the key went DOWN — and Alt goes down before Tab enters this submap, so
      # without `u` nothing fires on release and the keyboard stays trapped here.
      #
      # The cost is that `u` skips the submap check entirely, so this fires on
      # every Alt release anywhere. It therefore has to stay side-effect free: no
      # `submap, reset` here. Switcher.close() resets the submap itself, and only
      # when the switcher was actually open. Hyprland cannot express "only on
      # release inside this submap" — the guard has to live in the client.
      bindru = ALT, Alt_L, global, quickshell:switcherAccept
      bindru = ALT, Alt_R, global, quickshell:switcherAccept
      # `i` (ignoreMods) because Alt is still held: the modmask is still ALT when
      # the release is dispatched, so a bare `, escape` (modmask 0) would never
      # match. Escape is pressed inside the submap, so it needs no `u` — and it
      # dispatches the reset directly, which keeps it working as the escape hatch
      # even if Quickshell is not running.
      bindi  = , escape, global, quickshell:switcherCancel
      bindi  = , escape, submap, reset
      submap = reset
    '';
  };
}

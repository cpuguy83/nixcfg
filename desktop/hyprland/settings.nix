{
  plugin-packages,
  inputs,
  pkgs,
  ...
}:
{
  home-manager.users.cpuguy83.home.file.".local/bin/exec_yazi" = {
    text = ''
      #!/usr/bin/env bash
      source ~/.bashrc
      exec ${pkgs.yazi}/bin/yazi "$@"
    '';
    executable = true;
  };
  home-manager.users.cpuguy83.wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;

    plugins = with plugin-packages; [
      hyprbars
      hyprexpo
      inputs.hyprtasking.packages.${pkgs.system}.hyprtasking
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
      "$file_manager" = "uwsm app -- ghostty -e ~/.local/bin/exec_yazi";

      "$cursor" = "WhiteSur-cursors-light";
      "$cursor_size" = "24";
      exec-once = [
        "$terminal"
        "uwsm app -- gnome-keyring-daemon --start --components=secrets"
        "uwsm app -- systemctl --user start hyprpolkitagent"
        "hyprctl setcursor $cursor $cursor_size"
        # "uwsm app -- wl-paste --type text --watch cliphist store"
        # "uwsm app -- wl-paste --type image --watch cliphist store"
      ];
      general = {
        resize_on_border = true;
        hover_icon_on_border = true;
      };
      monitor = [
        "DP-1,preferred,auto-right,auto"
        "DP-2,preferred,auto-left,auto"
      ];

      "$menu" = "fuzzel";
      bind = [
        "$mod SHIFT, Q, exec, $terminal"
        "$mod, Q, killactive,"
        "$mod, M, exit,"
        "$mod, SPACE, exec, $menu"
        "$mod, P, pseudo,"
        "$mod, J, togglesplit,"
        "$mod, E, exec, [float; size 40%] $file_manager"
        "$mod, L, exec, hyprlock"
        # "$mod, TAB, hyprexpo:expo, toggle"
        "$mod, TAB, hyprtasking:toggle, all"
        "SHIFT $mod, 4, exec, hyprshot -m region --clipboard-only --silent"
        "CTRL SHIFT $mod, 4, exec, hyprshot -m region -o ~/Pictures/Screenshots --silent -- xdg-open"
        "SHIFT $mod, m, exec, swaync-client -t"
        "SHIFT $mod, v, exec, hyprctl dispatch togglefloating"
        "SHIFT $mod, p, exec, 1password --quick-access"
        "$mod, F11, fullscreen"
      ];

      env = [
        "HYPRCURSOR_THEME,$cursor"
        "HYPRCURSOR_SIZE,$cursor_size"
        "XCURSOR_THEME,$cursor"
        "XCURSOR_SIZE,$cursor_size"
      ];

      bindle = [
        ", XF86AudioRaiseVolume, exec, swayosd-client --output-volume raise"
        ", XF86AudioLowervolume, exec, swayosd-client --output-volume lower"
        ", XF86AudioMute, exec, swayosd-client --output-volume mute-toggle"
        ", XF86AudioMicMute, exec, swayosd-client --input-volume mute-toggle"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86MonBrightnessUp, exec, swayosd-client --brightness +2"
        ", XF86MonBrightnessDown, exec, swayosd-client --brightness -2"
      ];

      windowrule = [
        "float, class:^com\\.mitchellh\\.ghostty\\.filepicker$"
        "size 40% 40%, class:^com\\.mitchellh\\.ghostty\\.filepicker$"
        "float, class:(microsoft-azurevpnclient)"

        "float, class:^(steam)$, title:^(Steam)$"
        "size 60%, class:^(steam)$, title:^(Steam)$"

        # NOTE: The zoom app sucks, and so do these rules...
        # Zoom Meeting windows
        "float, class:^(zoom)$, initialTitle:^(Meeting)$"
        "size 40%, class:^(zoom)$, initialTitle:^(Meeting)$"
        # Stupid Zoom workplace window that always comes up when you open zoom...
        "float, class:^(zoom)$, initialTitle:^(Zoom Workplace - Free account)$"
        "size 40%, class:^(zoom)$, initialTitle:^(Zoom Workplace - Free account)$"
      ];

      decoration = {
        rounding = 10;
        rounding_power = 2;
        active_opacity = 1.0;
        inactive_opacity = 0.95;

        shadow = {
          enabled = true;
          range = 4;
          render_power = 3;
          color = "rgba(1a1a1aee)";
        };

        blur = {
          enabled = true;

          size = 3;
          passes = 2;
          vibrancy = "0.1696";
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
      };
    };
  };
}

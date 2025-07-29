{ pkgs, plugin-packages, ... }:
{
  home-manager.users.cpuguy83.wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;

    plugins = with plugin-packages; [
      hyprbars
      pkgs.hyprlandPlugins.hyprspace
    ];

    settings = {
      ecosystem = {
        "no_donation_nag" = true;
      };
      "$mod" = "SUPER";
      "$terminal" = "uwsm app -- ghostty";
      "exec-once" = [
        "$terminal"
        "uwsm app -- swayosd-server"
        "uwsm app -- gnome-keyring-daemon --start --components=secrets"
        "uwsm app -- swaync"
        "uwsm app -- ashell"
      ];
      general = {
        "resize_on_border" = true;
        "hover_icon_on_border" = true;
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
        "$mod, E, exec, dolphin"
        "$mod, L, exec, hyprlock"
        "$mod, TAB, exec, hyprctl dispatch overview:toggle"
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
          passes = 1;
          vibrancy = "0.1696";
        };
      };
    };
  };
}

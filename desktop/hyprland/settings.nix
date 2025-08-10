{ pkgs, plugin-packages, inputs, ... }:
{
  home-manager.users.cpuguy83.wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = null;

    plugins = with plugin-packages; [
      hyprbars
      inputs.hyprspace.packages.${pkgs.system}.Hyprspace
    ];

    settings = {
      ecosystem = {
        "no_donation_nag" = true;
      };
      "$mod" = "SUPER";
      "$terminal" = "uwsm app -- ghostty";
      "exec-once" = [
        "$terminal"
        "uwsm app -- caelestia-shell"
        "uwsm app -- gnome-keyring-daemon --start --components=secrets"
        "uwsm app -- wl-paste --type text --watch cliphist store"
        "uwsm app -- wl-paste --type image --watch cliphist store"
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
        "SHIFT $mod, 4, exec, hyprshot -m region --clipboard-only"
        "SHIFT $mod, m, exec, swaync-client -t"
        "SHIFT $mod, v, exec, hyprctl dispatch togglefloating"
        "SHIFT $mod, p, exec, 1password --quick-access"
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

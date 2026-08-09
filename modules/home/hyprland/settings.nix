{ pkgs
, lib
, config
, brightnessPath
, getMonitorPath
, ...
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
    configType = "lua";

    # `settings` here holds only `_var` entries: Home Manager's Lua generator
    # renders those as `local` declarations and nothing else, so all actual
    # Hyprland configuration lives in the hand-written settings.lua, appended
    # verbatim via `extraConfig` below. This keeps the Nix side to exactly
    # what it needs to be: the bridge that hands store paths and host data
    # (monitors/workspaces/layout) to the Lua config as plain locals.
    settings = {
      micMuteToggle = {
        _var = lib.getExe micMuteToggle;
      };

      brightnessPath = {
        _var = brightnessPath;
      };

      getMonitorPath = {
        _var = getMonitorPath;
      };

      # `cfg.layout` is nullable; `lib.generators.toLua` converts Nix `null`
      # straight to Lua `nil`, so no special-casing is needed here.
      layout = {
        _var = cfg.layout;
      };

      monitors = {
        _var = cfg.monitors;
      };

      workspaceRules = {
        _var = cfg.workspaces;
      };
    };

    extraConfig = builtins.readFile ./settings.lua;
  };
}

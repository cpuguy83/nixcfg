{ pkgs
, config
, brightnessPath
, getMonitorPath
, ...
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
    configType = "lua";

    # `settings` here holds only `_var` entries: Home Manager's Lua generator
    # renders those as `local` declarations and nothing else, so all actual
    # Hyprland configuration lives in the hand-written settings.lua, appended
    # verbatim via `extraConfig` below. This keeps the Nix side to exactly
    # what it needs to be: the bridge that hands store paths and host data
    # (monitors/workspaces/layout) to the Lua config as plain locals.
    settings = {
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

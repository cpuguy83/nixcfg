# The `audio-mode` CLI, the `easyeffects-preset` CLI, their generated
# descriptor, and the internal handles (`mine.audio.package` /
# `mine.audio.configFile` / `mine.audio.easyeffectsPresetPackage`) that let
# other portable modules (e.g. `modules/home/hyprland/shell.nix`) wire them
# into a unit's `Environment` by store path.
# See .copilot/plans/control-center.md §5, §7, §9.5, §14.
{ config, lib, pkgs, ... }:
let
  cfg = config.mine.audio;

  # One descriptor, consumed by both the CLI and the Quickshell panel
  # (§7) -- so the iD4 monitor list and the latency table are declared once
  # as host data and never independently re-typed.
  modesJson = pkgs.writeText "audio-modes.json" (
    builtins.toJSON {
      latencyModes = cfg.latencyModes;
      rates = cfg.rates;
      quantums = cfg.quantums;
      inputMonitors = map
        (m: {
          inherit (m) id label description;
          node = m.playbackNode;
        })
        cfg.inputMonitors;
    }
  );

  audio-mode = pkgs.writeShellApplication {
    name = "audio-mode";
    runtimeInputs = [
      pkgs.pipewire
      pkgs.jq
      pkgs.gnused
      pkgs.coreutils
      pkgs.util-linux # flock
    ];
    text = ''
      MODES_FILE=${modesJson}
    '' + builtins.readFile ./audio-mode.sh;
  };

  # The EasyEffects preset selector CLI (§9.5): `status`/`load` for the
  # Control Center panel. `easyeffects` itself is a runtime input rather than
  # relying on it being separately on the caller's PATH, since this is what
  # `-a`/`-l` shell out to; `systemd` is for the `easyeffects.service`
  # active-check that gates them (see the script's own header comment for
  # why that check exists at all).
  easyeffects-preset = pkgs.writeShellApplication {
    name = "easyeffects-preset";
    runtimeInputs = [
      pkgs.easyeffects
      pkgs.systemd
      pkgs.jq
      pkgs.gnused
      pkgs.coreutils
    ];
    text = builtins.readFile ./easyeffects-preset.sh;
  };
in
{
  options.mine.audio = {
    package = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
      default = audio-mode;
      description = "The built `audio-mode` CLI, for units that need its store path directly.";
    };

    configFile = lib.mkOption {
      type = lib.types.path;
      internal = true;
      readOnly = true;
      default = modesJson;
      description = ''
        Store path of the generated `audio-modes.json` descriptor. Passed as a
        path (not the JSON itself) through unit `Environment=`, since a value
        containing spaces (the descriptor has "iD4 Mic Monitor") would
        otherwise be split into multiple assignments.
      '';
    };

    easyeffectsPresetPackage = lib.mkOption {
      type = lib.types.package;
      internal = true;
      readOnly = true;
      default = easyeffects-preset;
      description = "The built `easyeffects-preset` CLI, for units that need its store path directly.";
    };
  };

  config.home.packages = [ cfg.package cfg.easyeffectsPresetPackage ];
}

{ config, lib, ... }:
let
  inherit (lib) mkEnableOption types;
  cfg = config.mine.audio;
in
{
  options.mine.desktop.hyprland.enable = mkEnableOption "Enable Hyprland profile";
  options.mine.desktop.hyprland.monitors = lib.mkOption {
    type = types.listOf (
      types.submodule {
        options = {
          output = lib.mkOption {
            type = types.str;
            description = "Monitor identifier, e.g. a connector name (`DP-1`) or description.";
          };

          mode = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Resolution/refresh mode, e.g. `preferred` or `1920x1080@60`.";
          };

          position = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Monitor position, e.g. `0x0` or `auto`.";
          };

          scale = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "Monitor scale factor, e.g. `1` or `auto`.";
          };

          transform = lib.mkOption {
            type = types.nullOr types.int;
            default = null;
            description = "Monitor transform (rotation/flip); see Hyprland's `transform` values.";
          };

          disabled = lib.mkOption {
            type = types.bool;
            default = false;
            description = "Disable this monitor entirely.";
          };
        };
      }
    );
    default = [ ];
    description = "Hyprland monitor definitions for this machine.";
    example = [
      {
        output = "DP-1";
        mode = "preferred";
        position = "auto-right";
        scale = "auto";
      }
      {
        output = "HDMI-A-1";
        disabled = true;
      }
    ];
  };

  options.mine.desktop.hyprland.layout = lib.mkOption {
    type = with types; nullOr str;
    default = null;
    description = "Default layout";
    example = "scrolling";
  };

  options.mine.desktop.hyprland.workspaces = lib.mkOption {
    type = types.listOf (
      types.submodule {
        options = {
          workspace = lib.mkOption {
            type = types.str;
            description = "Workspace selector this rule applies to, e.g. `1` or `m[DP-2]`.";
          };

          layout_opts = lib.mkOption {
            type = types.nullOr (types.attrsOf types.str);
            default = null;
            description = "Layout-specific options for this workspace, e.g. `{ direction = \"down\"; }`.";
          };
        };
      }
    );
    default = [ ];
    description = "Hyprland workspace rule definitions";
    example = [
      {
        workspace = "1";
        layout_opts = {
          rounding = "false";
        };
      }
    ];
  };

  options.mine.desktop.hyprland.lockScreenMonitor = lib.mkOption {
    type = with types; nullOr str;
    default = null;
    description = "Monitor to target for hyprlock widgets; null uses Hyprlock defaults.";
    example = "eDP-1";
  };

  options.mine.msft-corp = {
    enable = mkEnableOption {
      description = "Microsoft services integration";
      default = false;
    };

    corpnet = {
      gateway = lib.mkOption {
        type = types.str;
        # redmond is persistently broken; bay is the reliable default.
        default = "bay.msftvpn-alt.ras.microsoft.com";
        description = "GlobalProtect gateway for the Microsoft corporate VPN profile.";
      };

      gatewayDomain = lib.mkOption {
        type = types.str;
        default = "msftvpn-alt.ras.microsoft.com";
        description = ''
          Domain suffix shared by the corpnet GlobalProtect gateways. The
          corpnet-vpn@ systemd template appends this to its instance name, so
          `systemctl start corpnet-vpn@dublin` connects to
          `dublin.''${gatewayDomain}`. Lets you switch regions at start time
          (e.g. when one gateway is degraded) without a rebuild.
        '';
      };

      gateways = lib.mkOption {
        type = types.listOf types.str;
        # Every region remains a valid choice -- this is the offered list, not
        # the default (that's `gateway` above). Ordered with the default
        # region first since this list also drives display ordering (the
        # panel's gateway picker, the waybar/menu picker).
        default = [ "bay" "redmond" "dublin" "irving" ];
        description = ''
          Region short-names offered by the corpnet VPN waybar indicator's
          gateway picker. Each maps to `corpnet-vpn@<region>` (connecting to
          `<region>.''${gatewayDomain}`). Purely a convenience list for the
          menu; any region still works via `systemctl start corpnet-vpn@<region>`.
        '';
      };

      protocol = lib.mkOption {
        type = types.str;
        default = "gp";
        description = "OpenConnect protocol for the Microsoft corporate VPN profile.";
      };

      reportedOs = lib.mkOption {
        type = types.str;
        default = "win";
        description = "Operating system reported by OpenConnect during Microsoft VPN authentication.";
      };

      browserDesktopFile = lib.mkOption {
        type = types.str;
        default = "zen-beta.desktop";
        description = "Expected XDG desktop file for the browser used by Microsoft VPN SAML authentication.";
      };
    };

    authStack = lib.mkOption {
      type = types.enum [
        "intune"
        "himmelblau"
      ];
      default = "intune";
      description = "Corporate identity/compliance backend to use.";
    };

    himmelblau = {
      localUser = lib.mkOption {
        type = types.str;
        default = "cpuguy83";
        description = "Local user to map to an Entra ID user for Himmelblau.";
      };

      upn = lib.mkOption {
        type = types.str;
        description = "Entra ID UPN to map to the local user for Himmelblau.";
      };
    };
  };

  # Audio latency tiers + input-monitor loopbacks
  # (.copilot/plans/control-center.md §7). `hosts/yavin4/shared.nix` is
  # imported by both the NixOS and home-manager tiers, so declaring the
  # options here (imported by both `configuration.nix` and `home.nix`) is what
  # lets one set of values feed the NixOS loopback generator
  # (`modules/nixos/audio`), the `audio-mode` CLI, and the Quickshell panel
  # without drifting. NixOS and home-manager remain two independent
  # evaluations of the same option tree -- they merely agree because they
  # read the same host file.
  options.mine.audio = {
    latencyModes = lib.mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            id = lib.mkOption {
              type = types.str;
              description = "Stable tier id; also the status `class`.";
            };

            label = lib.mkOption {
              type = types.str;
              description = "Short display label.";
            };

            quantum = lib.mkOption {
              type = types.ints.unsigned;
              description = "`clock.force-quantum`; 0 means do not force.";
            };

            rate = lib.mkOption {
              type = types.ints.unsigned;
              description = "`clock.force-rate`; 0 means do not force.";
            };
          };
        }
      );
      default = [
        {
          id = "normal";
          label = "Normal";
          quantum = 0;
          rate = 0;
        }
        {
          id = "low";
          label = "Low";
          quantum = 256;
          rate = 48000;
        }
        {
          id = "ultra";
          label = "Ultra";
          # 64 @ 96000 = 0.67 ms, confirmed working by ear.
          #
          # The value carried over from pw-profile-toggle.sh was 54 (0.56 ms),
          # which distorted *all* output while reporting the correct hardware
          # rate and accumulating zero xruns -- neither `pw-top` nor the
          # device's own reported rate showed anything wrong, only listening
          # did. 128 was the first value confirmed clean; 64 was found to work
          # afterwards.
          #
          # Two explanations fit the 54-bad/64-good boundary and this data
          # cannot separate them: 54 is simply below what the interface
          # sustains, or 54 is not a power of two and the period misaligns.
          # Testing 32 would discriminate -- if 32 is clean, alignment is the
          # cause, not size. Either way the slider's power-of-two detents keep
          # a value like 54 off the easy path.
          quantum = 64;
          rate = 96000;
        }
      ];
      description = ''
        Latency tiers offered by the `audio-mode` CLI
        (.copilot/plans/control-center.md §4). Apply order is always
        quantum then rate.
      '';
    };

    rates = lib.mkOption {
      type = types.listOf types.ints.positive;
      default = [
        44100
        48000
        88200
        96000
      ];
      description = ''
        Sample rates offered as choices in the Custom latency picker
        (.copilot/plans/control-center.md §9.5) -- UI data, not validation.
        `audio-mode set-custom` accepts any positive rate; PipeWire itself
        only ever reports a min/max *range* for `clock.rate`, never a
        discrete list, so there is nothing to query and hardcoding the iD4's
        four supported rates here loses nothing.
      '';
    };

    quantums = lib.mkOption {
      type = types.listOf types.ints.positive;
      default = [
        32
        64
        128
        256
        512
        1024
        2048
      ];
      description = ''
        Quantum values used only as a bounds fallback for the panel's
        quantum slider (its endpoints, `[0]`/`[-1]`) -- UI data, not
        validation. `audio-mode set-custom` accepts any quantum inside the
        daemon's *live* `clock.min-quantum`/`clock.max-quantum` window, and
        the panel reads that live window directly rather than this list
        whenever `audio-mode status` can report it; this only stands in
        while it cannot (PipeWire unreachable).

        The slider itself is continuous across that live window, log2-mapped
        so every octave gets equal width, with the powers of two inside it
        acting as magnetic detents -- not snapped to this fixed list. An
        index-snapped slider that could only ever reach these seven stops is
        exactly how `54` (not one of them, and not reachable from a snapped
        slider either) ended up as "Ultra" above: it distorted all output
        while every instrument (xrun counters, the negotiated hardware rate)
        reported fine, and was only caught by listening (§4). A continuous
        slider with detents keeps both properties -- every value reachable,
        and the well-known stops still easy to land on exactly.
      '';
    };

    inputMonitors = lib.mkOption {
      type = types.listOf (
        types.submodule (
          { config, ... }:
          {
            options = {
              id = lib.mkOption {
                type = types.str;
                description = ''Stable monitor id, e.g. "mic" / "di".'';
              };

              label = lib.mkOption {
                type = types.str;
                description = ''Short display label, e.g. "Mic" / "DI".'';
              };

              description = lib.mkOption {
                type = types.str;
                description = ''
                  `node.description` for the loopback. This is also the
                  WirePlumber persistence key (§2.2) -- changing it discards
                  the monitor's stored volume/mute exactly once, so it must
                  not be changed casually.
                '';
              };

              source = lib.mkOption {
                type = types.str;
                description = "Capture `target.object`: the source device being monitored.";
              };

              sourceChannel = lib.mkOption {
                type = types.str;
                description = ''Channel captured from `source`, e.g. "FL" / "FR".'';
              };

              sink = lib.mkOption {
                type = types.nullOr types.str;
                default = null;
                description = ''
                  Playback `target.object`: the sink the monitor is routed into.

                  `null` (the default) pins it to nothing, so the monitor
                  follows whatever the current default sink is. That is almost
                  always what you want: monitoring is only useful through
                  whatever you are actually listening on, and pinning it to the
                  interface's own headphone jack means it is silent the moment
                  you switch to Bluetooth or desktop speakers.

                  Set it only to deliberately pin monitoring to one device
                  regardless of where everything else is playing.
                '';
              };

              captureNode = lib.mkOption {
                type = types.str;
                default = "input.monitor-${config.id}";
                description = ''
                  Stable `node.name` for the capture stream. Defaulted from
                  `id` so the NixOS loopback generator and the home-manager
                  descriptor can never independently invent -- and drift on --
                  the same string.
                '';
              };

              playbackNode = lib.mkOption {
                type = types.str;
                default = "output.monitor-${config.id}";
                description = "Stable `node.name` for the playback stream. Defaulted from `id`, same reasoning as `captureNode`.";
              };
            };
          }
        )
      );
      default = [ ];
      description = ''
        Input-monitor loopbacks generated by `modules/nixos/audio` and
        consumed by the `audio-mode` descriptor / Quickshell panel. Narrow by
        design: one channel of one source, fanned to FL+FR of one sink --
        widen it when a second shape actually appears.
      '';
    };
  };

  config.assertions = [
    {
      # Duplicate ids would make the descriptor ambiguous (which entry does
      # `audio-mode set <id>` mean?).
      assertion =
        let
          ids = map (m: m.id) cfg.latencyModes;
        in
        lib.length ids == lib.length (lib.unique ids);
      message = "mine.audio.latencyModes: every entry must have a unique id";
    }
    {
      # Duplicate (quantum, rate) pairs would make tier *resolution* from live
      # metadata ambiguous -- `audio-mode status` matches by exact pair, and a
      # second tier sharing one would make the matcher's answer arbitrary
      # (.copilot/plans/control-center.md §5.4).
      assertion =
        let
          pairs = map (m: [ m.quantum m.rate ]) cfg.latencyModes;
        in
        lib.length pairs == lib.length (lib.unique pairs);
      message = "mine.audio.latencyModes: every entry must have a unique (quantum, rate) pair";
    }
  ];
}

# Generic PipeWire loopback generator over `mine.audio.inputMonitors`,
# replacing the hardcoded `modules/nixos/audio/id4/input-routing.nix`.
# See .copilot/plans/control-center.md §8.
{ config, lib, ... }:
let
  cfg = config.mine.audio;

  mkLoopback = m: {
    name = "libpipewire-module-loopback";
    args = {
      # This is the WirePlumber persistence key (§2.2) -- must stay
      # byte-identical to what shipped before this generator existed, or the
      # monitor's stored volume/mute is discarded once.
      "node.description" = m.description;
      "audio.position" = [ "MONO" ];
      "capture.props" = {
        # Explicit in both props blocks (§8) rather than relying on the
        # module's global-name prefixing, so there is nothing to get wrong.
        # `node.name` embeds the daemon PID otherwise -- unstable across
        # restarts and unusable in any name-matching rule.
        "node.name" = m.captureNode;
        "audio.position" = [ m.sourceChannel ];
        "stream.dont-remix" = true;
        "target.object" = m.source;
      };
      "playback.props" = {
        "node.name" = m.playbackNode;
        "audio.position" = [
          "FL"
          "FR"
        ];
        "stream.dont-remix" = true;
        # Deliberately no `node.passive`: a passive playback stream would let
        # the monitored sink suspend when nothing else is playing, silently
        # killing monitoring -- which is the entire feature.
      }
      # Only pin the playback side when a sink was explicitly named. With
      # `sink = null` the stream carries no target and follows the default
      # sink, so monitoring is audible wherever you are actually listening --
      # pinning it to the interface's own headphone jack made it silent the
      # moment the default moved to Bluetooth.
      // lib.optionalAttrs (m.sink != null) {
        "target.object" = m.sink;
      };
    };
  };
in
{
  config = lib.mkIf (cfg.inputMonitors != [ ]) {
    services.pipewire.extraConfig.pipewire."10-input-monitors" = {
      "context.modules" = map mkLoopback cfg.inputMonitors;
    };
  };
}

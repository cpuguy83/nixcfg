{ ... }:
{
  services.pipewire.extraConfig.pipewire."10-id4-loopback" = {
    "context.modules" = [
      {
        name = "libpipewire-module-loopback";
        args = {
          "node.description" = "iD4 Mic Monitor";
          "audio.position" = [ "MONO" ];
          "capture.props" = {
            "audio.position" = [ "FL" ];
            "stream.dont-remix" = true;
            "target.object" = "alsa_input.usb-Audient_iD4-00.Direct__Direct__source";
          };
          "playback.props" = {
            "audio.position" = [
              "FL"
              "FR"
            ];
            "stream.dont-remix" = true;
            "target.object" = "alsa_output.usb-Audient_iD4-00.Direct__Direct__sink";
          };
        };
      }
      {
        name = "libpipewire-module-loopback";
        args = {
          "node.description" = "iD4 DI Monitor";
          "audio.position" = [ "MONO" ];
          "capture.props" = {
            "audio.position" = [ "FR" ];
            "stream.dont-remix" = true;
            "target.object" = "alsa_input.usb-Audient_iD4-00.Direct__Direct__source";
          };
          "playback.props" = {
            "audio.position" = [
              "FL"
              "FR"
            ];
            "stream.dont-remix" = true;
            "target.object" = "alsa_output.usb-Audient_iD4-00.Direct__Direct__sink";
          };
        };
      }
    ];
  };
}

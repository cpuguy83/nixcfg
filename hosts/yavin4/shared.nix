{ ... }:
{
  mine.msft-corp.enable = true;
  mine.msft-corp.authStack = "himmelblau";
  mine.msft-corp.himmelblau.upn = "brgoff@microsoft.com";

  # The iD4's mic (FL) and DI (FR) inputs, monitored into whatever sink is
  # currently the default -- no `sink` is set, so the loopbacks follow it.
  # Pinning them to the iD4's own headphone jack (as the original
  # input-routing.nix did) meant monitoring went silent the moment the default
  # sink moved to Bluetooth headphones. See .copilot/plans/control-center.md §8.
  mine.audio.inputMonitors = [
    {
      id = "mic";
      label = "Microphone";
      # FL is the mic preamp input on this iD4.
      sourceChannel = "FL";
      description = "iD4 Mic Monitor";
      source = "alsa_input.usb-Audient_iD4-00.Direct__Direct__source";
    }
    {
      id = "di";
      label = "Instrument (DI)";
      # FR is the DI (direct injection) input on this iD4.
      sourceChannel = "FR";
      description = "iD4 DI Monitor";
      source = "alsa_input.usb-Audient_iD4-00.Direct__Direct__source";
    }
  ];
}

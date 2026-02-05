{
  pkgs,
  pkgs-unstable,
  ...
}:
let
  defaultAudioWatcher = pkgs.writeShellApplication {
    name = "swayosd-default-audio-watcher";
    runtimeInputs = [
      pkgs.pulseaudio
      pkgs.coreutils
      pkgs.gawk
      pkgs.swayosd
    ];
    text = ''
      set -euo pipefail

      swayosd_notify() {
        local icon="$1"
        shift
        swayosd-client --custom-icon "$icon" --custom-message "$@"
      }
      last_sink=""

      notify_default_sink() {
        sink="$(pactl info | awk -F': ' '/^Default Sink:/ { print $2 }')"

        if [ -z "$sink" ] || [ "$sink" = "n/a" ] || [ "$sink" = "auto_null" ]; then
          if [ "$last_sink" != "n/a" ]; then
            swayosd_notify "Output unavailable"
            last_sink="n/a"
          fi
          return 0
        fi

        if [ "$sink" = "$last_sink" ]; then
          return 0
        fi

        desc="$(pactl list sinks | awk -v target="$sink" '
          $1 == "Name:" { current = $2 }
          current == target && /^[[:space:]]*Description:/ {
            sub(/^[[:space:]]*Description:[[:space:]]*/, "")
            print
            exit
          }
        ')"

        if [ -z "$desc" ]; then
          desc="$sink"
        fi

        icon="audio-speakers-symbolic"
        case "$sink" in
          bluez_output.*)
            icon="audio-headphones"
            ;;
          alsa_output.usb*)
            icon=""
            ;;
        esac

        swayosd_notify "$icon" "$desc"

        last_sink="$sink"
      }

      notify_default_sink

      pactl subscribe | while read -r line; do
        case "$line" in
          *"on server"*) notify_default_sink ;;
          *"on sink"*) notify_default_sink ;;
        esac
      done
    '';
  };
in
{
  services.udev.packages = [ pkgs.swayosd ];

  environment.systemPackages = [
    pkgs.swayosd
  ];

  systemd.user.services.sway-osd = {
    description = "Sway OSD";
    wantedBy = [ "graphical-session.target" ];
    after = [
      "graphical-session.target"
      "xdg-desktop-autostart.target"
    ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.swayosd}/bin/swayosd-server";
      Restart = "on-failure";
    };
  };

  systemd.user.services.swayosd-default-audio-watcher = {
    description = "Show an OSD when the default audio output changes";
    wantedBy = [ "graphical-session.target" ];
    after = [
      "graphical-session.target"
      "pipewire.service"
      "wireplumber.service"
    ];
    partOf = [ "graphical-session.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${defaultAudioWatcher}/bin/swayosd-default-audio-watcher";
      Restart = "on-failure";
    };
  };

  systemd.services.swayosd-libinput-backend = {
    description = "SwayOSD LibInput backend for listening to certain keys like CapsLock, ScrollLock, VolumeUp, etc.";
    documentation = [ "https://github.com/ErikReider/SwayOSD" ];
    wantedBy = [ "graphical.target" ];
    partOf = [ "graphical.target" ];
    after = [ "graphical.target" ];

    serviceConfig = {
      Type = "dbus";
      BusName = "org.erikreider.swayosd";
      ExecStart = "${pkgs.swayosd}/bin/swayosd-libinput-backend";
      Restart = "on-failure";
    };
  };
}

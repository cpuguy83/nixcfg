# writeShellApplication supplies strict mode and WirePlumber's PATH.
export LC_ALL=C
if [[ $# != 1 || ! "$1" =~ ^[1-9][0-9]*$ ]]; then
  echo "expected an explicit microphone source id" >&2
  exit 2
fi
wpctl set-mute "$1" toggle
wpctl get-volume "$1"

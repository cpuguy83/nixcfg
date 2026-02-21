set -euo pipefail

LIVE_QUANTUM=54
LIVE_RATE=96000

get_force_quantum() {
  pw-metadata -n settings 0 clock.force-quantum 2>/dev/null \
    | grep "clock.force-quantum" \
    | sed "s/.*value:'\([^']*\)'.*/\1/" \
    || echo "0"
}

get_force_rate() {
  pw-metadata -n settings 0 clock.force-rate 2>/dev/null \
    | grep "clock.force-rate" \
    | sed "s/.*value:'\([^']*\)'.*/\1/" \
    || echo "0"
}

is_live() {
  local q
  q="$(get_force_quantum)"
  [ -n "$q" ] && [ "$q" != "0" ]
}

set_live() {
  pw-metadata -n settings 0 clock.force-quantum "$LIVE_QUANTUM"
  pw-metadata -n settings 0 clock.force-rate "$LIVE_RATE"
}

set_normal() {
  pw-metadata -n settings 0 clock.force-quantum 0
  pw-metadata -n settings 0 clock.force-rate 0
}

toggle() {
  if is_live; then
    set_normal
  else
    set_live
  fi
}

status() {
  if is_live; then
    local rate
    rate="$(get_force_rate)"
    printf '{"text": "󰝱 LIVE", "tooltip": "Live mode: quantum=%s rate=%s", "class": "live"}\n' \
      "$LIVE_QUANTUM" "$rate"
  else
    printf '{"text": "󰝱", "tooltip": "Normal mode", "class": "normal"}\n'
  fi
}

case "${1:-status}" in
  toggle)  toggle; status ;;
  on)      set_live ;;
  off)     set_normal ;;
  is-live) is_live ;;
  status)  status ;;
  *)       echo "Usage: $0 {toggle|on|off|is-live|status}" >&2; exit 1 ;;
esac

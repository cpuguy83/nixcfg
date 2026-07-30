# corpnet VPN waybar indicator.
#
# Reports and toggles the corpnet GlobalProtect VPN systemd units:
#   corpnet-vpn.service          default gateway (DEFAULT_GATEWAY)
#   corpnet-vpn@<region>.service per-region gateway (<region>.GATEWAY_DOMAIN)
#
# The following variables are injected by shell.nix (do not define them here):
#   DEFAULT_UNIT DEFAULT_GATEWAY GATEWAY_DOMAIN GATEWAYS SYSTEMCTL SWITCH
: "${DEFAULT_UNIT:?}" "${DEFAULT_GATEWAY:?}" "${GATEWAY_DOMAIN:?}"
: "${SYSTEMCTL:?}" "${SWITCH:?}"

# Name of the active/activating corpnet unit, if any. Empty when disconnected.
active_unit() {
  "$SYSTEMCTL" list-units --type=service --state=active,activating \
    --no-legend --plain 'corpnet-vpn*.service' 2>/dev/null \
    | awk '{ print $1 }' | head -n1
}

# Human region label for a unit name.
unit_region() {
  case "$1" in
    "$DEFAULT_UNIT.service") printf '%s' "${DEFAULT_GATEWAY%%.*}" ;;
    corpnet-vpn@*.service)
      local inst="${1#corpnet-vpn@}"
      printf '%s' "$(systemd-escape -u "${inst%.service}")"
      ;;
    *) printf '%s' "$1" ;;
  esac
}

status() {
  local unit state region
  unit="$(active_unit)"

  if [ -z "$unit" ]; then
    printf '{"text": "󰖂 off", "tooltip": "corpnet: disconnected", "class": "disconnected"}\n'
    return
  fi

  state="$("$SYSTEMCTL" is-active "$unit" 2>/dev/null || true)"
  region="$(unit_region "$unit")"

  if [ "$state" = "activating" ]; then
    printf '{"text": "󰖂 %s…", "tooltip": "corpnet: connecting (%s)", "class": "connecting"}\n' \
      "$region" "$region"
  else
    printf '{"text": "󰖂 %s", "tooltip": "corpnet: connected (%s)", "class": "connected"}\n' \
      "$region" "$region"
  fi
}

toggle() {
  if [ -n "$(active_unit)" ]; then
    "$SWITCH" off
  else
    "$SWITCH" "$DEFAULT_UNIT"
  fi
}

menu() {
  local choice region
  choice="$(printf 'Disconnect\n%s\n' "$GATEWAYS" | grep -v '^$' \
    | fuzzel --dmenu --prompt 'corpnet gateway: ')" || return 0
  [ -n "$choice" ] || return 0

  if [ "$choice" = "Disconnect" ]; then
    "$SWITCH" off && notify-send 'corpnet VPN' 'Disconnected'
    return 0
  fi

  region="$(systemd-escape "$choice")"
  if "$SWITCH" "corpnet-vpn@$region"; then
    notify-send 'corpnet VPN' "Connecting to $choice ($choice.$GATEWAY_DOMAIN)"
  else
    notify-send -u critical 'corpnet VPN' "Failed to switch to $choice"
  fi
}

case "${1:-status}" in
  status) status ;;
  toggle) toggle ;;
  menu)   menu ;;
  *)      echo "Usage: $0 {status|toggle|menu}" >&2; exit 1 ;;
esac

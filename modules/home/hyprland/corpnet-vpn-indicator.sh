# corpnet VPN waybar indicator.
#
# Reports and toggles the corpnet GlobalProtect VPN systemd units:
#   corpnet-vpn.service          default gateway (DEFAULT_GATEWAY)
#   corpnet-vpn@<region>.service per-region gateway (<region>.GATEWAY_DOMAIN)
#
# `status`, `toggle` and `menu` are the original waybar verbs and are left
# untouched (see .copilot/plans/control-center.md §9.6) so
# `programs.waybar.enable = true` remains a working rollback. `state`,
# `connect` and `disconnect` are additive verbs for the Quickshell Control
# Center panel.
#
# The following variables are injected by shell.nix (do not define them here):
#   DEFAULT_UNIT DEFAULT_GATEWAY GATEWAY_DOMAIN GATEWAYS SYSTEMCTL SWITCH
: "${DEFAULT_UNIT:?}" "${DEFAULT_GATEWAY:?}" "${GATEWAY_DOMAIN:?}"
: "${SYSTEMCTL:?}" "${SWITCH:?}"

# Region name of the default gateway (e.g. "redmond" from
# "redmond.msftvpn-alt.ras.microsoft.com"). Mirrors the extraction
# unit_region() does inline for the bare corpnet-vpn.service case.
default_region() {
  printf '%s' "${DEFAULT_GATEWAY%%.*}"
}

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

# Structured state for the Control Center panel: one JSON document with the
# live connection state plus the full gateway list, so QML never has to parse
# a region back out of the glyph string status() emits. Always valid JSON on
# stdout and always exits 0, even if systemd is unreachable (active_unit and
# is-active already swallow their own failures). Built entirely with
# `jq --arg`/`--argjson`, never printf'd, so a gateway name containing a quote
# still produces well-formed output.
state() {
  local unit region gateway state_val

  unit="$(active_unit)"

  if [ -n "$unit" ]; then
    region="$(unit_region "$unit")"
    if [ "$region" = "$(default_region)" ]; then
      gateway="$DEFAULT_GATEWAY"
    else
      gateway="$region.$GATEWAY_DOMAIN"
    fi
    if [ "$("$SYSTEMCTL" is-active "$unit" 2>/dev/null || true)" = "activating" ]; then
      state_val="connecting"
    else
      state_val="connected"
    fi
  else
    region=""
    gateway=""
    state_val="disconnected"
  fi

  jq -n \
    --arg state "$state_val" \
    --arg unit "$unit" \
    --arg region "$region" \
    --arg gateway "$gateway" \
    --arg default_region "$(default_region)" \
    --arg default_gateway "$DEFAULT_GATEWAY" \
    --arg domain "$GATEWAY_DOMAIN" \
    --arg gateways_raw "$GATEWAYS" \
    '
      ($gateways_raw | split("\n") | map(select(length > 0))) as $regions
      | {
          state: $state,
          unit: (if $unit == "" then null else $unit end),
          region: (if $region == "" then null else $region end),
          gateway: (if $gateway == "" then null else $gateway end),
          gateways: [
            $regions[] | {
              region: .,
              gateway: (if . == $default_region then $default_gateway else (. + "." + $domain) end),
              default: (. == $default_region),
              active: ($region != "" and . == $region)
            }
          ]
        }
    '
}

# Connect to <region>, a plain region short-name (e.g. "dublin"). Does its own
# systemd-escape and unit construction, the same way menu() does for a
# non-default choice, so the Control Center panel never has to build a unit
# name or shell-escape itself (invariant I4 in the control-center plan). The
# default gateway's region resolves to the bare corpnet-vpn unit (the same
# unit toggle() uses) rather than corpnet-vpn@<default>, so there is one
# canonical unit per gateway instead of two names for the same host.
connect() {
  local region="${1:?usage: $0 connect <region>}"
  local unit

  if [ "$region" = "$(default_region)" ]; then
    unit="$DEFAULT_UNIT"
  else
    unit="corpnet-vpn@$(systemd-escape "$region")"
  fi

  if "$SWITCH" "$unit"; then
    notify-send 'corpnet VPN' "Connecting to $region ($region.$GATEWAY_DOMAIN)"
  else
    notify-send -u critical 'corpnet VPN' "Failed to switch to $region"
  fi
}

disconnect() {
  "$SWITCH" off && notify-send 'corpnet VPN' 'Disconnected'
}

case "${1:-status}" in
  status)     status ;;
  toggle)     toggle ;;
  menu)       menu ;;
  state)      state ;;
  connect)    connect "${2:-}" ;;
  disconnect) disconnect ;;
  *)          echo "Usage: $0 {status|toggle|menu|state|connect <region>|disconnect}" >&2; exit 1 ;;
esac

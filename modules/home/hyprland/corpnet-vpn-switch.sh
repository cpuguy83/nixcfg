# corpnet VPN switch helper. Stops whatever corpnet-vpn* unit is active, then
# starts the target, so an endpoint switch is one guarded operation instead of
# an ad-hoc stop+start. Runs as the invoking user; the system polkit rule
# (modules/nixos/msft-corp) authorizes managing corpnet-vpn* units without a
# password, so no pkexec/sudo is needed.
#
#   corpnet-vpn-switch <corpnet-vpn | corpnet-vpn@REGION | off>
#
# Stops whatever corpnet-vpn* unit is currently active, then starts the target
# (unless the target is "off", which just disconnects).
target="${1:?usage: corpnet-vpn-switch <corpnet-vpn|corpnet-vpn@REGION|off>}"

case "$target" in
  off | corpnet-vpn | corpnet-vpn@*) ;;
  *) echo "refusing to manage non-corpnet unit: $target" >&2; exit 2 ;;
esac

mapfile -t active < <(
  systemctl list-units --type=service --state=active,activating \
    --no-legend --plain 'corpnet-vpn*.service' 2>/dev/null | awk '{ print $1 }'
)

if [ "${#active[@]}" -gt 0 ]; then
  systemctl stop "${active[@]}"
fi

if [ "$target" != "off" ]; then
  systemctl start "$target"
fi

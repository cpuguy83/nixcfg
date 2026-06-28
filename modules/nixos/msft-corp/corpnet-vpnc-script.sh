#!/usr/bin/env bash
# corpnet-vpnc-script: openconnect/gpclient vpnc-script wrapper.
#
# gpclient/openconnect runs this as root on each tunnel "reason" event. We defer
# to the standard vpnc-script for the usual tun/DNS/server-route handling, then
# add the Microsoft corp split-tunnel routes once the tunnel is up. The corpnet
# GlobalProtect gateway does not push these include-routes, so we add them here.
#
# The route list is an UNMANAGED file (corp-internal IP ranges, deliberately kept
# out of git) at /etc/msft-vpn/corpnet-routes.txt. It is a point-in-time snapshot
# of the include-routes in the Azure VPN Client profile; regenerate it (the
# profile lives in your home, the output is root-owned under /etc) whenever
# Azure's routes change:
#
#   f=~/.config/microsoft-azurevpnclient/profiles/MSFT-AzVPN-Manual
#   sudo mkdir -p /etc/msft-vpn
#   tr -d '\n' < "$f" \
#     | grep -oiE '<destination>[^<]+</destination>[[:space:]]*<mask>[^<]+</mask>' \
#     | sed -E 's/<destination>([^<]+)<\/destination>[[:space:]]*<mask>([^<]+)<\/mask>/\1\/\2/I' \
#     | tr -d ' ' | sort -u | sudo tee /etc/msft-vpn/corpnet-routes.txt >/dev/null
#
# CORPNET_BASE_VPNC_SCRIPT and CORPNET_ROUTES_FILE are injected by the Nix wrapper.

set -euo pipefail

BASE="${CORPNET_BASE_VPNC_SCRIPT:?CORPNET_BASE_VPNC_SCRIPT not set}"
ROUTES_FILE="${CORPNET_ROUTES_FILE:?CORPNET_ROUTES_FILE not set}"
REASON="${reason:-}"

LOG_NAME=$(basename "$0")
log_msg() {
    echo "$LOG_NAME: $1" >&2
    # Also emit to the journal so failures are recoverable regardless of how
    # gpclient/openconnect was launched (e.g. a detached terminal that scrolled
    # away). View with: journalctl -t corpnet-vpnc-script
    command -v logger >/dev/null 2>&1 && logger -t "$LOG_NAME" -- "$1" || true
}

add_corpnet_routes() {
    local tun="${TUNDEV:-}"
    if [[ -z "$tun" ]]; then
        log_msg "TUNDEV is unset; cannot add corp routes."
        return 0
    fi
    if [[ ! -r "$ROUTES_FILE" ]]; then
        log_msg "Routes file $ROUTES_FILE is missing or unreadable; nothing to add."
        return 0
    fi

    local -a cidrs=()
    local cidr
    while IFS= read -r cidr; do
        cidr="${cidr%%#*}"
        cidr="${cidr//[[:space:]]/}"
        [[ -n "$cidr" ]] || continue
        cidrs+=("$cidr")
    done < "$ROUTES_FILE"

    local attempted=${#cidrs[@]}
    if [[ "$attempted" -eq 0 ]]; then
        log_msg "No routes found in $ROUTES_FILE for interface $tun."
        return 0
    fi

    local batch=""
    for cidr in "${cidrs[@]}"; do
        batch+="route replace $cidr dev $tun"$'\n'
    done

    # -force keeps ip going after a per-route failure. Plain "ip -batch" aborts
    # at the first error, which previously left the bulk of the routes (every
    # CIDR after the first failure) uninstalled.
    local out failed applied
    out=$(printf '%s' "$batch" | ip -force -batch - 2>&1) || true
    failed=$(printf '%s\n' "$out" | grep -c '^Command failed' || true)
    failed=${failed//[^0-9]/}
    failed=${failed:-0}
    applied=$((attempted - failed))

    if [[ "$failed" -eq 0 ]]; then
        log_msg "Added $applied/$attempted corp route(s) to interface $tun."
        return 0
    fi

    log_msg "Added $applied/$attempted corp route(s) to interface $tun; $failed failed. Sample failures:"
    # ip reports each failure as "Error: <message>" followed by
    # "Command failed -:<line>"; map the batch line number back to its CIDR.
    local line lineno
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        lineno=${line##*:}
        log_msg "  ${cidrs[$((lineno - 1))]:-?}: ${line}"
    done < <(printf '%s\n' "$out" | grep -E '^Command failed -:[0-9]+' | head -8)
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        log_msg "  $line"
    done < <(printf '%s\n' "$out" | grep -E '^Error:' | head -8)
}

# Let the standard vpnc-script do its normal work first, preserving its exit code.
rc=0
"$BASE" "$@" || rc=$?

case "$REASON" in
connect | reconnect)
    add_corpnet_routes
    ;;
esac

exit "$rc"

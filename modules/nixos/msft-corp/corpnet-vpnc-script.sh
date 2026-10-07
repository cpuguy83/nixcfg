#!/usr/bin/env bash
set -euo pipefail

exec "${CORPNET_VPN_COMMAND:?CORPNET_VPN_COMMAND not set}" hook -- "$@"

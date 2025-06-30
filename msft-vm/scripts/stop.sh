#!/usr/bin/env bash

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source ${SCRIPT_DIR}/lib.sh

send_shutdown

while [ -S "$QMP_SOCKET" ]; do
  sleep 1
done


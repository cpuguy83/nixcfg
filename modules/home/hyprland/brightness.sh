#!/usr/bin/env bash

set -euo pipefail

cmd="$1"
shift

socket="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/brightnessd.sock"

focused() {
	local id
	id="$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.monitor // empty' || true)"
	if [ -z "${id}" ]; then
		id="$(hyprctl -j monitors 2>/dev/null | jq -r 'map(select(.focused).name)[0] // empty' || true)"
	fi

	echo "${id}"
}

ensure_socket() {
	if [ -S "${socket}" ]; then
		return 0
	fi

	systemctl --user start brightnessd.socket >/dev/null 2>&1 || true

	for _ in $(seq 1 10); do
		if [ -S "${socket}" ]; then
			return 0
		fi
		sleep 0.05
	done

	echo "brightnessd socket not available at ${socket}" >&2
	exit 1
}

send_brightness() {
	local monitor="$1"
	local op="$2"
	local value="${3:-}"

	if [ -z "${monitor}" ]; then
		echo "No monitor focused" >&2
		exit 1
	fi

	ensure_socket

	local payload="${monitor} ${op}"
	if [ -n "${value}" ]; then
		payload="${payload} ${value}"
	fi

	local response
	if ! response="$(printf '%s\n' "${payload}" | socat - "UNIX-CONNECT:${socket}")"; then
		echo "Failed to send brightness request" >&2
		exit 1
	fi

	if [[ "${response}" != OK* ]]; then
		echo "brightnessd error: ${response}" >&2
		exit 1
	fi
}

brightness_up() {
	local monitor
	monitor="$(focused)"
	local step="${1:-10}"
	send_brightness "${monitor}" "+" "${step}"
}

brightness_down() {
	local monitor
	monitor="$(focused)"
	local step="${1:-10}"
	send_brightness "${monitor}" "-" "${step}"
}

brightness_set() {
	local monitor
	monitor="$(focused)"

	local value="${1:-50}"
	if (( value < 0 )); then
		value=0
	fi
	if (( value > 100 )); then
		value=100
	fi

	send_brightness "${monitor}" "set" "${value}"
}

case "${cmd}" in
	up)
		brightness_up "$@"
		;;
	down)
		brightness_down "$@"
		;;
	set)
		brightness_set "$@"
		;;
	*)
		echo "Unknown command: ${cmd}" >&2
		exit 1
		;;
esac

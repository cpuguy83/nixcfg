#!/usr/bin/env bash

set -eux -o pipefail

cmd="$1"
shift

get_bus_number() {
	local id="$1"

	# NOTE: These bus numbers are *NOT* the normal bus numbers
	# These monitors (Samsung NEO G7) do not support DDC over DP.
	# Subsequently I have added HDMI connects to them so I can control over DDC.
	# Obviously this is pretty device specific...
	# Sorry future me if/when this is a problem, I am forever in your debt as I *will* absolutely forget about this.
	local DP1_BUS=12
	local DP2_BUS=10

	case "${id}" in
		"DP-1")
			echo "${DP1_BUS}"
			;;
		"DP-2")
			echo "${DP2_BUS}"
			;;
		*)
			echo "Unknown monitor: ${id}" >&2
			return 1
			;;
	esac
}

focused() {
	local id="$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.monitor // empty' || true)"
	if [ -z "${id}" ]; then
		id="$(hyprctl -j monitors 2>/dev/null | jq -r 'map(select(.focused).name)[0] // empty' || true)"
	fi

	echo "${id}"
}

brightness_up() {
	local monitor="$(focused)"
	local bus="$(get_bus_number ${monitor})"
	local current="$(ddcutil --bus=${bus} getvcp 10)"

	local step="${1:-10}"
	local cur=$(echo "$current" | awk -F'current value = *' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')
	local v=$(( cur + step ))
	(( v > 100 )) && v=100

	ddcutil --bus=${bus} setvcp 10 ${v}
	swayosd-client --monitor "${monitor}" --custom-progress "$(awk "BEGIN {print $v/100}")"
}

brightness_down() {
	local monitor="$(focused)"
	local bus="$(get_bus_number ${monitor})"
	local current="$(ddcutil --bus=${bus} getvcp 10 | awk -F'current value = *' '{print $2}' | awk -F',' '{print $1}' | tr -d ' ')"

	local step="${1:-10}"
	local v=$(( current - step ))
	(( v < 0 )) && v=0

	ddcutil --bus=${bus} setvcp 10 ${v}
	swayosd-client --monitor "${monitor}" --custom-progress "$(awk "BEGIN {print $v/100}")"
}

brightness_set() {
	local monitor="$(focused)"
	local bus="$(get_bus_number ${monitor})"

	local value="${1:-50}"
	(( value < 0 )) && value=0
	(( value > 100 )) && value=100

	ddcutil --bus=${bus} setvcp 10 ${value}
	swayosd-client --monitor "${monitor}" --custom-progress "$(awk "BEGIN {print $value/100}")"
}

case "${cmd}" in
	up)
		brightness_up $@
		;;
	down)
		brightness_down $@
		;;
	set)
		brightness_set $@
		;;
	*)
		echo "Unknown command: ${cmd}" >&2
esac

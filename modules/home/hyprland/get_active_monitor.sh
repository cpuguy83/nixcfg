#!/usr/bin/env bash

id="$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.monitor // empty' || true)"
if [ -z "${id}" ]; then
	id="$(hyprctl -j monitors 2>/dev/null | jq -r 'map(select(.focused).name)[0] // empty' || true)"
fi

echo "${id}"

#!/usr/bin/env bash
# yawn — show Hyprland clients that are inhibiting idle.
#
# Some apps (video players, meetings, browsers playing media) hold an idle
# inhibitor, which keeps hypridle from dimming the screen, locking, or
# suspending. This surfaces the culprits by filtering `hyprctl clients -j` for
# `inhibitingIdle == 1` and printing them in a ps-like table.
set -euo pipefail

rows="$(
  hyprctl clients -j | jq -r '
    .[]
    | select(.inhibitingIdle == 1)
    | [ (.pid | tostring),
        (.class // .initialClass // "?"),
        (.workspace.name // (.workspace.id | tostring) // "?"),
        (.title // "") ]
    | @tsv
  '
)"

if [ -z "$rows" ]; then
  echo "Nothing is inhibiting idle." >&2
  exit 0
fi

{
  printf 'PID\tAPP\tWORKSPACE\tTITLE\n'
  printf '%s\n' "$rows"
} | column -t -s "$(printf '\t')"

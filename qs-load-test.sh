#!/usr/bin/env bash
# Load-test the Quickshell config on a throwaway headless compositor.
#
# Why this exists: `nixos-rebuild build` only copies the QML into the store — it
# never loads it. A bad type name, an illegal method name, or a broken import is
# accepted by the build and then makes Quickshell refuse the *entire* config at
# startup, taking the whole bar down. The only way to catch that before a switch
# is to actually load the config.
#
# Why headless: running `qs -p` against the live compositor maps real surfaces on
# the user's screen — a second bar, and for anything focus-related a window that
# can steal keyboard focus. That has already interrupted a fullscreen game. This
# runs against a nested wlroots compositor with no outputs, so nothing is ever
# drawn on the real display and no input is ever grabbed.
#
# Usage:  ./qs-load-test.sh [path/to/shell.qml]
# Exit:   0 = config loaded with no errors, 1 = load errors (see the log)

set -euo pipefail

CONFIG="${1:-modules/home/hyprland/quickshell/shell.qml}"
LOG="${QS_LOAD_TEST_LOG:-/tmp/qs-load-test.log}"
RUN_SECONDS="${QS_LOAD_TEST_SECONDS:-8}"

: "${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR must be set}"

[ -f "$CONFIG" ] || { echo "no such config: $CONFIG" >&2; exit 2; }

# Nix does not include untracked files in a flake, so a file that exists in the
# working copy is silently absent from the built config. This harness loads the
# *working copy*, so without this check it happily reports PASS while the
# deployed shell dies with "File not found" — which has happened, and a single
# missing file takes the entire bar down (the error cascades up through every
# parent type). Refuse to pass in that state.
if repo_root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  config_dir="$(cd "$(dirname "$CONFIG")" && pwd)"
  untracked="$(git -C "$repo_root" ls-files --others --exclude-standard -- "$config_dir")"
  if [ -n "$untracked" ]; then
    echo "FAIL — untracked files under $config_dir." >&2
    echo "Nix omits untracked files from a flake, so these would be missing at runtime:" >&2
    printf '%s\n' "$untracked" | while IFS= read -r path; do echo "  $path" >&2; done
    echo "fix: git add -N <file>" >&2
    exit 1
  fi
fi

# Ask the nested compositor to report its own socket rather than diffing
# $XDG_RUNTIME_DIR for a newly-appeared wayland-*. A diff races anything else
# that happens to start a compositor at the same moment, and would then test
# against the wrong session entirely. Sway runs `exec` with WAYLAND_DISPLAY
# already set to the socket it created, so this is exact by construction.
display_file="$(mktemp)"
sway_config="$(mktemp)"
# shellcheck disable=SC2016  # $WAYLAND_DISPLAY must reach sway unexpanded — sway expands it
printf 'exec printf "%%s" "$WAYLAND_DISPLAY" > %s\n' "$display_file" > "$sway_config"

WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman \
  sway --config "$sway_config" > /tmp/qs-load-test-sway.log 2>&1 &
sway_pid=$!

# shellcheck disable=SC2329  # invoked indirectly via the EXIT trap below
cleanup() {
  kill "$sway_pid" 2>/dev/null || true
  wait "$sway_pid" 2>/dev/null || true
  rm -f "$sway_config" "$display_file"
}
trap cleanup EXIT

nested=""
for _ in $(seq 40); do
  if [ -s "$display_file" ]; then
    nested="$(cat "$display_file")"
    break
  fi
  sleep 0.25
done

[ -n "$nested" ] || { echo "headless compositor never came up; see /tmp/qs-load-test-sway.log" >&2; exit 2; }

WAYLAND_DISPLAY="$nested" timeout "$RUN_SECONDS" qs -p "$CONFIG" > "$LOG" 2>&1 || true

errors="$(grep -cE '^\s*ERROR' "$LOG" || true)"
loaded="$(grep -cE 'Configuration Loaded' "$LOG" || true)"

echo "log: $LOG"
if [ "$loaded" -gt 0 ] && [ "$errors" -eq 0 ]; then
  echo "PASS — configuration loaded, 0 errors"
  exit 0
fi

echo "FAIL — loaded=$loaded errors=$errors"
grep -E '^\s*ERROR' "$LOG" || true
exit 1

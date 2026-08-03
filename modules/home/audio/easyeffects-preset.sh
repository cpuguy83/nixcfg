# easyeffects-preset -- EasyEffects preset selector helper for the Control
# Center Audio section (.copilot/plans/control-center.md §5, §7, §9.5).
#
# Verbs: status (default) | load <input|output> <name>.
#
# Presets are enumerated by listing the preset directories directly
# (`$XDG_DATA_HOME/easyeffects/{input,output}/*.json`) rather than parsing
# `easyeffects -p`, whose output is display-formatted (numbered, grouped
# under "No output presets."/"Input presets:") and brittle to depend on.
#
# `available` reflects whether a running EasyEffects instance can actually
# be queried, not merely whether the binary is on PATH: `-a`/`-l` are
# GApplication remote actions, and invoking one with no primary instance
# already registered on the session bus starts a brand-new instance rather
# than failing cleanly -- exactly the live-audio disruption this helper must
# never cause. Checking the user service's active state first is a read-only
# guard against that, so `status` never has to find out the hard way.

: "${XDG_DATA_HOME:=$HOME/.local/share}"

# One preset directory's names, one per line -- the basename of each
# `*.json` file, minus the extension. `nullglob` is what makes a directory
# with zero presets (the live "output" case on this machine) yield an empty
# list instead of the literal, unexpanded glob pattern.
list_presets() {
  local type="$1"
  local dir="$XDG_DATA_HOME/easyeffects/$type"
  local file

  [ -d "$dir" ] || return 0

  shopt -s nullglob
  for file in "$dir"/*.json; do
    basename "$file" .json
  done
  shopt -u nullglob
}

# True only if a real EasyEffects instance is reachable on the session bus.
# Gates every `-a`/`-l` call below -- see the header comment for why a plain
# `command -v easyeffects` is not enough on its own.
easyeffects_running() {
  command -v easyeffects >/dev/null 2>&1 || return 1
  systemctl --user is-active --quiet easyeffects.service 2>/dev/null
}

# The last-loaded preset name for one type, read from EasyEffects' own config
# rather than by asking the running app.
#
# The obvious way to get this is `easyeffects -a <type>`, and that is what this
# did first. It is unusable: `-a` is a GApplication remote action, and the
# primary instance *closes its window* when it handles one. Polling it every
# few seconds meant the EasyEffects GUI could never stay open for longer than
# one poll interval -- observed directly (window count 1 -> run `-a` -> 0).
#
# `db/easyeffectsrc` carries the same value under `[Presets]` as
# `lastLoaded{Input,Output}Preset`, so reading the file gives identical
# information with no side effect on the app. Nothing here launches or talks to
# EasyEffects at all; `status` is now purely filesystem reads.
last_loaded() {
  local type="$1"
  local key rc

  case "$type" in
    input) key="lastLoadedInputPreset" ;;
    output) key="lastLoadedOutputPreset" ;;
    *) return 0 ;;
  esac

  rc="${XDG_CONFIG_HOME:-$HOME/.config}/easyeffects/db/easyeffectsrc"
  [ -r "$rc" ] || return 0

  sed -n "s/^${key}=//p" "$rc" | head -n1
}

# One type's `{presets, current}` document.
type_status() {
  local type="$1"
  local -a names
  local current

  mapfile -t names < <(list_presets "$type")

  current="$(last_loaded "$type" || true)"
  current="$(printf '%s' "$current" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

  jq -n --arg current "$current" '
    {
      presets: $ARGS.positional,
      current: (if $current == "" then null else $current end)
    }
  ' --args -- "${names[@]}"
}

# Every key always present, `null`/`[]` where unknown, always exit 0 -- the
# same contract `audio-mode status` has, and for the same reason: a consumer
# (EffectsState.qml) tests for null, never for key existence.
status() {
  if ! easyeffects_running; then
    jq -n '{
      available: false,
      input: { presets: [], current: null },
      output: { presets: [], current: null }
    }'
    return 0
  fi

  jq -n \
    --argjson input "$(type_status input)" \
    --argjson output "$(type_status output)" \
    '{ available: true, input: $input, output: $output }'
}

# Loads a preset by name into the running instance. `type` is validated
# (exit 2 on anything else) purely to catch a caller passing garbage early --
# it is not itself forwarded to `easyeffects -l`, since that flag takes only
# a preset name, not a type. Guarded by `easyeffects_running`: `-l` is a
# GApplication remote action, so calling it with no primary instance
# registered would start a brand-new one rather than fail cleanly.
#
# Note this DOES close the EasyEffects window if it happens to be open, the
# same way `-a` did (see `last_loaded`). That is tolerable here and not in
# `status`: this runs only when the user explicitly picks a preset, not on a
# timer. There is no file-based equivalent -- loading is an action, not a
# reading -- so `-l` is genuinely the only option.
load_preset() {
  local type="${1:-}" name="${2:-}"

  case "$type" in
    input | output) ;;
    *)
      echo "easyeffects-preset: usage: easyeffects-preset load {input|output} <name>" >&2
      exit 2
      ;;
  esac

  if [ -z "$name" ]; then
    echo "easyeffects-preset: usage: easyeffects-preset load {input|output} <name>" >&2
    exit 2
  fi

  if ! easyeffects_running; then
    echo "easyeffects-preset: EasyEffects is not running" >&2
    exit 1
  fi

  easyeffects -l "$name"
}

case "${1:-status}" in
  status) status ;;
  load) load_preset "${2:-}" "${3:-}" ;;
  *) echo "Usage: $0 {status|load {input|output} <name>}" >&2; exit 2 ;;
esac

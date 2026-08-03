# audio-mode -- PipeWire latency tier CLI (.copilot/plans/control-center.md §5).
#
# Verbs: status (default) | get | set <id> | set-custom <quantum> <rate> |
# cycle | list | watch. There is no `restore` verb and no state file -- the
# tier is always derived from PipeWire's live metadata (§10.2), never
# remembered, and a PipeWire restart deliberately drops back to
# unforced/"normal" (§6).
#
# The following variables are injected by default.nix (do not define them
# here):
#   MODES_FILE  path to the generated audio-modes.json descriptor
: "${MODES_FILE:?}"
: "${XDG_RUNTIME_DIR:?}"

LOCK_FILE="$XDG_RUNTIME_DIR/audio-mode.lock"

# One read of pw-metadata's settings object, normalized to `key=value` lines.
# `-n ... p` (not a bare `s///`) matters: without it sed passes non-matching
# lines through verbatim, corrupting the capture on a partial match (§5.3).
read_settings() {
  pw-metadata -n settings 0 2>/dev/null \
    | sed -n "s/^.*key:'\([^']*\)' value:'\([^']*\)'.*\$/\1=\2/p"
}

# $1: `key=value` lines, as produced by read_settings. $2: key to look up.
settings_field() {
  printf '%s\n' "$1" | sed -n "s/^$2=\(.*\)\$/\1/p" | tail -n1
}

# Populates FQ/FR/DQ/DR (force-quantum, force-rate, default quantum, default
# rate) from $1, defaulting any missing key to 0, plus MINQ/MAXQ
# (clock.min-quantum/clock.max-quantum). MINQ/MAXQ are deliberately left
# empty rather than defaulted to 0 when absent -- 0 is not a meaningful
# quantum bound, and `status`/`set-custom` both need to tell "unknown" apart
# from "zero".
parse_settings() {
  FQ="$(settings_field "$1" 'clock.force-quantum')"
  FR="$(settings_field "$1" 'clock.force-rate')"
  DQ="$(settings_field "$1" 'clock.quantum')"
  DR="$(settings_field "$1" 'clock.rate')"
  MINQ="$(settings_field "$1" 'clock.min-quantum')"
  MAXQ="$(settings_field "$1" 'clock.max-quantum')"
  FQ="${FQ:-0}"
  FR="${FR:-0}"
  DQ="${DQ:-0}"
  DR="${DR:-0}"
}

# One id per line, straight from the descriptor -- shell completion and
# scripting, and reused below to build the `set` usage message and the
# `cycle` order.
list() {
  jq -r '.latencyModes[].id' "$MODES_FILE"
}

# Emits the full status JSON document (§5.2). Every key is always present,
# `null` where unknown, and this always exits 0 -- callers test for `null`,
# never for key existence.
status() {
  local settings

  settings="$(read_settings || true)"
  if [ -z "$settings" ]; then
    jq -n '{
      available: false,
      mode: "unknown",
      label: "Unavailable",
      class: "unavailable",
      forced: false,
      forcedQuantum: null,
      forcedRate: null,
      quantum: null,
      rate: null,
      defaultQuantum: null,
      defaultRate: null,
      minQuantum: null,
      maxQuantum: null,
      latencyMs: null,
      text: "—",
      tooltip: "Audio mode: PipeWire is not running"
    }'
    return 0
  fi

  parse_settings "$settings"

  # The mode is resolved by an exact (forcedQuantum, forcedRate) match against
  # the descriptor's latencyModes -- never from a sidecar file. `normal`
  # matches naturally because it is literally (0, 0). A pair that matches no
  # declared tier (including a partially-applied write) resolves to "custom".
  jq -n \
    --argjson forcedQuantum "$FQ" \
    --argjson forcedRate "$FR" \
    --argjson defaultQuantum "$DQ" \
    --argjson defaultRate "$DR" \
    --arg minQuantumRaw "$MINQ" \
    --arg maxQuantumRaw "$MAXQ" \
    --slurpfile descriptor "$MODES_FILE" \
    '
      ($descriptor[0].latencyModes) as $modes
      | (if $minQuantumRaw == "" then null else ($minQuantumRaw | tonumber) end) as $minQuantum
      | (if $maxQuantumRaw == "" then null else ($maxQuantumRaw | tonumber) end) as $maxQuantum
      | (($forcedQuantum != 0) or ($forcedRate != 0)) as $forced
      | (if $forcedQuantum != 0 then $forcedQuantum else $defaultQuantum end) as $quantum
      | (if $forcedRate != 0 then $forcedRate else $defaultRate end) as $rate
      | ([$modes[] | select(.quantum == $forcedQuantum and .rate == $forcedRate)] | .[0]) as $match
      | ($match.id // "custom") as $mode
      | ($match.label // "Custom") as $label
      | (if $rate != 0 then (($quantum / $rate * 1000 * 100 | round) / 100) else null end) as $latencyMs
      | (if $forced then
           "\($quantum) frames @ \($rate) Hz (\($latencyMs) ms)"
         else
           "dynamic, default \($defaultQuantum) @ \($defaultRate) Hz (\($latencyMs) ms)"
         end) as $detail
      | {
          available: true,
          mode: $mode,
          label: $label,
          class: $mode,
          forced: $forced,
          forcedQuantum: $forcedQuantum,
          forcedRate: $forcedRate,
          quantum: $quantum,
          rate: $rate,
          defaultQuantum: $defaultQuantum,
          defaultRate: $defaultRate,
          minQuantum: $minQuantum,
          maxQuantum: $maxQuantum,
          latencyMs: $latencyMs,
          text: $label,
          tooltip: ("Audio mode: " + $label + " — " + $detail)
        }
    '
}

get() {
  status | jq -r '.mode'
}

# Writes force-quantum then force-rate (§4 -- the reverse order would
# transiently produce a period shorter than either endpoint on the way back
# to Normal), then re-reads and verifies (§5.4). This is the shared
# apply-then-verify core for both `set <id>` and
# `set-custom <quantum> <rate>` -- what makes a silently rejected
# force-rate write (§2.4) visible instead of assumed. The caller must
# already hold the lock and have confirmed PipeWire is reachable.
apply_pair() {
  local q="$1" r="$2"
  local settings

  pw-metadata -n settings 0 clock.force-quantum "$q" >/dev/null
  pw-metadata -n settings 0 clock.force-rate "$r" >/dev/null

  settings="$(read_settings || true)"
  parse_settings "$settings"

  if [ "$FQ" != "$q" ] || [ "$FR" != "$r" ]; then
    echo "audio-mode: failed to verify pair $q/$r: observed force-quantum=$FQ force-rate=$FR" >&2
    exit 1
  fi
}

# Looks up declared tier $1's (quantum, rate) from the descriptor and applies
# it via apply_pair.
apply_mode() {
  local id="$1"
  local q r

  q="$(jq -r --arg id "$id" '.latencyModes[] | select(.id == $id) | .quantum' "$MODES_FILE")"
  r="$(jq -r --arg id "$id" '.latencyModes[] | select(.id == $id) | .rate' "$MODES_FILE")"

  apply_pair "$q" "$r"
}

# Exclusive lock held for the rest of the process's life -- released when the
# script exits. Guards every state-changing verb against a concurrent writer
# (a double-click issuing two `set`s, a terminal invocation racing the panel)
# interleaving force-quantum/force-rate writes into a mixed pair (§5.4).
acquire_lock() {
  exec {lock_fd}>"$LOCK_FILE"
  flock -x "$lock_fd"
}

set_mode() {
  local id="${1:-}"
  local settings

  if [ -z "$id" ] || ! jq -e --arg id "$id" '.latencyModes | any(.id == $id)' "$MODES_FILE" >/dev/null; then
    echo "audio-mode: usage: audio-mode set <id>; valid ids: $(list | tr '\n' ' ')" >&2
    exit 2
  fi

  acquire_lock

  settings="$(read_settings || true)"
  if [ -z "$settings" ]; then
    echo "audio-mode: PipeWire is not running" >&2
    exit 1
  fi

  apply_mode "$id"
}

# Applies an arbitrary (quantum, rate) pair (§9.5's Custom latency picker),
# through the exact same flock + apply_pair + verify path `set` uses. Unlike
# `set`, the pair is not looked up in the descriptor -- `mine.audio.quantums`/
# `rates` are UI choices offered by the panel, not a policy this verb
# enforces, so any quantum/rate PipeWire itself will accept is valid here.
#
# The one bound actually enforced is the daemon's own *live*
# `clock.min-quantum`/`clock.max-quantum` window -- read from the same
# pw-metadata capture as everything else, never hardcoded, since that window
# is itself daemon-reported and can differ from today's 32/2048. This is the
# guard that stops a repeat of `54` (§4): that value was inside the window
# and produced zero xruns, so range-checking would not have caught it either
# -- but it stops the class of mistake this verb could otherwise introduce
# freshly, an out-of-window value that PipeWire itself would reject or clamp
# silently.
set_custom() {
  local quantum="${1:-}" rate="${2:-}"
  local settings

  if ! [[ "$quantum" =~ ^[0-9]+$ ]] || [ "$quantum" -le 0 ]; then
    echo "audio-mode: usage: audio-mode set-custom <quantum> <rate>; quantum must be a positive integer" >&2
    exit 2
  fi
  if ! [[ "$rate" =~ ^[0-9]+$ ]] || [ "$rate" -le 0 ]; then
    echo "audio-mode: usage: audio-mode set-custom <quantum> <rate>; rate must be a positive integer" >&2
    exit 2
  fi

  acquire_lock

  settings="$(read_settings || true)"
  if [ -z "$settings" ]; then
    echo "audio-mode: PipeWire is not running" >&2
    exit 1
  fi

  parse_settings "$settings"

  if [ -z "$MINQ" ] || [ -z "$MAXQ" ]; then
    echo "audio-mode: could not read clock.min-quantum/clock.max-quantum from PipeWire" >&2
    exit 1
  fi

  if [ "$quantum" -lt "$MINQ" ] || [ "$quantum" -gt "$MAXQ" ]; then
    echo "audio-mode: quantum $quantum outside daemon's allowed window ($MINQ..$MAXQ)" >&2
    exit 2
  fi

  apply_pair "$quantum" "$rate"
}

cycle() {
  local settings current next_id i
  local -a ids

  acquire_lock

  settings="$(read_settings || true)"
  if [ -z "$settings" ]; then
    echo "audio-mode: PipeWire is not running" >&2
    exit 1
  fi

  parse_settings "$settings"
  current="$(jq -r --argjson fq "$FQ" --argjson fr "$FR" '
    ([.latencyModes[] | select(.quantum == $fq and .rate == $fr)] | .[0].id) // "custom"
  ' "$MODES_FILE")"

  mapfile -t ids < <(list)
  if [ "${#ids[@]}" -eq 0 ]; then
    echo "audio-mode: no latency modes configured" >&2
    exit 1
  fi

  # Next id in declared order; from "custom"/"unknown" (no match in $ids)
  # this falls through to the first entry.
  next_id="${ids[0]}"
  for i in "${!ids[@]}"; do
    if [ "${ids[$i]}" = "$current" ]; then
      next_id="${ids[$(( (i + 1) % ${#ids[@]} ))]}"
      break
    fi
  done

  apply_mode "$next_id"
}

# Change notifier for the panel (§9.4/Quickshell's AudioState.qml): `-m`
# streams metadata for the whole "settings" object, printing every key's
# current value once on startup and one line per change thereafter. Runs
# until killed -- the caller (a long-lived Quickshell Process) is
# responsible for restarting it if it exits, e.g. because PipeWire itself
# went away. `exec` replaces this shell with pw-metadata rather than
# forking it, so there is no wrapper process left holding a lingering flock
# or file descriptor once it starts, and signals reach pw-metadata directly.
watch() {
  exec pw-metadata -n settings -m
}

case "${1:-status}" in
  status)     status ;;
  get)        get ;;
  set)        set_mode "${2:-}" ;;
  set-custom) set_custom "${2:-}" "${3:-}" ;;
  cycle)      cycle ;;
  list)       list ;;
  watch)      watch ;;
  *)          echo "Usage: $0 {status|get|set <id>|set-custom <quantum> <rate>|cycle|list|watch}" >&2; exit 2 ;;
esac

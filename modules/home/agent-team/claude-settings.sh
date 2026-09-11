# shellcheck shell=bash
# shellcheck disable=SC2086  # $VERBOSE_ARG is intentionally word-split (home-manager idiom)
#
# Merge owned Claude or Copilot settings without taking the file away from the
# client. This template is instantiated separately for each client.
#
# ~/.claude/settings.json cannot be a home-manager symlink: Claude rewrites it at
# runtime whenever the user runs /model, /effort or /config. So this merges a
# small set of owned keys into whatever is there. The client may be
# writing the same file while activation runs -- and the mitigations are:
#
#   * If the owned keys are already what we want, do nothing at all. This is the
#     common case on every re-activation, so most runs never write.
#   * Otherwise capture the file's content hash and inode before reading, and
#     re-check both immediately before the replacing rename. A concurrent write
#     is detected and the merge is abandoned rather than silently reverting it.
#
# That leaves a window of one rename, which cannot be closed without a lock
# protocol Claude does not participate in. Losing that race costs a settings
# write, and the next activation re-applies the key.

_agentTeamSettingsIdentity() {
  local file="$1" inode hash
  inode="$(stat -c '%i:%s:%y' "$file" 2>/dev/null)" || return 1
  hash="$(sha256sum <"$file" 2>/dev/null)" || return 1
  printf '%s %s' "$inode" "$hash"
}

_agentTeamMergeSettings() {
  local dir="$HOME/@settingsDir@"
  local settings="$dir/settings.json"
  local owned='@ownedSettings@'
  local tmp before after

  if [[ -L $dir || -L $settings ]]; then
    warnEcho "agent-team: $dir or $settings is a symlink; leaving settings unchanged"
    return 0
  fi

  run mkdir -p $VERBOSE_ARG "$dir"

  if [[ ! -e $settings ]]; then
    if [[ -v DRY_RUN ]]; then
      echo "agent-team: would create $settings with $owned"
      return 0
    fi
    tmp="$(mktemp "$settings.agent-team.XXXXXX")"
    printf '%s\n' "$owned" >"$tmp"
    # Link without replacement: a client creating settings concurrently wins.
    if ! ln -T -- "$tmp" "$settings"; then
      warnEcho "agent-team: $settings appeared while creating it; leaving it as-is"
    fi
    rm -f "$tmp"
    return 0
  elif [[ ! -f $settings ]]; then
    warnEcho "agent-team: $settings is not a regular file; leaving settings unchanged"
    return 0
  fi

  # The common case: already correct, so never write at all.
  # shellcheck disable=SC2016  # $owned is a jq variable
  if @jq@ -e -s --argjson owned "$owned" \
    'length == 1 and (.[0] | type == "object" and (. + $owned == .))' \
    "$settings" >/dev/null 2>&1; then
    verboseEcho "agent-team: $settings already has the desired settings"
    return 0
  fi

  # Everything below writes directly rather than through `run`, including the
  # temporary file, so a dry run has to stop before it leaves one behind.
  if [[ -v DRY_RUN ]]; then
    echo "agent-team: would merge $owned into $settings"
    return 0
  fi

  if ! before="$(_agentTeamSettingsIdentity "$settings")"; then
    warnEcho "agent-team: cannot read $settings; leaving settings unchanged"
    return 0
  fi

  # Reject scalars, arrays, empty streams and multiple JSON documents as well as
  # malformed JSON. Never turn unexpected input into a partial settings file.
  if ! @jq@ -e -s 'length == 1 and (.[0] | type == "object")' "$settings" >/dev/null 2>&1; then
    warnEcho "agent-team: $settings is not a JSON object; leaving settings unchanged"
    return 0
  fi

  tmp="$(mktemp "$settings.agent-team.XXXXXX")"
  # shellcheck disable=SC2016  # $owned is a jq variable
  if ! @jq@ -e -s --argjson owned "$owned" \
    'if length == 1 and (.[0] | type == "object") then .[0] + $owned else error("expected one object") end' \
    "$settings" >"$tmp"; then
    rm -f "$tmp"
    warnEcho "agent-team: $settings is not a JSON object; leaving settings unchanged"
    return 0
  fi

  run chmod $VERBOSE_ARG --reference="$settings" "$tmp"

  # Last check before the swap. Anything the client wrote since the read above is
  # still on disk, and abandoning here preserves it.
  if [[ -L $dir || -L $settings ]] \
    || ! after="$(_agentTeamSettingsIdentity "$settings")" || [[ $after != "$before" ]]; then
    rm -f "$tmp"
    warnEcho "agent-team: $settings changed while merging; leaving it as-is"
    return 0
  fi

  run mv $VERBOSE_ARG "$tmp" "$settings"
}

_agentTeamMergeSettings

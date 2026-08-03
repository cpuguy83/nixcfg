# shellcheck shell=bash
# shellcheck disable=SC2086  # $VERBOSE_ARG is intentionally word-split (home-manager idiom)
#
# Set Claude's session-wide fallbackModel without taking the file away from
# Claude itself.
#
# ~/.claude/settings.json cannot be a home-manager symlink: Claude rewrites it at
# runtime whenever the user runs /model, /effort or /config. So this merges a
# single key into whatever is there. The hazard is obvious -- Claude may be
# writing the same file while activation runs -- and the mitigations are:
#
#   * If fallbackModel is already what we want, do nothing at all. This is the
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

_agentTeamMergeClaudeSettings() {
  local settings="$HOME/.claude/settings.json"
  local chain='@fallbackModel@'
  local tmp before after

  if [[ -L $settings ]]; then
    warnEcho "agent-team: $settings is a symlink; leaving fallbackModel unset"
    return 0
  fi

  run mkdir -p $VERBOSE_ARG "$HOME/.claude"

  if [[ ! -e $settings ]]; then
    if [[ -v DRY_RUN ]]; then
      echo "agent-team: would create $settings with fallbackModel $chain"
      return 0
    fi
    run install -m 600 /dev/null "$settings"
    printf '{}\n' >"$settings"
  elif [[ ! -f $settings ]]; then
    warnEcho "agent-team: $settings is not a regular file; leaving fallbackModel unset"
    return 0
  fi

  # The common case: already correct, so never write at all.
  if @jq@ -e --argjson chain "$chain" '.fallbackModel == $chain' "$settings" >/dev/null 2>&1; then
    verboseEcho "agent-team: $settings already has the desired fallbackModel"
    return 0
  fi

  # Everything below writes directly rather than through `run`, including the
  # temporary file, so a dry run has to stop before it leaves one behind.
  if [[ -v DRY_RUN ]]; then
    echo "agent-team: would set fallbackModel $chain in $settings"
    return 0
  fi

  if ! before="$(_agentTeamSettingsIdentity "$settings")"; then
    warnEcho "agent-team: cannot read $settings; leaving fallbackModel unset"
    return 0
  fi

  tmp="$(mktemp "$settings.agent-team.XXXXXX")"
  if ! @jq@ --argjson chain "$chain" '.fallbackModel = $chain' "$settings" >"$tmp"; then
    rm -f "$tmp"
    warnEcho "agent-team: $settings is not valid JSON; leaving fallbackModel unset"
    return 0
  fi

  # Last check before the swap. Anything Claude wrote since the read above is
  # still on disk, and abandoning here preserves it.
  if ! after="$(_agentTeamSettingsIdentity "$settings")" || [[ $after != "$before" ]]; then
    rm -f "$tmp"
    warnEcho "agent-team: $settings changed while merging fallbackModel; leaving it as-is"
    return 0
  fi

  run chmod $VERBOSE_ARG --reference="$settings" "$tmp"
  run mv $VERBOSE_ARG "$tmp" "$settings"
}

_agentTeamMergeClaudeSettings

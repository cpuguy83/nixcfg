# shellcheck shell=bash
# shellcheck disable=SC2086  # $VERBOSE_ARG is intentionally word-split (home-manager idiom)
#
# Retire the pre-existing global instruction topology so Home Manager can take
# ownership of those paths.
#
# Ordering matters here. `checkLinkTargets` runs before `writeBoundary` and
# refuses to proceed when a target exists that Home Manager does not own. For a
# regular file it defers to `backupFileExtension`, but that branch is gated on
# the path not being a symlink, so an unmanaged *symlink* is a hard error no
# backup setting can resolve. Clearing that is the only reason this exists.
#
# The obvious fix -- delete the symlinks -- would leave those paths missing if
# any later activation step failed, which is exactly the failure mode this is
# meant to avoid. So instead each symlink is replaced, in place and atomically,
# by a regular file holding the content it resolved to. Nothing is ever absent,
# no content is lost, and afterwards every target is a plain file that Home
# Manager backs up itself inside `linkGeneration` -- a single rename immediately
# before it writes the replacement, which is the last safe moment.
#
# Dangling symlinks are left alone deliberately: `checkLinkTargets` skips them
# (its guard is `-e`, which is false for a broken link) and `linkGeneration`
# force-links over them.
#
# Adoption of any kind needs a backup mechanism, and where that comes from
# depends on how activation was invoked: the NixOS and nix-darwin modules set it
# from `home-manager.backupFileExtension`, while standalone Home Manager has no
# equivalent option and picks it up only from `home-manager switch -b EXT`. The
# requirement is therefore checked here rather than assumed.

_agentTeamOwnedByHomeManager() {
  local link
  link="$(readlink "$1" 2>/dev/null)" || return 1
  [[ $link == @storeDir@/*-home-manager-files/* ]]
}

_agentTeamTakeover() {
  local targets=(@targets@)
  local target problem link tmp backup
  local problems=()
  local convert=()
  local adopt=()
  local manifest manifestDir

  # Pass 1 -- classify only. No live path is modified in this loop, so an
  # unsupported topology is reported while everything is still intact.
  for target in "${targets[@]}"; do
    if [[ ! -e $target && ! -L $target ]]; then
      continue
    fi
    if _agentTeamOwnedByHomeManager "$target"; then
      continue
    fi

    if [[ -L $target ]]; then
      if [[ ! -e $target ]]; then
        verboseEcho "agent-team: leaving dangling symlink $target for home-manager"
        continue
      fi
      if [[ ! -f $target ]]; then
        problems+=("$target is a symlink to something that is not a regular file")
        continue
      fi
      convert+=("$target")
      adopt+=("$target")
    elif [[ -f $target ]]; then
      adopt+=("$target")
    else
      problems+=("$target exists but is neither a regular file nor a symlink")
    fi
  done

  # Everything in `adopt` reaches checkLinkTargets as an unmanaged regular file:
  # the pre-existing ones already are, and the symlinks become one the moment
  # pass 2 runs. That check only tolerates such a file when it can be backed up,
  # so without a backup mechanism activation fails a few steps from here. The
  # check has to cover the symlinks too -- gating it on the pre-existing files
  # alone lets a topology made purely of foreign symlinks be converted first and
  # rejected afterwards, which is precisely the mutate-then-fail this two-pass
  # split exists to prevent.
  #
  # The conditions below mirror that check's own precedence: a backup command is
  # assumed to succeed, otherwise the extension is used and its destination has
  # to be free. "A mechanism is configured" is necessary but not sufficient -- a
  # backup left by an earlier run occupies the slot and is refused just as
  # firmly. Deliberately stricter in one respect: checkLinkTargets also lets a
  # target through when its content already equals what home-manager is about to
  # write, which is not knowable here, so a stale backup beside an
  # already-correct file is refused where home-manager would have proceeded.
  # That costs a clear error the user can clear in seconds; guessing wrong the
  # other way costs a conversion nothing undoes automatically.
  if [[ ${#adopt[@]} -gt 0 ]]; then
    if [[ -n ${HOME_MANAGER_BACKUP_COMMAND:-} ]]; then
      verboseEcho "agent-team: adoption backed by HOME_MANAGER_BACKUP_COMMAND"
    elif [[ -n ${HOME_MANAGER_BACKUP_EXT:-} ]]; then
      for target in "${adopt[@]}"; do
        backup="$target.$HOME_MANAGER_BACKUP_EXT"
        if [[ -d $backup && ! -L $backup ]]; then
          # linkGeneration clears an occupied slot with a non-recursive `rm` and
          # then moves the target onto it, and neither can handle a directory:
          # `rm` refuses outright, and `mv` either buries the file inside the
          # directory or, if it is not writable, fails. The script has no
          # `errexit` and only warns on a failed move, so it goes on to
          # force-link the target and the original content is gone. Overwrite
          # does not help -- the `rm` it enables is the part that cannot work.
          problems+=("$backup is a directory; home-manager cannot back up onto it and would destroy $target trying")
        elif [[ -e $backup && -z ${HOME_MANAGER_BACKUP_OVERWRITE:-} ]]; then
          problems+=("$backup already exists and would be clobbered when $target is backed up; move it aside, or pick an unused backup extension")
        fi
      done
    else
      for target in "${adopt[@]}"; do
        problems+=("$target must be adopted from outside home-manager, but no backup mechanism is configured")
      done
      problems+=("set home-manager.backupFileExtension as a NixOS or nix-darwin module, run a standalone 'home-manager switch -b EXT', or export HOME_MANAGER_BACKUP_EXT before invoking an activation package directly")
    fi
  fi

  if [[ ${#problems[@]} -gt 0 ]]; then
    for problem in "${problems[@]}"; do
      errorEcho "agent-team: $problem"
    done
    errorEcho "agent-team: refusing to modify anything; all paths left untouched"
    exit 1
  fi

  if [[ ${#convert[@]} -eq 0 ]]; then
    return 0
  fi

  # Pass 1 is read-only, so a dry run reports its verdict and stops here. Below
  # this point the script writes files directly rather than through `run`, and a
  # dry run that fell through would both create a manifest and abort activation
  # when `run mkdir` had only echoed the directory it needed.
  if [[ -v DRY_RUN ]]; then
    for target in "${convert[@]}"; do
      echo "agent-team: would replace symlink $target with its content"
    done
    return 0
  fi

  # Pass 2 -- the only mutation, recorded so the previous layout can be restored
  # by hand.
  manifestDir="$HOME/.local/state/agent-team"
  manifest="$manifestDir/takeover-$(date +%Y%m%d%H%M%S).manifest"
  run mkdir -p $VERBOSE_ARG "$manifestDir"

  {
    printf '# agent-team takeover %s\n' "$(date -Is)"
    printf '# These paths were symlinks. Their content was materialised in place\n'
    printf '# so home-manager could adopt them. To restore the previous layout:\n'
  } >"$manifest"

  for target in "${convert[@]}"; do
    link="$(readlink "$target")"
    printf 'ln -sfn %q %q\n' "$link" "$target" >>"$manifest"

    # Write beside the target so the rename is atomic and on the same
    # filesystem, and copy the content rather than the link so whatever the
    # symlink pointed at is left untouched.
    tmp="$target.agent-team-takeover.$$"
    if ! cat -- "$target" >"$tmp"; then
      rm -f -- "$tmp"
      errorEcho "agent-team: could not read $target; leaving it as a symlink"
      exit 1
    fi
    chmod 644 "$tmp"
    warnEcho "agent-team: replacing symlink $target -> $link with its content"
    run mv $VERBOSE_ARG -- "$tmp" "$target"
  done

  warnEcho "agent-team: previous symlink layout recorded in $manifest"
}

_agentTeamTakeover

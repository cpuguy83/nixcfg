{ pkgs }:

# Private launch policy, not session environment or package policy. Source with
# a fixed harness argument; never accept a caller-selected path or fallback.
pkgs.writeText "agent-temp-env.sh" ''
  # shellcheck shell=bash
  _agentTempDir() (
    umask 077
    case "$1" in
      claude|codex|copilot|opencode) ;;
      *)
        printf 'agent-temp: unknown harness: %s\n' "$1" >&2
        exit 1
        ;;
    esac

    base=/tmp/ai-agent-tmp
    for dir in "$base" "$base/$1"; do
      # mkdir without -p never traverses an unvalidated parent. A concurrent
      # creator is fine only if the resulting directory passes every check.
      if [[ ! -e $dir && ! -L $dir ]]; then
        ${pkgs.coreutils}/bin/mkdir -m 700 -- "$dir" 2>/dev/null || true
      fi
      if [[ -L $dir || ! -d $dir || ! -O $dir ]]; then
        printf 'agent-temp: %s must be an owned, non-symlink directory\n' "$dir" >&2
        exit 1
      fi
      mode=$(${pkgs.coreutils}/bin/stat -c '%a' -- "$dir") || exit 1
      if [[ $mode != 700 ]]; then
        printf 'agent-temp: %s must be mode 0700, found %s\n' "$dir" "$mode" >&2
        exit 1
      fi
    done
    printf '%s\n' "$base/$1"
  )

  if ! TMPDIR="$(_agentTempDir "$1")"; then
    exit 1
  fi
  unset -f _agentTempDir
  export TMPDIR
  export TMP="$TMPDIR" TEMP="$TMPDIR"
  if [[ $1 == claude ]]; then
    export CLAUDE_CODE_TMPDIR="$TMPDIR"
  fi
''

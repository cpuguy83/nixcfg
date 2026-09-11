# shellcheck shell=bash
#
# Body of the `codex-team-review` wrapper. Placeholders are substituted by
# codex-review.nix; keeping the shell in a real file means shellcheck lints it
# directly and Nix string escaping cannot corrupt the logic.

readonly BASE_URL='@baseUrl@'
readonly TIMEOUT='@timeoutSeconds@'
readonly MAX_BRIEF_BYTES='@maxBriefBytes@'
readonly MAX_BRIEF_AGE='@maxBriefAgeSeconds@'
ERRFILE=""

readonly DESIGN_PREAMBLE='@designPreamble@'
readonly FINAL_PREAMBLE='@finalPreamble@'

# A review that did not happen must never read as a review that passed.
unavailable() {
  printf 'CODEX REVIEW UNAVAILABLE\n'
  printf 'reason: %s\n' "$1"
  # Codex writes its transcript to stderr. It is noise on success and the only
  # useful diagnostic on failure, so it is held back until it is needed, and
  # then reduced to the error lines when there are any. Note the match has to be
  # tested on its own: the exit status of `grep | tail` is tail's, so it would
  # never report a miss.
  if [ -n "$ERRFILE" ] && [ -s "$ERRFILE" ]; then
    local diag
    diag=$(grep -iE '^[[:space:]]*(error|warning)' -- "$ERRFILE" || true)
    if [ -z "$diag" ]; then
      diag=$(tail -n 10 -- "$ERRFILE" || true)
    fi
    if [ -n "$diag" ]; then
      printf 'codex diagnostics:\n'
      printf '%s\n' "$diag" | tail -n 10
    fi
  fi
  printf 'No review was performed. Do not record this as approval.\n'
  exit 1
}

reject() {
  printf 'codex-team-review: refusing request: %s\n' "$1" >&2
  exit 64
}

# Credentials for the real upstream APIs have no business in this process. The
# review proxy does not authenticate, so nothing here needs them.
unset OPENAI_API_KEY ANTHROPIC_API_KEY AZURE_OPENAI_API_KEY \
  OPENAI_API_BASE OPENAI_BASE_URL ANTHROPIC_BASE_URL

# The wrapper owns one private directory and briefs may only live inside it.
# This is what stops the tool being a confused deputy: a caller cannot name
# `~/.ssh/id_ed25519`, because a brief path is a fixed prefix plus 32 hex
# characters, and no other path can be spelled that way.
resolve_brief_dir() {
  local base dir perms

  if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ] && [ -O "$XDG_RUNTIME_DIR" ]; then
    base=$XDG_RUNTIME_DIR
  else
    base=$HOME/.cache
  fi
  dir=$base/codex-team-review

  if [ -L "$dir" ]; then
    reject "brief directory $dir is a symlink"
  fi

  if [ ! -d "$dir" ]; then
    # Create it already private; do not widen then narrow.
    (umask 077 && mkdir -p -- "$dir")
  fi

  if [ ! -d "$dir" ]; then
    reject "could not create brief directory $dir"
  fi
  if [ ! -O "$dir" ]; then
    reject "brief directory $dir is not owned by the calling user"
  fi

  perms=$(stat -c '%a' "$dir")
  if [ "$perms" != "700" ]; then
    reject "brief directory $dir must be mode 0700, found $perms"
  fi

  printf '%s' "$dir"
}

# Codex keeps its state, and more importantly its instruction documents, under
# CODEX_HOME. At least three files there reach the model: AGENTS.md,
# AGENTS.override.md, and every skills/<name>/SKILL.md, which codex inlines by
# name into the prompt. Enumerating the bad names cannot work -- codex recreates
# skills/.system on every run and ships a skill whose stated job is installing
# more skills -- so each review gets a directory that did not exist until the
# review started. There is then nothing to poison: anything planted earlier is
# in some other directory, and this one is removed when the run ends.
#
# It lives under ~/.cache rather than the brief directory because that one may be
# on tmpfs, and codex refuses to create its helper binaries under a temporary dir.
new_codex_home() {
  local base=$HOME/.cache/codex-team-review-home dir perms minutes

  if [ -L "$base" ]; then
    reject "codex home $base is a symlink"
  fi

  if [ ! -d "$base" ]; then
    # Create it already private; do not widen then narrow.
    (umask 077 && mkdir -p -- "$base")
  fi

  if [ ! -d "$base" ]; then
    reject "could not create codex home $base"
  fi
  if [ ! -O "$base" ]; then
    reject "codex home $base is not owned by the calling user"
  fi

  perms=$(stat -c '%a' "$base")
  if [ "$perms" != "700" ]; then
    reject "codex home $base must be mode 0700, found $perms"
  fi

  # A crashed run leaves its directory behind. Each one is a few megabytes of
  # sqlite, so they must not accumulate.
  minutes=$(((MAX_BRIEF_AGE + 59) / 60))
  find "$base" -mindepth 1 -maxdepth 1 -type d -name 'run.*' \
    -mmin "+$minutes" -exec rm -rf -- {} + 2>/dev/null || true

  dir=$(mktemp -d "$base/run.XXXXXXXXXXXX") || reject "could not create a codex home"
  printf '%s' "$dir"
}

# Only ever removes a directory this script created, identified by the full
# prefix it was minted under.
discard_codex_home() {
  [ -n "$CODEX_RUN_HOME" ] || return 0
  case $CODEX_RUN_HOME in
    "$HOME/.cache/codex-team-review-home/run."*) ;;
    *) return 0 ;;
  esac
  [ ! -L "$CODEX_RUN_HOME" ] || return 0
  [ -d "$CODEX_RUN_HOME" ] || return 0
  rm -rf -- "$CODEX_RUN_HOME"
}

# Briefs describe unreleased work. A crashed run must not leave one behind
# indefinitely.
prune_stale_briefs() {
  local dir=$1 minutes
  minutes=$(((MAX_BRIEF_AGE + 59) / 60))
  find "$dir" -mindepth 1 -maxdepth 2 -type f \
    \( -name '*.brief' -o -name '*.issued' -o -name 'out.*' \) \
    -mmin "+$minutes" -delete 2>/dev/null || true
}

# Split a candidate brief path into its directory and basename using string
# comparison rather than a regex, so no interpolated value is ever treated as a
# pattern, and validate the basename shape exactly.
brief_basename() {
  local dir=$1 path=$2 rest

  case $path in
    "$dir"/*) rest=${path#"$dir"/} ;;
    *) return 1 ;;
  esac

  if [[ ! $rest =~ ^[0-9a-f]{32}\.brief$ ]]; then
    return 1
  fi

  printf '%s' "$rest"
}

CLAIM=""
CLAIM_INODE=""
OUTFILE=""
CODEX_RUN_HOME=""

# Remove the brief only if the inode still matches the one that was validated
# and consumed. Never unlink a path that something else has since substituted.
cleanup_claim() {
  local now
  [ -n "$CLAIM" ] || return 0
  [ -n "$CLAIM_INODE" ] || return 0
  [ -f "$CLAIM" ] || return 0
  [ ! -L "$CLAIM" ] || return 0

  now=$(stat -c '%i' "$CLAIM" 2>/dev/null || printf '')
  if [ -n "$now" ] && [ "$now" = "$CLAIM_INODE" ]; then
    rm -f -- "$CLAIM"
  fi
}

cleanup_run() {
  cleanup_claim
  discard_codex_home
  [ -n "$OUTFILE" ] && rm -f -- "$OUTFILE"
  [ -n "$ERRFILE" ] && rm -f -- "$ERRFILE"
  return 0
}

run_codex() {
  local workdir=$1 outfile=$2 errfile=$3 codexhome=$4

  # `set -e` is suspended for the whole body of a function whose exit status is
  # tested, and both call sites test it. So this cannot rely on an inner `exit`
  # to stop anything -- a failure has to be returned. It matters here more than
  # anywhere else in the script: codex reads an empty CODEX_HOME as unset and
  # falls back to ~/.codex, quietly restoring the injection this exists to
  # prevent, while still producing a review that looks entirely normal.
  if [ -z "$codexhome" ]; then
    printf 'codex-team-review: no private codex home; refusing to run\n' >&2
    return 70
  fi

  # What is actually isolated here, verified by capturing the outbound request:
  #
  #   * --ignore-user-config drops $CODEX_HOME/config.toml only. It does NOT
  #     drop instruction documents, which is why CODEX_HOME points at a
  #     directory minted for this run: the real ~/.codex/AGENTS.md is this
  #     module's own routing text, and a reviewer that reads it is reviewing
  #     against instructions it was supposed to judge independently.
  #   * project_doc_max_bytes=0 drops the AGENTS.md chain rooted at the
  #     workdir. Without it the repository under review supplies instructions
  #     to its own adversarial reviewer, which is a prompt-injection path.
  #   * mcp_servers={} plus the per-run CODEX_HOME leaves no server to launch.
  #   * --sandbox read-only blocks writes and network egress. It does not
  #     restrict reads: 0.145.0 has no read-confinement flag, and -C only sets
  #     the writable root. A review can read anything the user can read.
  #   * The --disable flags below made no observable difference to the request
  #     in testing -- multi-agent tools are still advertised with multi_agent
  #     disabled. They are kept as defence in depth, not relied upon. Codex
  #     validates the names, so an unknown one is a hard error rather than a
  #     silent no-op; that direction is fail-closed via `report`.
  #
  # The transcript goes to /dev/null and only the model's final message is
  # kept, so the caller reads findings rather than a replay of its own prompt.
  # Errors still surface on stderr.
  #
  # shellcheck disable=SC2016
  CODEX_HOME="$codexhome" timeout "$TIMEOUT" @codex@ \
    -c 'model="@model@"' \
    -c 'model_reasoning_effort="@effort@"' \
    -c 'model_provider="proxy"' \
    -c 'model_providers.proxy.name="Local Proxy"' \
    -c "model_providers.proxy.base_url=\"$BASE_URL\"" \
    -c 'mcp_servers={}' \
    -c 'shell_environment_policy.inherit="core"' \
    -c 'tools.web_search=false' \
    -c 'project_doc_max_bytes=0' \
    exec \
    --ignore-user-config \
    --sandbox read-only \
    --ephemeral \
    --skip-git-repo-check \
    --ignore-rules \
    --disable apps \
    --disable hooks \
    --disable multi_agent \
    --disable plugins \
    --disable browser_use \
    --disable computer_use \
    --disable in_app_browser \
    --disable image_generation \
    --color never \
    -C "$workdir" \
    --output-last-message "$outfile" \
    - >/dev/null 2>"$errfile"
}

usage() {
  cat >&2 <<'USAGE'
codex-team-review brief-dir
codex-team-review new-brief
codex-team-review design <brief-path from new-brief>
codex-team-review final <git-repository-directory>
USAGE
  exit 64
}

main() {
  local mode dir name

  [ "$#" -ge 1 ] || usage
  mode=$1
  shift

  case $mode in
    brief-dir)
      [ "$#" -eq 0 ] || reject "brief-dir takes no arguments"
      dir=$(resolve_brief_dir)
      printf '%s\n' "$dir"
      return 0
      ;;

    new-brief)
      [ "$#" -eq 0 ] || reject "new-brief takes no arguments"
      dir=$(resolve_brief_dir)
      prune_stale_briefs "$dir"
      name=$(od -An -tx1 -N16 /dev/urandom | tr -d ' \n')
      # The capability is the .issued marker, not the brief itself. Only this
      # wrapper can create one: the guard confines the agent's Write to names
      # matching <32 hex>.brief, so it has no way to mint a marker for a name
      # that was never handed out.
      #
      # The brief itself is deliberately left uncreated, so filling it in does
      # not require first reading an existing file.
      (umask 077 && : >"$dir/$name.issued")
      printf '%s/%s.brief\n' "$dir" "$name"
      return 0
      ;;

    design) design_review "$@" ;;
    final) final_review "$@" ;;
    *) reject "unknown mode '$mode'" ;;
  esac
}

design_review() {
  local target dir base issued claimdir perms size mtime age status output

  [ "$#" -eq 1 ] || reject "design takes exactly one brief path"
  target=$1

  dir=$(resolve_brief_dir)
  base=$(brief_basename "$dir" "$target") ||
    reject "brief path must be one issued by 'new-brief' under $dir"

  # Redeem the capability first, and redeem it exactly once. A name that was
  # never issued, or one already reviewed, has no marker and gets no further.
  issued=$dir/${base%.brief}.issued
  if [ -L "$issued" ] || [ ! -f "$issued" ] || [ ! -O "$issued" ]; then
    reject "brief path was not issued by 'new-brief', or has already been used"
  fi
  rm -f -- "$issued"

  if [ ! -e "$target" ] && [ ! -L "$target" ]; then
    reject "brief does not exist; run 'new-brief', write the brief to that path, then retry"
  fi

  claimdir=$dir/claimed
  (umask 077 && mkdir -p -- "$claimdir")
  CLAIM=$claimdir/$base

  if [ -e "$CLAIM" ] || [ -L "$CLAIM" ]; then
    CLAIM=""
    reject "brief has already been claimed"
  fi

  # Claim by rename before inspecting anything. After this the brief lives at a
  # name nothing else knows, which closes the gap between validating a path and
  # reading it.
  mv -n -- "$target" "$CLAIM"
  if [ ! -e "$CLAIM" ]; then
    CLAIM=""
    reject "could not claim brief"
  fi

  trap cleanup_run EXIT

  if [ -L "$CLAIM" ]; then
    rm -f -- "$CLAIM"
    CLAIM=""
    reject "brief is a symlink"
  fi
  if [ ! -f "$CLAIM" ]; then
    CLAIM=""
    reject "brief is not a regular file"
  fi
  if [ ! -O "$CLAIM" ]; then
    CLAIM=""
    reject "brief is not owned by the calling user"
  fi

  CLAIM_INODE=$(stat -c '%i' "$CLAIM")

  # More than one link means the same inode is reachable under another name,
  # which is how a hard link to a private file would arrive here.
  if [ "$(stat -c '%h' "$CLAIM")" != "1" ]; then
    reject "brief has multiple hard links"
  fi

  perms=$(stat -c '%a' "$CLAIM")
  if ((8#$perms & 8#022)); then
    reject "brief is group- or world-writable (mode $perms)"
  fi

  size=$(stat -c '%s' "$CLAIM")
  if [ "$size" -eq 0 ]; then
    reject "brief is empty"
  fi
  if [ "$size" -gt "$MAX_BRIEF_BYTES" ]; then
    reject "brief is $size bytes, over the $MAX_BRIEF_BYTES limit"
  fi

  mtime=$(stat -c '%Y' "$CLAIM")
  age=$(($(date +%s) - mtime))
  if [ "$age" -gt "$MAX_BRIEF_AGE" ]; then
    reject "brief is ${age}s old, over the ${MAX_BRIEF_AGE}s limit"
  fi

  # Codex runs with the private claim directory as its workspace, so it has
  # nowhere to write and no repository in view. Reads are a different matter:
  # read-only sandboxing in 0.145.0 constrains writes and network, not reads,
  # so this narrows what the review is pointed at, not what it could reach.
  OUTFILE=$(mktemp "$claimdir/out.XXXXXX")
  ERRFILE=$(mktemp "$claimdir/out.XXXXXX")

  # Minted here rather than inside run_codex: `set -e` is suspended in there,
  # so a rejection would be silently discarded. `|| exit` makes that impossible
  # to get wrong regardless of the caller's context.
  CODEX_RUN_HOME=$(new_codex_home) || exit $?
  [ -n "$CODEX_RUN_HOME" ] || reject "could not create a private codex home"

  status=0
  cat -- "$DESIGN_PREAMBLE" "$CLAIM" |
    run_codex "$claimdir" "$OUTFILE" "$ERRFILE" "$CODEX_RUN_HOME" || status=$?
  output=$(cat -- "$OUTFILE" 2>/dev/null || printf '')

  report "$status" "$output"
}

final_review() {
  local repo dir status output

  [ "$#" -eq 1 ] || reject "final takes exactly one repository directory"
  repo=$1

  if [[ ! $repo =~ ^(/[A-Za-z0-9._-]+)+$ ]]; then
    reject "repository path must be absolute and contain only [A-Za-z0-9._-] segments"
  fi
  if [ -L "$repo" ]; then
    reject "repository path is a symlink"
  fi
  if [ ! -d "$repo" ]; then
    reject "repository path is not a directory"
  fi
  # Reviewing "the working tree" only means something in a repository, and this
  # keeps a review from being pointed at an arbitrary directory of private files.
  if [ ! -e "$repo/.git" ]; then
    reject "repository path is not a git repository"
  fi

  dir=$(resolve_brief_dir)
  OUTFILE=$(mktemp "$dir/out.XXXXXX")
  ERRFILE=$(mktemp "$dir/out.XXXXXX")
  trap cleanup_run EXIT

  # See design_review: this must not be resolved inside run_codex.
  CODEX_RUN_HOME=$(new_codex_home) || exit $?
  [ -n "$CODEX_RUN_HOME" ] || reject "could not create a private codex home"

  status=0
  run_codex "$repo" "$OUTFILE" "$ERRFILE" "$CODEX_RUN_HOME" <"$FINAL_PREAMBLE" || status=$?
  output=$(cat -- "$OUTFILE" 2>/dev/null || printf '')

  report "$status" "$output"
}

report() {
  local status=$1 output=$2

  if [ "$status" -eq 124 ]; then
    unavailable "codex exceeded the ${TIMEOUT}s timeout"
  fi
  if [ "$status" -ne 0 ]; then
    unavailable "codex exited $status; the review proxy is unreachable or unauthenticated"
  fi
  if [ -z "${output//[[:space:]]/}" ]; then
    unavailable "codex returned no content"
  fi

  printf '%s\n' "$output"
}

main "$@"

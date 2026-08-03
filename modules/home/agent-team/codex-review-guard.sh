# shellcheck shell=bash
#
# PreToolUse gate for the Claude-only Codex agents.
#
# Frontmatter `tools:` is a tool-level allowlist and cannot scope Bash to one
# command, and Bash permission patterns are documented as fragile around
# operators and substitutions. So the enforcement point is this hook, which
# exits 2 to block the call before permission rules are consulted.
#
# Matching is exact-prefix plus a fixed shape, never a regex built from an
# interpolated value. Anything carrying an operator, a substitution, a redirect
# or an extra argument fails to match and is refused.

readonly WRAPPER='@wrapper@'

deny() {
  printf 'This agent may only run the fixed review commands.\n' >&2
  printf 'Refused %s: %s\n' "$1" "$2" >&2
  exit 2
}

mode=${1:-}
case $mode in
  design | final) ;;
  *)
    printf 'guard: invalid mode\n' >&2
    exit 2
    ;;
esac

# Every jq call is forced to produce a value even when it fails, because this
# hook only blocks on exit 2. Any other status -- jq's own exit 5 on malformed
# input, say -- is read as "not blocking" and the tool call proceeds. So parse
# failures must fall through to `deny`, never out of the script.
field() {
  printf '%s' "$payload" | jq -r "$1" 2>/dev/null || printf ''
}

payload=$(cat)
[ -n "$payload" ] || deny input 'empty hook payload'

tool=$(field '.tool_name // ""')
[ -n "$tool" ] || deny input 'unparseable hook payload'

# Fail closed: if the brief directory cannot be resolved, nothing is allowed.
brief_dir() {
  "$WRAPPER" brief-dir 2>/dev/null || true
}

# A path is acceptable only when it sits directly inside the wrapper's private
# directory and its name has the exact shape the wrapper issues.
is_brief_path() {
  local path=$1 dir rest

  dir=$(brief_dir)
  [ -n "$dir" ] || return 1

  case $path in
    "$dir"/*) rest=${path#"$dir"/} ;;
    *) return 1 ;;
  esac

  [[ $rest =~ ^[0-9a-f]{32}\.brief$ ]]
}

case $tool in
  Bash)
    command=$(field '.tool_input.command // ""')
    [ -n "$command" ] || deny Bash 'missing or unreadable command'

    if [ "$mode" = final ]; then
      case $command in
        "$WRAPPER final "*)
          rest=${command#"$WRAPPER final "}
          [[ $rest =~ ^(/[A-Za-z0-9._-]+)+$ ]] && exit 0
          ;;
      esac
      deny Bash "$command"
    fi

    [ "$command" = "$WRAPPER new-brief" ] && exit 0

    case $command in
      "$WRAPPER design "*)
        rest=${command#"$WRAPPER design "}
        is_brief_path "$rest" && exit 0
        ;;
    esac
    deny Bash "$command"
    ;;

  Write | Read)
    [ "$mode" = design ] || deny "$tool" "not permitted for this agent"
    path=$(field '.tool_input.file_path // ""')
    is_brief_path "$path" && exit 0
    deny "$tool" "$path"
    ;;

  *)
    deny "$tool" "tool not permitted"
    ;;
esac

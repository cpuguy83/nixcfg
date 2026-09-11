# shellcheck shell=bash
# Add session defaults, never session flags to utility commands. Keep explicit
# user choices (including --agents) rather than relying on duplicate-flag order.
defaults=()
# Prompts in the generated JSON may contain literal shell examples.
# shellcheck disable=SC2016
readonly agents='@agents@'
has_model=false
has_effort=false
has_agents=false
has_agent=false
utility=false
skip_value=false
for arg in "$@"; do
  if "$skip_value"; then
    skip_value=false
    continue
  fi
  case "$arg" in
    --) break ;;
    --model) has_model=true; skip_value=true ;;
    --model=*) has_model=true ;;
    --effort) has_effort=true; skip_value=true ;;
    --effort=*) has_effort=true ;;
    --agents) has_agents=true; skip_value=true ;;
    --agents=*) has_agents=true ;;
    --agent) has_agent=true; skip_value=true ;;
    --agent=*) has_agent=true ;;
    -h|--help|-v|--version) utility=true ;;
    agents|auth|auto-mode|doctor|gateway|import|install|mcp|plugin|plugins|project|setup-token|ultrareview|update|upgrade|help|completion)
      utility=true ;;
    --append-system-prompt|--autocompact|--debug-file|--environment|--fallback-model|--input-format|--json-schema|--max-budget-usd|--name|-n|--output-format|--permission-mode|--plugin-dir|--plugin-url|--remote-control-session-name-prefix|--session-id|--setting-sources|--settings|--system-prompt)
      skip_value=true ;;
  esac
done

if ! "$utility"; then
  # Selecting a role for the main session must retain that role's model/effort.
  if ! "$has_model" && ! "$has_agent"; then defaults+=(--model '@model@'); fi
  if ! "$has_effort" && ! "$has_agent"; then defaults+=(--effort '@effort@'); fi
  if ! "$has_agents" && [[ -n $agents ]]; then
    defaults+=(--agents "$agents")
  fi
fi

exec @claude@ "${defaults[@]}" "$@"

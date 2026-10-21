# writeShellApplication supplies Bash strict mode and runtime tools.
if [[ "$EUID" -eq 0 ]]; then
  printf '%s\n' 'agency-install: run as your normal user, not root.' >&2
  exit 1
fi

if [[ -z "${TMPDIR:-}" ]]; then
  printf '%s\n' 'agency-install: TMPDIR must be explicitly set to an existing writable directory.' >&2
  exit 1
fi

scratch="$(mktemp -d "$TMPDIR/nixcfg-agency-install.XXXXXX")"
cleanup() {
  local status=$?

  if ! rm -rf -- "$scratch"; then
    printf '%s\n' "agency-install: failed to clean scratch directory: $scratch" >&2
    if [[ "$status" -eq 0 ]]; then
      status=1
    fi
  fi

  exit "$status"
}
trap cleanup EXIT

script="$scratch/InstallTool.sh"
curl --fail --silent --show-error --location --output "$script" \
  https://aka.ms/InstallTool.sh

# Do not exec: the EXIT trap owns only our download directory, not upstream staging.
bash -e "$script" agency "$@"

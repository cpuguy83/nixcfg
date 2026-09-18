#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Statically-defined components handled by update_<name> functions below.
STATIC_COMPONENTS=(inputs buildx github tether)

# Per-component update scripts discovered anywhere below the repo root (any
# update.sh other than this one). Each such script owns its component's update
# logic — e.g. recomputing a vendorHash — so that logic lives next to the
# package instead of accreting in this file. The component name is the parent
# directory's basename.
declare -A DISCOVERED
_discover() {
	local script name
	while IFS= read -r script; do
		name="$(basename "$(dirname "${script}")")"
		DISCOVERED["${name}"]="${script}"
	done < <(find . -mindepth 2 -type f -name update.sh | sort)
}
_discover

# Update every flake input to its latest locked revision. Components that pin a
# tag in flake.nix (buildx, github) stay on their pinned tag here; bumping the
# tag is the job of their dedicated update functions.
update_inputs() {
	nix flake update
}

update_buildx() {
	local buildx_ref
	buildx_ref="$(gh release view --repo docker/buildx --json tagName --jq .tagName)"
	sed -i -E "s|(github:docker/buildx\?ref=refs/tags/)v[0-9.]+|\1${buildx_ref}|" flake.nix
	nix flake update buildx
}

update_github() {
	local gh_app_ref
	gh_app_ref="$(gh release view --repo github/app --json tagName --jq .tagName)"
	sed -i -E "s|(releases/download/)v[0-9.]+(/GitHub-Copilot-linux-x64\.deb)|\1${gh_app_ref}\2|" flake.nix
	nix flake update github-copilot-deb
}

update_tether() {
	ref="$(gh release view --repo zackb/tether --json tagName --jq .tagName)"
	sed -i -E "s|(github:zackb/tether\?ref=refs/tags/)v[0-9.]+|\1${ref}|" flake.nix
	nix flake update tether
}

# Resolve a component name to something runnable: a static update_<name>
# function, or a discovered per-package update.sh.
is_component() {
	local name="$1"
	declare -F "update_${name}" >/dev/null || [ -n "${DISCOVERED[${name}]:-}" ]
}

run_component() {
	local name="$1"
	if declare -F "update_${name}" >/dev/null; then
		"update_${name}"
	else
		bash "${DISCOVERED[${name}]}"
	fi
}

usage() {
	cat >&2 <<EOF
Usage: ${0##*/} [component...]

Update flake inputs / pinned versions for individual components.

Components:
  inputs    Update every flake input to its latest locked revision
  buildx    Bump the Docker Buildx input to the latest release tag
  github    Bump the GitHub Copilot deb to the latest release
EOF
	local name
	for name in "${!DISCOVERED[@]}"; do
		printf '  %-9s Run %s\n' "${name}" "${DISCOVERED[${name}]#./}" >&2
	done
	cat >&2 <<EOF
  all       Update every component (default when none are given)

Examples:
  ${0##*/}                 # update all
  ${0##*/} all             # update all
  ${0##*/} inputs vekil    # update inputs, then recompute vekil's vendorHash
EOF
}

main() {
	if [ "$#" -eq 0 ]; then
		set -- all
	fi

	local to_run=()
	local arg
	for arg in "$@"; do
		case "$arg" in
			-h | --help)
				usage
				return 0
				;;
			all)
				# Static components first (inputs bumps the flake), then the
				# discovered scripts, which may depend on freshly-updated inputs.
				to_run=("${STATIC_COMPONENTS[@]}" "${!DISCOVERED[@]}")
				break
				;;
			*)
				if is_component "${arg}"; then
					to_run+=("${arg}")
				else
					echo "Unknown component: ${arg}" >&2
					usage
					return 1
				fi
				;;
		esac
	done

	local component
	for component in "${to_run[@]}"; do
		echo "==> Updating ${component}" >&2
		run_component "${component}"
	done
}

main "$@"

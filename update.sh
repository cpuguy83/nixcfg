#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

COMPONENTS=(inputs vscode buildx github)

# Update every flake input to its latest locked revision. Components that pin a
# tag in flake.nix (buildx, github) stay on their pinned tag here; bumping the
# tag is the job of their dedicated update functions.
update_inputs() {
	nix flake update
}

update_vscode() {
	./overlays/vscode_update.sh
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

usage() {
	cat >&2 <<EOF
Usage: ${0##*/} [component...]

Update flake inputs / pinned versions for individual components.

Components:
  inputs    Update every flake input to its latest locked revision
  vscode    Update the VS Code overlay sha256
  buildx    Bump the Docker Buildx input to the latest release tag
  github    Bump the GitHub Copilot deb to the latest release
  all       Update every component (default when none are given)

Examples:
  ${0##*/}                 # update all
  ${0##*/} all             # update all
  ${0##*/} vscode buildx   # update only vscode and buildx
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
				to_run=("${COMPONENTS[@]}")
				break
				;;
			vscode | buildx | github)
				to_run+=("$arg")
				;;
			*)
				echo "Unknown component: ${arg}" >&2
				usage
				return 1
				;;
		esac
	done

	local component
	for component in "${to_run[@]}"; do
		echo "==> Updating ${component}" >&2
		"update_${component}"
	done
}

main "$@"

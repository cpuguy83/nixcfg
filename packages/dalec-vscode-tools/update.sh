#!/usr/bin/env bash

# Bump the pinned DALEC VSCode Tools extension to the latest marketplace
# release and recompute its VSIX hash.
#
# The extension isn't in nixpkgs, so we pin version + hash in default.nix. This
# queries the VS Code Marketplace for the current version, rewrites it, then
# forces a fixed-output hash mismatch and reads the real hash from the build
# error — the same trick the vekil vendorHash updater uses.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NIX_FILE="${SCRIPT_DIR}/default.nix"

EXT="ms-kubernetes-tools.dalec-vscode-tools"
ATTR='.#nixosConfigurations.yavin4.pkgs.vscode-extensions.ms-kubernetes-tools.dalec-vscode-tools'

# nixpkgs lib.fakeHash: valid-shaped SRI hash that never matches.
FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

set_field() {
	# set_field <field> <value> — rewrite `<field> = "..."` in default.nix.
	sed -i -E "s|(${1} = \")[^\"]+(\";)|\1${2}\2|" "${NIX_FILE}"
}

latest="$(
	curl -s 'https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery' \
		-H 'Accept: application/json;api-version=3.0-preview.1' \
		-H 'Content-Type: application/json' \
		--data "{\"filters\":[{\"criteria\":[{\"filterType\":7,\"value\":\"${EXT}\"}]}],\"flags\":914}" |
		jq -r '.results[0].extensions[0].versions[0].version'
)"

if [ -z "${latest}" ] || [ "${latest}" = "null" ]; then
	echo "dalec-vscode-tools: failed to determine latest version" >&2
	exit 1
fi

set_field version "${latest}"

# Force a mismatch so the build error reports the real hash. The flake only sees
# git-tracked files, so make sure default.nix is visible before building.
set_field hash "${FAKE_HASH}"
cd "${REPO_ROOT}"
git add --intent-to-add "${NIX_FILE}" 2>/dev/null || true

new_hash="$(
	{ nix build --no-link "${ATTR}" 2>&1 || true; } |
		awk '/got:/ { print $NF }'
)"

if [ -z "${new_hash}" ]; then
	echo "dalec-vscode-tools: failed to determine hash for version ${latest}" >&2
	exit 1
fi

set_field hash "${new_hash}"
echo "dalec-vscode-tools: version = ${latest}, hash = ${new_hash}" >&2

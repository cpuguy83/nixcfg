#!/usr/bin/env bash

# Recompute vekil's Go module vendorHash and write it to vendor.sha256.
#
# vekil tracks the branch tip (github:sozercan/vekil, flake=false), so every
# `nix flake update` can change the module set and invalidate the pinned
# vendorHash. Rather than hand-editing the derivation, we force a hash mismatch
# with a fake hash and read the real one back out of the build error.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HASH_FILE="${SCRIPT_DIR}/vendor.sha256"

# nixpkgs lib.fakeHash: a valid-shaped SRI hash that never matches, forcing the
# fixed-output module derivation to fail with the real hash in its error.
FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

cd "${REPO_ROOT}"

printf '%s\n' "${FAKE_HASH}" >"${HASH_FILE}"

# The flake only sees git-tracked files; make sure a freshly-added hash file is
# visible to the evaluation before we build against it.
git add --intent-to-add "${HASH_FILE}" 2>/dev/null || true

new_hash="$(
	{ nix build --no-link '.#nixosConfigurations.yavin4.pkgs.vekil.goModules' 2>&1 || true; } |
		awk '/got:/ { print $NF }'
)"

if [ -z "${new_hash}" ]; then
	echo "vekil: failed to determine vendorHash (build did not report a mismatch)" >&2
	exit 1
fi

printf '%s\n' "${new_hash}" >"${HASH_FILE}"
echo "vekil: vendorHash = ${new_hash}" >&2

#!/usr/bin/env bash

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NIX_FILE="${SCRIPT_DIR}/vscode.nix"

URL="$(awk -F '"' '/url[[:space:]]*=/{print $2; exit}' "${NIX_FILE}")"
if [ -z "$URL" ]; then
    echo "Failed to extract URL from vscode.nix"
    exit 1
fi

echo "Prefetching $URL …" >&2
NEW_HASH=$(nix-prefetch-url --type sha256 --unpack "$URL" --name "vscode.tar.gz")

echo "Updating sha256 in $NIX_FILE" >&2
sed -i "s|sha256 = \".*\"|sha256 = \"$NEW_HASH\"|g" "$NIX_FILE"
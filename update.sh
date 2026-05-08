#!/usr/bin/env bash

set -euo pipefail

buildx_ref="$(gh release view --repo docker/buildx --json tagName --jq .tagName)"

nix flake update --override-input buildx "git+https://github.com/docker/buildx?ref=refs/tags/${buildx_ref}"
./overlays/vscode_update.sh

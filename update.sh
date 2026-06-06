#!/usr/bin/env bash

set -euo pipefail

buildx_ref="$(gh release view --repo docker/buildx --json tagName --jq .tagName)"

nix flake update --override-input buildx "git+https://github.com/docker/buildx?ref=refs/tags/${buildx_ref}"
./overlays/vscode_update.sh

gh_app_ref="$(gh release view --repo github/app --json tagName --jq .tagName)"
sed -i -E "s|(releases/download/)v[0-9.]+(/GitHub-Copilot-linux-x64\.deb)|\1${gh_app_ref}\2|" flake.nix
nix flake update github-copilot-deb

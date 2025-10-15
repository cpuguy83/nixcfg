#!/usr/bin/env bash

set -e

nix flake update
./overlays/vscode_update.sh

#!/usr/bin/env bash
set -euo pipefail

verbose=0
if [[ "${1:-}" == "-v" ]]; then
  verbose=1
  shift
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: nix-unwrap [-v] <command>" >&2
  exit 1
fi

target="$1"

# Resolve command name to path
if [[ ! -e "$target" ]]; then
  resolved="$(command -v "$target" 2>/dev/null || true)"
  if [[ -z "$resolved" ]]; then
    echo "nix-unwrap: command not found: $target" >&2
    exit 1
  fi
  target="$resolved"
fi

for (( i=0; i<50; i++ )); do
  # Resolve symlinks
  real="$(readlink -f "$target")"
  if [[ "$real" != "$target" && $verbose -eq 1 ]]; then
    echo "symlink: $target -> $real" >&2
  fi
  target="$real"

  filetype="$(file -b "$target")"

  # If it's an ELF binary, we're done
  if [[ "$filetype" == ELF* ]]; then
    if [[ $verbose -eq 1 ]]; then
      echo "found ELF: $target" >&2
    fi
    echo "$target"
    exit 0
  fi

  # Shell script wrapper: look for exec lines pointing into /nix/store
  if [[ "$filetype" == *text* || "$filetype" == *script* ]]; then
    # Try to find an exec line and extract the /nix/store path from it
    exec_line="$(grep -P '^\s*exec\s' "$target" | tail -1 || true)"
    if [[ -n "$exec_line" ]]; then
      next="$(echo "$exec_line" | grep -oP '/nix/store/[^\s"'\'']+' | head -1 || true)"
    fi

    if [[ -z "$next" ]]; then
      # Fallback: any /nix/store/.../bin/... path in the script
      next="$(grep -oP '/nix/store/[a-z0-9]{32}-[^/]+/bin/[^\s"'\'']+' "$target" \
        | tail -1 || true)"
    fi

    if [[ -n "$next" ]]; then
      if [[ $verbose -eq 1 ]]; then
        echo "shell wrapper: $target -> $next" >&2
      fi
      target="$next"
      continue
    fi

    # No further wrapper found; this text file is the final target
    if [[ $verbose -eq 1 ]]; then
      echo "terminal script: $target" >&2
    fi
    echo "$target"
    exit 0
  fi

  # Binary wrapper (makeBinaryWrapper): extract /nix/store paths via strings
  next="$(strings "$target" \
    | grep -oP '/nix/store/[a-z0-9]{32}-[^/]+/bin/[^\s"'\'']+' \
    | head -1 || true)"

  if [[ -n "$next" ]]; then
    if [[ $verbose -eq 1 ]]; then
      echo "binary wrapper: $target -> $next" >&2
    fi
    target="$next"
    continue
  fi

  # Nothing more to unwrap
  if [[ $verbose -eq 1 ]]; then
    echo "terminal: $target ($filetype)" >&2
  fi
  echo "$target"
  exit 0
done

echo "nix-unwrap: too many layers (50), giving up at: $target" >&2
exit 1

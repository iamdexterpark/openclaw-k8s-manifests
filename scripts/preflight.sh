#!/usr/bin/env bash
# preflight.sh — verify the toolchain needed to validate this repo's deliverable.
# Prints the install command for anything missing, then exits non-zero. (F4)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
missing=0

need() { # need <bin> <install-hint>
  if command -v "$1" >/dev/null 2>&1; then
    echo "  ✓ $1"
  else
    echo "  ✗ $1 not found — install: $2" >&2
    missing=1
  fi
}

want() { # want <bin> <install-hint>  (optional: warn, never fail)
  if command -v "$1" >/dev/null 2>&1; then
    echo "  ✓ $1"
  else
    echo "  — $1 not found (optional) — install when needed: $2"
  fi
}

# Always needed.
need python3 "brew install python3"

# Deliverable-specific.
if [ -d manifests ]; then
  need kustomize "brew install kustomize"
  want kubectl   "brew install kubectl   # needed to apply, not to build"
elif [ -d terraform ]; then
  need terraform "brew install terraform"
fi

[ "$missing" -eq 0 ] && echo "✓ preflight clean" || exit 1

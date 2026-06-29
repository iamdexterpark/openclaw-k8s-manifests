#!/usr/bin/env bash
# validate.sh — local mirror of the CI gate. Exits non-zero on any failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
fail=0

echo "==> 0/3  Preflight (toolchain)"
bash scripts/preflight.sh || { echo "✗ preflight failed — install missing tools above." >&2; exit 1; }

echo "==> 1/3  Doc-sync check (diagrams injected)"
# F5: don't trust `git diff` on a fresh/untracked repo (untracked files read as 'unchanged').
# Run the injector, then run it AGAIN and assert the second pass reports no work to do.
python3 scripts/build_docs.py >/dev/null
if python3 scripts/build_docs.py | grep -qiE 'updated|injected|changed'; then
  echo "✗ Docs out of sync — build_docs.py still had work on a second pass. Commit the result." >&2
  fail=1
else
  echo "✓ Docs in sync (idempotent second pass clean)"
fi

echo "==> 2/3  Deliverable lint/build"
if [ -d manifests ]; then
  # Kustomize: every overlay/base/platform must build; production overlays must render a digest pin.
  shopt -s nullglob
  for k in manifests/platform manifests/base manifests/overlays/*/; do
    [ -f "$k/kustomization.yaml" ] || continue
    if kustomize build "$k" >/dev/null; then echo "  ✓ kustomize build $k"; else echo "  ✗ kustomize build $k" >&2; fail=1; fi
  done
  # Assert production overlays pin by @sha256 (F3: a base rename can silently drop the overlay digest).
  for o in manifests/overlays/*/; do
    [ -f "$o/kustomization.yaml" ] || continue
    if kustomize build "$o" 2>/dev/null | grep -q 'image:.*@sha256:'; then
      echo "  ✓ digest-pinned: $o"
    else
      echo "  ⚠ no @sha256 digest in rendered image for $o (placeholder ok pre-fill; real overlays MUST pin)"
    fi
  done
elif [ -d terraform ]; then
  ( cd terraform && terraform fmt -check -recursive && terraform validate )
else
  echo "  (no recognized deliverable dir — nothing to build)"
fi

echo "==> 3/3  Secret-leak scan (value-bearing files only)"
if git grep -nIE \
   '(BEGIN [A-Z ]*PRIVATE KEY|AKIA[0-9A-Z]{16}|password\s*[:=]\s*["'\'']?[^"'\'' ]{6,})' \
   -- . ':!*.md' ':!docs/**' 2>/dev/null; then
  echo "✗ Possible secret material in tracked files." >&2
  fail=1
else
  echo "✓ No obvious secret material"
fi

[ "$fail" -eq 0 ] && echo "✅ validate passed" || { echo "❌ validate failed"; exit 1; }

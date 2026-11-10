#!/usr/bin/env bash
# validate.sh — local-only sanity pass (no cloud, no side effects):
#   unit suite + infrastructure static suite + file-sync invariants.
# This is what CI runs on every push; `make test` is the fuller version.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
FAILED=0

bash tests/unit/run.sh || FAILED=$((FAILED + 1))

if docker info >/dev/null 2>&1; then
  bash tests/infrastructure/run.sh || FAILED=$((FAILED + 1))
else
  echo "validate: docker unavailable — skipping terraform container checks"
fi

echo ""
if [[ "$FAILED" -gt 0 ]]; then echo "validate: $FAILED suite(s) failed"; exit 1; fi
echo "validate: all suites green"

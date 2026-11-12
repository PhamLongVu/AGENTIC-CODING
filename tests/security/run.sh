#!/usr/bin/env bash
# SECURITY suite: auth, gateway hardening, container isolation.
# Local-only (mock mode). Complements tests/integration (which also asserts
# hardening properties in passing); this suite is the deliberate, adversarial
# pass required by docs/architecture/security-model.md §test-matrix.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source tests/lib/env.sh
source scripts/lib/deploy-log.sh

[[ -s .coder-session ]] || { echo "security: no admin session — run: make bootstrap" >&2; exit 2; }
[[ "$AI_PROVIDER_MODE" == "mock" ]] || { echo "security: mock mode only" >&2; exit 2; }

FAILED=0
dlog_section "make test-security"
for t in tests/security/test_*.sh; do
  echo ""
  echo "===================================================================="
  echo "  $t"
  echo "===================================================================="
  dlog "run $t"
  if ! bash "$t"; then
    FAILED=$((FAILED + 1))
    echo "  >>> SUITE FAIL: $t"
    dlog "FAIL $t"
  else
    dlog "PASS $t"
  fi
done
dlog "note: test_container_isolation spins short-lived probe containers (docker run --rm) — removed on exit by design"

echo ""
[[ $FAILED -eq 0 ]] && echo "security: all test files passed" || { echo "security: $FAILED test file(s) FAILED"; exit 1; }

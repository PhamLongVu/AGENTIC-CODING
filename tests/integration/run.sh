#!/usr/bin/env bash
# Local INTEGRATION suite (mock AI mode). Requires the platform stack
# running (make up && make bootstrap); it will refuse otherwise.
# Never touches AWS. Tests are independent and run in order; every failure
# is reported but the suite exits non-zero at the end.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source tests/lib/env.sh

# --- preconditions -------------------------------------------------------------
if ! docker compose ps --format json 2>/dev/null | jq -se 'length > 0' >/dev/null 2>&1; then
  echo "integration: platform stack not running — run: make up && make bootstrap" >&2
  exit 2
fi
for svc in postgres litellm coder; do
  state="$(docker compose ps "$svc" --format '{{.Health}}')"
  if [[ "$state" != "healthy" ]]; then
    echo "integration: service '$svc' is '$state' (want healthy)" >&2
    exit 2
  fi
done
[[ -s .coder-session ]] || { echo "integration: no admin session — run: make bootstrap" >&2; exit 2; }
if [[ "$AI_PROVIDER_MODE" != "mock" ]]; then
  echo "integration: refusing to run with AI_PROVIDER_MODE=$AI_PROVIDER_MODE (mock only)" >&2
  exit 2
fi

FAILED=0
for t in tests/integration/test_*.sh; do
  echo ""
  echo "===================================================================="
  echo "  $t"
  echo "===================================================================="
  if ! bash "$t"; then
    FAILED=$((FAILED + 1))
    echo "  >>> SUITE FAIL: $t"
  fi
done

echo ""
if [[ $FAILED -gt 0 ]]; then
  echo "integration: $FAILED test file(s) FAILED"
  exit 1
fi
echo "integration: all test files passed"

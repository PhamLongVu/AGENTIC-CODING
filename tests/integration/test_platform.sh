#!/usr/bin/env bash
# Platform stack health: services, databases, coder API, admin auth.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source tests/lib/env.sh
source tests/lib/assertions.sh
source tests/lib/coder.sh

echo "== platform: compose services healthy =="
for svc in postgres litellm coder; do
  state="$(docker compose ps "$svc" --format '{{.Health}}')"
  assert_eq "$state" "healthy" "$svc container healthy"
done

echo "== platform: application databases exist =="
dbs="$(docker compose exec -T postgres psql -U "${POSTGRES_USER:-platform_admin}" -d postgres -tAc \
  "SELECT datname FROM pg_database WHERE datname IN ('coder','litellm') ORDER BY 1" | tr '\n' ' ' | xargs)"
assert_eq "$dbs" "coder litellm" "coder + litellm databases created by init script"

echo "== platform: coder API identity =="
BI="$(curl -fsS "$CODER_API_URL/api/v2/buildinfo")"
assert_contains "$(echo "$BI" | jq -r .version)" "v2.36.3" "coder version matches pinned image tag"

echo "== platform: admin authentication =="
ME="$(coder_api GET /api/v2/users/me)"
assert_eq "$(echo "$ME" | jq -r .username)" "$CODER_ADMIN_USER" "admin session resolves to bootstrap user"
assert_contains "$(echo "$ME" | jq -c '[.roles[].name]')" "owner" "admin has owner role"

BAD="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$CODER_API_URL/api/v2/users/login" \
  -H 'Content-Type: application/json' -d '{"email":"nobody@example.invalid","password":"wrong"}')"
assert_eq "$BAD" "401" "wrong credentials rejected with 401"

echo "== platform: bootstrap idempotency (re-run must succeed) =="
assert_cmd "make bootstrap exits 0" make bootstrap

finish_suite "test_platform"

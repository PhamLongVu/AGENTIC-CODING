#!/usr/bin/env bash
# Authentication surface: no self-registration, bad logins rejected,
# API requires session, app proxy does not serve unauthenticated requests.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source tests/lib/env.sh
source tests/lib/assertions.sh
source tests/lib/coder.sh

echo "== auth: no anonymous API access =="
code="$(curl -s -o /dev/null -w '%{http_code}' "$CODER_API_URL/api/v2/users/me")"
assert_eq "$code" "401" "users/me without session -> 401"

echo "== auth: bad credentials rejected =="
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$CODER_API_URL/api/v2/users/login" \
  -H 'Content-Type: application/json' -d "{\"email\":\"$CODER_ADMIN_EMAIL\",\"password\":\"definitely-wrong\"}")"
assert_eq "$code" "401" "wrong password -> 401"

echo "== auth: no self-registration (owner-only user creation) =="
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$CODER_API_URL/api/v2/users" \
  -H 'Content-Type: application/json' \
  -d '{"username":"selfsignup","email":"self@example.invalid","password":"password123","login_type":"password"}')"
assert_eq "$code" "401" "user creation without admin session -> 401"

DEMO_USER="dev-$(date +%s)"
DEMO_PASS="devuser-pass-1"
OUT="$(coder_api POST /api/v2/users "{\"username\":\"$DEMO_USER\",\"email\":\"$DEMO_USER@example.invalid\",\"password\":\"$DEMO_PASS\",\"login_type\":\"password\"}")"
assert_contains "$OUT" '"id"' "admin can create developer users (operator onboarding path)"
cleanup() { coder_api DELETE "/api/v2/users/$(echo "$OUT" | jq -r .id)/workspaces" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== auth: developer login works with operator-issued credentials =="
TOK="$(curl -s -X POST "$CODER_API_URL/api/v2/users/login" -H "Content-Type: application/json" \
  -d "{\"email\":\"$DEMO_USER@example.invalid\",\"password\":\"$DEMO_PASS\"}" | jq -r '.session_token // empty')"
assert_not_contains "$TOK" "" "developer session issued"

echo "== auth: developer is NOT an owner =="
ROLES="$(curl -s -H "Authorization: Bearer $TOK" "$CODER_API_URL/api/v2/users/me" | jq -c '[.roles[].name]')"
assert_not_contains "$ROLES" "owner" "developer lacks owner role"
code="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOK" \
  -X POST "$CODER_API_URL/api/v2/users" -H 'Content-Type: application/json' \
  -d '{"username":"another","email":"a@example.invalid","password":"password123","login_type":"password"}')"
[[ "$code" != "2"* ]] && _t_ok "developer cannot create users ($code)" || _t_fail "developer created a user!"

echo "== auth: app proxy requires coder session =="
# unauthenticated fetch of a (possibly nonexistent) workspace app path must
# not return 200 application content
code="$(curl -s -o /dev/null -w '%{http_code}' "$CODER_ACCESS_URL/@$CODER_ADMIN_USER/x/apps/code-server/")"
[[ "$code" != "200" ]] && _t_ok "app path without session not served ($code)" || _t_fail "app proxy served anonymous request"

finish_suite "test_auth"

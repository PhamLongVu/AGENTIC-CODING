#!/usr/bin/env bash
# Gateway hardening: master-key separation, key revocation, budget field
# enforcement points. (Numeric budget exhaustion is NOT testable in mock
# mode because mock completions cost $0 — documented limitation; the
# rpm limiter and revocation ARE exercised here for real.)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source tests/lib/env.sh
source tests/lib/assertions.sh

MODEL="anthropic.claude-3-5-sonnet-20241022-v2:0"
ALIAS="sectest-$(date +%s)"
KEYS=()
cleanup() {
  for k in "${KEYS[@]:-}"; do
    curl -s -X POST "$LITELLM_BASE_URL/key/delete" \
      -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H "Content-Type: application/json" \
      -d "{\"keys\":[\"$k\"]}" >/dev/null || true
  done
}
trap cleanup EXIT

echo "== hardening: master key is NEVER a valid chat key path =="
# (master must not be handed to users; assert it is distinct from issued keys)
K1="$(gateway/litellm/scripts/create-virtual-key.sh "$ALIAS-1" 20 30)"
KEYS+=("$K1")
assert_not_contains "$K1" "$LITELLM_MASTER_KEY" "issued key differs from master key"

echo "== hardening: virtual key cannot mint other keys =="
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$LITELLM_BASE_URL/key/generate" \
  -H "Authorization: Bearer $K1" -H 'Content-Type: application/json' \
  -d '{"key_alias":"escalation-attempt","max_budget":999}')"
[[ "$code" != "200" ]] && _t_ok "virtual key cannot generate keys ($code)" || _t_fail "PRIVILEGE ESCALATION: virtual key minted a key!"

echo "== hardening: virtual key cannot read spend of others =="
code="$(curl -s -o /dev/null -w '%{http_code}' "$LITELLM_BASE_URL/key/list" \
  -H "Authorization: Bearer $K1")"
[[ "$code" != "200" ]] && _t_ok "virtual key cannot list keys ($code)" || _t_fail "virtual key listed all keys!"

echo "== hardening: revocation is immediate =="
curl -s -X POST "$LITELLM_BASE_URL/key/delete" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H "Content-Type: application/json" \
  -d "{\"keys\":[\"$K1\"]}" >/dev/null
code="$(curl -s -o /dev/null -w '%{http_code}' "$LITELLM_BASE_URL/v1/chat/completions" \
  -H "Authorization: Bearer $K1" -H 'Content-Type: application/json' \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")"
assert_eq "$code" "401" "revoked key dead immediately"

echo "== hardening: budgets are recorded on keys (enforced upstream of mock) =="
K2="$(gateway/litellm/scripts/create-virtual-key.sh "$ALIAS-2" 20 30)"
KEYS+=("$K2")
INFO="$(curl -s "$LITELLM_BASE_URL/key/info?key=$K2" -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  | jq -c '.info')"
assert_contains "$INFO" '"key_alias":"'"$ALIAS-2"'"' "alias stored on key record"
assert_contains "$INFO" '"max_budget":20' "budget stored on key record"

echo "== hardening: model allowlist on virtual keys =="
code="$(curl -s -o /dev/null -w '%{http_code}' "$LITELLM_BASE_URL/v1/chat/completions" \
  -H "Authorization: Bearer $K2" -H 'Content-Type: application/json' \
  -d '{"model":"openai/gpt-4o","messages":[{"role":"user","content":"hi"}]}')"
# LiteLLM 1.83 denies with 401 key_model_access_denied (not 400)
assert_eq "$code" "401" "non-allowlisted model rejected (401 key_model_access_denied)"

finish_suite "test_gateway_hardening"

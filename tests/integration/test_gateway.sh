#!/usr/bin/env bash
# AI gateway (LiteLLM, DB mode, mock provider): health, virtual keys,
# completions, rejection, rate-limit enforcement, key isolation.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source tests/lib/env.sh
source tests/lib/assertions.sh

MODEL="anthropic.claude-3-5-sonnet-20241022-v2:0"
KEY_ALIAS="itest-$(date +%s)"
TMP_KEYS=()

new_key() {  # new_key <budget> <rpm> [tpm] -> prints key
  # Alias encodes budget AND rpm — two keys with equal budgets but different
  # rpm limits must not collide on the alias (usage assertions select by it).
  gateway/litellm/scripts/create-virtual-key.sh "$KEY_ALIAS-b$1-r$2" "$1" "$2" "${3:-100000}"
}

cleanup() {
  for k in "${TMP_KEYS[@]:-}"; do
    curl -s -X POST "$LITELLM_BASE_URL/key/delete" \
      -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
      -H "Content-Type: application/json" -d "{\"keys\":[\"$k\"]}" >/dev/null || true
  done
}
trap cleanup EXIT

echo "== gateway: health =="
code="$(curl -s -o /dev/null -w '%{http_code}' "$LITELLM_BASE_URL/health/liveliness")"
assert_eq "$code" "200" "health/liveliness returns 200"

echo "== gateway: virtual key + mock completion =="
KEY="$(new_key 20 30)"
TMP_KEYS+=("$KEY")
BODY="$(curl -s "$LITELLM_BASE_URL/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}")"
assert_contains "$(echo "$BODY" | jq -r '.choices[0].message.content // empty')" "MOCK RESPONSE" \
  "chat completion served by mock provider"
assert_eq "$(echo "$BODY" | jq -r .model)" "$MODEL" "requested model echoed"

echo "== gateway: rejection =="
code="$(curl -s -o /dev/null -w '%{http_code}' "$LITELLM_BASE_URL/v1/chat/completions" \
  -H "Authorization: Bearer sk-bogus-key" -H "Content-Type: application/json" \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")"
assert_eq "$code" "401" "invalid virtual key rejected with 401"

code="$(curl -s -o /dev/null -w '%{http_code}' "$LITELLM_BASE_URL/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"model":"gpt-4o","messages":[{"role":"user","content":"hi"}]}')"
# LiteLLM 1.83 denies non-allowlisted models with 401 key_model_access_denied
assert_eq "$code" "401" "model not on key allowlist rejected (401 key_model_access_denied)"

echo "== gateway: virtual key CANNOT use admin API =="
code="$(curl -s -o /dev/null -w '%{http_code}' "$LITELLM_BASE_URL/key/list" \
  -H "Authorization: Bearer $KEY")"
[[ "$code" != "200" ]] && _t_ok "virtual key denied on /key/list ($code)" || _t_fail "virtual key could list keys!"

echo "== gateway: rpm enforcement =="
RL_KEY="$(new_key 20 1)"
TMP_KEYS+=("$RL_KEY")
codes=()
for _ in 1 2 3 4 5 6; do
  codes+=("$(curl -s -o /dev/null -w '%{http_code}' "$LITELLM_BASE_URL/v1/chat/completions" \
    -H "Authorization: Bearer $RL_KEY" -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")")
done
limited="$(printf '%s\n' "${codes[@]}" | grep -c '^429$' || true)"
assert_contains "$((limited > 0 ? 1 : 0))" "1" "rpm=1 key hits 429 under burst (got: ${codes[*]})"

echo "== gateway: usage tracking =="
# /key/list returns bare key strings in LiteLLM 1.83; per-key record is /key/info
INFO="$(curl -s "$LITELLM_BASE_URL/key/info?key=$KEY" -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  | jq -c '.info')"
assert_contains "$INFO" '"key_alias":"'"$KEY_ALIAS"'-b20-r30"' "key record has configured alias"
assert_contains "$INFO" '"max_budget":20' "key records configured budget"
assert_contains "$INFO" '"rpm_limit":30' "key records configured rpm_limit"
SPEND="$(echo "$INFO" | jq -r '.spend // 0')"
assert_contains "$(awk -v s="$SPEND" 'BEGIN{print (s>=0)?1:0}')" "1" "spend field present and >= 0"

echo "== gateway: key revocation =="
curl -s -X POST "$LITELLM_BASE_URL/key/delete" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H "Content-Type: application/json" \
  -d "{\"keys\":[\"$KEY\"]}" >/dev/null
code="$(curl -s -o /dev/null -w '%{http_code}' "$LITELLM_BASE_URL/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}")"
assert_eq "$code" "401" "revoked key immediately rejected"

finish_suite "test_gateway"

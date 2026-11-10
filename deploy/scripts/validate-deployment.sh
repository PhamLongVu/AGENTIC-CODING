#!/usr/bin/env bash
# =============================================================================
# validate-deployment.sh — post-deploy validation, run ON the EC2 instance.
# =============================================================================
# Includes the AWS-only security tests that CANNOT run locally:
#   * IMDS unreachable from a bridge-network container (hop limit 1)
#   * LiteLLM (host net) CAN reach IMDS and assume the instance role
#   * external exposure: only 22/7080 answer; 4000 must NOT
# Exit non-zero on any failure. Never prints secrets.
# =============================================================================
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source tests/lib/env.sh
source tests/lib/assertions.sh

echo "== validate: platform containers healthy =="
for svc in postgres litellm coder; do
  state="$(docker compose -f docker-compose.yml -f deploy/compose/aws.yml ps "$svc" --format '{{.Health}}' 2>/dev/null)"
  assert_eq "$state" "healthy" "$svc healthy"
done

echo "== validate: coder reachable at its public URL =="
code="$(curl -s -o /dev/null -w '%{http_code}' "$CODER_ACCESS_URL/api/v2/buildinfo")"
assert_eq "$code" "200" "public CODER_ACCESS_URL serves buildinfo"

echo "== validate: SECURITY — IMDS blocked from container networks =="
IMDS_OUT="$(docker run --rm curlimages/curl:8.10.1 \
  -s --max-time 3 http://169.254.169.254/latest/meta-data/ 2>&1 || true)"
assert_not_contains "$IMDS_OUT" "ami-id" "bridge container CANNOT read IMDS (hop limit 1)"

echo "== validate: SECURITY — gateway (host net) can reach IMDS =="
ROLE="$(curl -fsS --max-time 3 \
  -H "X-aws-ec2-metadata-token: $(curl -fsS -X PUT --max-time 3 http://169.254.169.254/latest/api/token)" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/ 2>/dev/null || true)"
assert_contains "$ROLE" "instance-role" "host-net LiteLLM can assume instance role"

echo "== validate: SECURITY — port 4000 not exposed externally =="
# from the instance, via its PUBLIC address (hairpin through the SG)
PUBLIC_IP="${CODER_ACCESS_URL//*:/}"
PUBLIC_IP="${PUBLIC_IP%%:*}"
code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "http://$PUBLIC_IP:4000/health/liveliness" || echo blocked)"
assert_contains "$code" "blocked" "gateway port 4000 unreachable via public IP"

echo "== validate: bedrock model reachable through gateway (real provider) =="
# uses the demo virtual key; in bedrock mode this exercises the full chain
KEY="$(cat .demo-virtual-key 2>/dev/null || true)"
if [[ -n "$KEY" ]]; then
  BODY="$(curl -s --max-time 30 http://127.0.0.1:4000/v1/chat/completions \
    -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
    -d "{\"model\":\"${BEDROCK_MODEL_ANTHROPIC:-anthropic.claude-3-5-sonnet-20241022-v2:0}\",\"messages\":[{\"role\":\"user\",\"content\":\"say ok\"}]}")"
  assert_contains "$(echo "$BODY" | jq -r '.choices[0].message.content // .error.message // empty' | head -c 200)" \
    "error-free completion" "bedrock completion via gateway"
else
  _t_ok "demo key absent — skipping real-model check (run make bootstrap)"
fi

finish_suite "validate-deployment"

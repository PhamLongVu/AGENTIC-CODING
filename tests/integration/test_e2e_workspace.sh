#!/usr/bin/env bash
# E2E: real Coder workspace from the docker-standard template.
# admin session -> workspace build -> agent connects -> apps healthy ->
# AI request from INSIDE the workspace through the gateway.
# Requires: stack running, bootstrap done, workspace image built.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source tests/lib/env.sh
source tests/lib/assertions.sh
source tests/lib/coder.sh

WS="e2e-$(date +%s)"
cleanup() { coder_delete_workspace "$WS" 2>/dev/null || true; }
trap cleanup EXIT

echo "== e2e: template present =="
TPL_ID="$(coder_template_id docker-standard)"
assert_not_empty "$TPL_ID" "docker-standard template exists (bootstrap pushes it)"
[[ -z "$TPL_ID" ]] && finish_suite "test_e2e_workspace (skipped: no template)"

echo "== e2e: create workspace '$WS' (profile small, 45m ttl) =="
CREATED="$(coder_create_workspace "$WS" docker-standard "$(cat .demo-virtual-key)" 45 && echo created)"
assert_eq "${CREATED:-}" "created" "workspace create accepted (CLI -> API)"

echo "== e2e: build reaches running =="
ST="$(coder_wait_workspace "$WS" running 420 || true)"
assert_eq "$ST" "running" "workspace build status=running (got: $ST)"

echo "== e2e: agent connects =="
ok=0
for _ in $(seq 1 40); do
  coder_wait_agent "$WS" 5 && { ok=1; break; } || true
done
assert_eq "$ok" "1" "coder agent status=connected"

CTR="$(coder_workspace_container "$WS")"
docker inspect "$CTR" >/dev/null 2>&1 \
  && _t_ok "workspace container exists ($CTR)" \
  || _t_fail "workspace container exists ($CTR)"

echo "== e2e: container hardening in effect =="
INSPECT="$(docker inspect "$CTR")"
assert_contains "$(echo "$INSPECT" | jq -c '.[0].HostConfig.CapDrop')" "ALL" "capabilities ALL dropped"
assert_contains "$(echo "$INSPECT" | jq -c '.[0].HostConfig.SecurityOpt')" "no-new-privileges" "no-new-privileges set"
assert_eq "$(echo "$INSPECT" | jq -r '.[0].HostConfig.NanoCpus')" "1000000000" "cpu limit = 1 vCPU (small profile)"
assert_eq "$(echo "$INSPECT" | jq -r '.[0].HostConfig.Memory')" "2147483648" "memory limit = 2048 MiB (small profile)"
# kreuzwerker/docker exposes no pids limit — documented known limitation
# (KNOWN_ISSUES.md); assert it is indeed unset so the docs stay honest.
assert_eq "$(echo "$INSPECT" | jq -r '.[0].HostConfig.PidsLimit')" "null" "pids limit unset (provider limitation, documented)"
assert_not_contains "$(echo "$INSPECT" | jq -c '.[0].HostConfig.Binds')" "docker.sock" "NO docker socket mounted"

echo "== e2e: apps report healthy through coder =="
ok=0
for _ in $(seq 1 30); do
  APPS="$(coder_agent_apps "$WS")"
  n_healthy="$(echo "$APPS" | jq '[.[].health] | map(select(.=="healthy")) | length')"
  (( n_healthy >= 2 )) && { ok=1; break; }
  sleep 3
done
assert_eq "$ok" "1" "code-server + opencode apps healthy (state: $(coder_agent_apps "$WS"))"

echo "== e2e: AI request from INSIDE the workspace via gateway =="
# NB: `docker exec` sessions do NOT inherit the coder-agent env (only the
# agent's children do), so inject the demo key we passed as the parameter;
# the plumbing itself is asserted right after via the service process env.
OUT="$(docker exec "$CTR" bash -c \
  "curl -s http://host.docker.internal:4000/v1/chat/completions \
     -H \"Authorization: Bearer $(cat .demo-virtual-key)\" \
     -H \"Content-Type: application/json\" \
     -d '{\"model\":\"anthropic.claude-3-5-sonnet-20241022-v2:0\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}'" 2>/dev/null || true)"
assert_contains "$(echo "$OUT" | jq -r '.choices[0].message.content // empty' 2>/dev/null)" "MOCK RESPONSE" \
  "workspace -> gateway -> mock model round-trip works"
KEYINENV="$(docker exec "$CTR" bash -c \
  'tr "\0" "\n" < /proc/$(pgrep -f "opencode serve --hostname" | head -1)/environ | grep -c "^OPENCODE_PROVIDER_API_KEY=sk-"')"
assert_eq "$KEYINENV" "1" "virtual key plumbed into service env (parameter -> agent env)"
assert_contains "$(docker exec "$CTR" bash -lc 'command -v aws' >/dev/null 2>&1 && echo yes || echo no)" "no" \
  "workspace still has no aws CLI"

echo "== e2e: ttl configured (autostop) =="
TTL="$(coder_workspace_json "$WS" | jq -r .ttl_ms)"
assert_eq "$TTL" "2700000" "workspace ttl = 45 min"

finish_suite "test_e2e_workspace"

#!/usr/bin/env bash
# Persistence: /home/coder survives stop -> start (volume kept), and the
# container recreation does NOT keep the writable layer (by design).
# Requires: stack + bootstrap + image + template (run after e2e).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source tests/lib/env.sh
source tests/lib/assertions.sh
source tests/lib/coder.sh

WS="persist-$(date +%s)"
cleanup() { coder_delete_workspace "$WS" 2>/dev/null || true; }
trap cleanup EXIT

TPL_ID="$(coder_template_id docker-standard)"
[[ -z "$TPL_ID" ]] && { echo "skip: template missing"; finish_suite "test_persistence (skipped)"; }

echo "== persistence: create + write marker =="
coder_create_workspace "$WS" "$TPL_ID" "$(cat .demo-virtual-key)" 45 >/dev/null
ST="$(coder_wait_workspace "$WS" running 420 || true)"
assert_eq "$ST" "running" "workspace starts"

CTR="$(coder_workspace_container "$WS")"
MARKER="keepme-$$"
docker exec "$CTR" bash -c "echo $MARKER > /home/coder/.persistence-marker"
docker exec "$CTR" bash -c "echo ephemeral > /tmp/.ephemeral-marker"
docker exec "$CTR" bash -c "mkdir -p /home/coder/.config/opencode && echo cfg > /home/coder/.config/opencode/.marker"

echo "== persistence: stop keeps volume, removes container =="
coder_workspace_action "$WS" stop
ST="$(coder_wait_workspace "$WS" stopped 180 || true)"
assert_eq "$ST" "stopped" "workspace stops cleanly"
docker inspect "$CTR" >/dev/null 2>&1 \
  && _t_fail "container removed on stop" \
  || _t_ok "container removed on stop (volume kept)"
VOL="coder-${CODER_ADMIN_USER,,}-$(echo "${WS//-/-}" | tr '[:upper:]' '[:lower:]')"
docker volume inspect "$VOL" >/dev/null 2>&1 \
  && _t_ok "home volume still exists ($VOL)" \
  || _t_fail "home volume still exists ($VOL)"

echo "== persistence: start reattaches the SAME volume =="
coder_workspace_action "$WS" start
ST="$(coder_wait_workspace "$WS" running 420 || true)"
assert_eq "$ST" "running" "workspace restarts"
CTR="$(coder_workspace_container "$WS")"
assert_eq "$(docker exec "$CTR" cat /home/coder/.persistence-marker 2>/dev/null)" "$MARKER" \
  "marker file in /home/coder survived stop/start"
assert_eq "$(docker exec "$CTR" cat /home/coder/.config/opencode/.marker 2>/dev/null)" "cfg" \
  "opencode config dir survived stop/start"
docker exec "$CTR" test -f /tmp/.ephemeral-marker 2>/dev/null \
  && _t_fail "writable layer correctly disposable (/tmp empty after restart)" \
  || _t_ok "writable layer correctly disposable (/tmp empty after restart)"

finish_suite "test_persistence"

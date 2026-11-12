#!/usr/bin/env bash
# Workspace peer isolation: two workspaces on separate docker networks must
# not be able to resolve or reach each other, and each keeps its own volume.
# Requires: stack + bootstrap + image + template.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source tests/lib/env.sh
source tests/lib/assertions.sh
source tests/lib/coder.sh

WSA="iso-a-$(date +%s)"
WSB="iso-b-$(date +%s)"
cleanup() { coder_delete_workspace "$WSA" 2>/dev/null || true; coder_delete_workspace "$WSB" 2>/dev/null || true; }
trap cleanup EXIT

TPL_ID="$(coder_template_id docker-standard)"
[[ -z "$TPL_ID" ]] && { echo "skip: template missing"; finish_suite "test_isolation (skipped)"; }

echo "== isolation: create two workspaces =="
for ws in "$WSA" "$WSB"; do
  coder_create_workspace "$ws" docker-standard "$(cat .demo-virtual-key)" 45 >/dev/null
  ST="$(coder_wait_workspace "$ws" running 420 || true)"
  assert_eq "$ST" "running" "$ws running"
done
CTRA="$(coder_workspace_container "$WSA")"
CTRB="$(coder_workspace_container "$WSB")"

echo "== isolation: separate networks =="
NETA="$(docker inspect "$CTRA" | jq -r '.[0].NetworkSettings.Networks | keys[0]')"
NETB="$(docker inspect "$CTRB" | jq -r '.[0].NetworkSettings.Networks | keys[0]')"
assert_not_contains "$NETB" "$NETA" "workspaces on different docker networks ($NETA vs $NETB)"

echo "== isolation: DNS does not leak peers =="
docker exec "$CTRA" getent hosts "$CTRB" >/dev/null 2>&1 \
  && _t_fail "A cannot resolve B hostname" \
  || _t_ok "A cannot resolve B hostname"

echo "== isolation: direct IP unreachable =="
IPB="$(docker inspect "$CTRB" | jq -r ".[0].NetworkSettings.Networks[\"$NETB\"].IPAddress")"
if docker exec "$CTRA" bash -c "curl -s --max-time 3 -o /dev/null http://$IPB:8080" 2>/dev/null; then
  _t_fail "A cannot reach B at $IPB:8080"
else
  _t_ok "A cannot reach B at $IPB:8080"
fi

echo "== isolation: separate home volumes =="
VOLA="coder-${CODER_ADMIN_USER,,}-${WSA,,}"
VOLB="coder-${CODER_ADMIN_USER,,}-${WSB,,}"
docker exec "$CTRA" bash -c 'echo A > /home/coder/.whoami'
docker exec "$CTRB" bash -c 'echo B > /home/coder/.whoami'
assert_eq "$(docker exec "$CTRA" cat /home/coder/.whoami)" "A" "A sees only its own /home/coder"
assert_eq "$(docker exec "$CTRB" cat /home/coder/.whoami)" "B" "B sees only its own /home/coder"
assert_not_contains "$VOLB" "$VOLA" "distinct volumes ($VOLA / $VOLB)"

echo "== isolation: no host docker socket in workspaces =="
for c in "$CTRA" "$CTRB"; do
  docker exec "$c" test -S /var/run/docker.sock 2>/dev/null \
    && _t_fail "$c must not see the docker socket" \
    || _t_ok "$c must not see the docker socket"
done

finish_suite "test_isolation"

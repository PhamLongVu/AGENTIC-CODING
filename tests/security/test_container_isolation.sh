#!/usr/bin/env bash
# Container isolation surface (local stand-ins for the AWS-only IMDS test):
# workspaces never get the docker socket, never run as root, cannot escalate
# privileges, and the ONLY socket-mounting container is the coder service.
# The real IMDS-block test (169.254.169.254) runs on the EC2 host via
# deploy/scripts/validate-deployment.sh — it cannot be simulated locally.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source tests/lib/env.sh
source tests/lib/assertions.sh

echo "== isolation: platform containers mounting the docker socket =="
MOUNTERS="$(docker ps --format '{{.Names}}' | while read -r c; do
  if docker inspect "$c" | jq -e '.[0].Mounts[]? | select(.Source=="/var/run/docker.sock")' >/dev/null 2>&1; then
    echo "$c"
  fi
done | sort | tr '\n' ' ' | xargs)"
assert_eq "$MOUNTERS" "cloud-coding-platform-coder-1" \
  "ONLY the coder service mounts docker.sock (got: ${MOUNTERS:-none})"

echo "== isolation: workspace image has no privilege escalation paths =="
IMAGE="cloudcoding-workspace:dev"
docker image inspect "$IMAGE" >/dev/null 2>&1 \
  || { echo "skip: image not built"; finish_suite "test_container_isolation (skipped)"; }
assert_eq "$(docker run --rm "$IMAGE" id -u)" "1000" "workspace default user uid 1000"
OUT="$(docker run --rm --cap-drop ALL --security-opt no-new-privileges:true "$IMAGE" \
  bash -c 'ping -c1 127.0.0.1 >/dev/null 2>&1 || true; unshare -Ur true 2>/dev/null && echo COULD_NS || echo no_ns')"
assert_contains "$OUT" "no_ns" "cannot create user namespace (no-new-privileges + no caps)"
assert_cmd_fails "no setuid binaries reachable" \
  docker run --rm "$IMAGE" bash -c 'find / -perm -4000 -type f 2>/dev/null | grep -q .'

echo "== isolation: live workspace containers (if any are running) =="
WS_CONTAINERS="$(docker ps --format '{{.Names}}' | grep '^coder-ws-' || true)"
if [[ -z "$WS_CONTAINERS" ]]; then
  _t_ok "no live workspaces right now (covered by tests/integration/test_isolation.sh)"
else
  for c in $WS_CONTAINERS; do
    UID0="$(docker inspect "$c" | jq -r '.[0].Config.User // "root"')"
    [[ "$UID0" != "root" && "$UID0" != "0:0" ]] && _t_ok "$c runs non-root ($UID0)" || _t_fail "$c runs as root"
    docker exec "$c" test -S /var/run/docker.sock 2>/dev/null \
      && _t_fail "$c must not see docker socket" \
      || _t_ok "$c must not see docker socket"
    # no platform/credential secrets in workspace env (ADR-0004):
    WS_ENV="$(docker inspect "$c" | jq -r '.[0].Config.Env | join("\n")')"
    assert_not_contains "$WS_ENV" "LITELLM_MASTER_KEY" \
      "$c env must not contain the gateway master key"
    assert_not_contains "$WS_ENV" "AWS_ACCESS_KEY_ID" \
      "$c env must not contain AWS credentials"
    assert_not_contains "$WS_ENV" "AWS_SESSION_TOKEN" \
      "$c env must not contain AWS session tokens"
  done
fi

finish_suite "test_container_isolation"

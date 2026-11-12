#!/usr/bin/env bash
# Workspace image: builds cleanly, runs non-root, has NO docker/aws CLI,
# both services become healthy in-container, shared project dir wiring,
# resource limits are enforceable. (Acceptance: BACKLOG 1.3 + 1.6)
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source tests/lib/assertions.sh

IMAGE="cloudcoding-workspace:dev"
CTR="wsimg-itest-$$"
cleanup() { docker rm -f "$CTR" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "== workspace image: build (skipped if already built) =="
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  assert_cmd "docker build $IMAGE" docker build -t "$IMAGE" -f workspace/images/development/Dockerfile workspace/
else
  _t_ok "image already present (make build-workspace rebuilds)"
fi

echo "== workspace image: non-root identity =="
assert_eq "$(docker run --rm "$IMAGE" id -u)" "1000" "container user is uid 1000 (coder)"
assert_eq "$(docker run --rm "$IMAGE" id -g)" "1000" "container group is gid 1000"

echo "== workspace image: forbidden tooling absent =="
assert_cmd_fails "no docker CLI in image" docker run --rm "$IMAGE" bash -lc 'command -v docker'
assert_cmd_fails "no aws CLI in image" docker run --rm "$IMAGE" bash -lc 'command -v aws'
assert_cmd_fails "no sudo in image" docker run --rm "$IMAGE" bash -lc 'command -v sudo'
assert_cmd_fails "no docker socket visible" docker run --rm "$IMAGE" bash -lc 'test -S /var/run/docker.sock'

echo "== workspace image: pinned tool versions =="
# NB: code-server --version also writes an "info: Wrote default config file"
# line to stdout first — so match on the full output, not the first line.
assert_contains "$(docker run --rm "$IMAGE" code-server --version)" "4.145.2" \
  "code-server version matches pin"
assert_contains "$(docker run --rm "$IMAGE" opencode --version)" "1.19.5" \
  "opencode version matches pin"

echo "== workspace image: both services healthy in-container =="
docker run -d --name "$CTR" "$IMAGE" /usr/local/bin/start-workspace-services.sh >/dev/null
ok=0
for _ in $(seq 1 45); do
  if docker exec "$CTR" bash -c 'curl -fsSo /dev/null http://127.0.0.1:8080/healthz' 2>/dev/null \
     && docker exec "$CTR" bash -c 'curl -fsSo /dev/null http://127.0.0.1:4096/' 2>/dev/null; then
    ok=1; break
  fi
  sleep 2
done
assert_eq "$ok" "1" "code-server and opencode both answer on loopback"

echo "== workspace image: shared project directory wiring =="
docker exec "$CTR" bash -c 'echo shared-proof > /home/coder/projects/proof.txt'
assert_eq "$(docker exec "$CTR" cat /home/coder/projects/proof.txt)" "shared-proof" \
  "project dir read/write via shell"
# NB: match the launcher arg pattern, not just the binary name — code-server
# forks a child that also carries the name, so a bare name-count is 2.
CS_PIDS="$(docker exec "$CTR" bash -c "ps -eo args | grep -c '[c]ode-server --bind-addr'")"
OC_PIDS="$(docker exec "$CTR" bash -c "ps -eo args | grep -c '[o]pencode serve --hostname'")"
assert_contains "$CS_PIDS" "1" "code-server process running"
assert_contains "$OC_PIDS" "1" "opencode serve process running"
# both processes' cwd is the shared volume path
CWD_CS="$(docker exec "$CTR" bash -c "readlink /proc/\$(pgrep -f '[c]ode-server' | head -1)/cwd")"
assert_eq "$CWD_CS" "/home/coder/projects" "code-server cwd is the shared project dir"

echo "== workspace image: resource limits are enforceable =="
# 384 MiB memory cap; node (guaranteed present in the image) keeps allocating
# until the kernel OOM-kills the process => docker reports exit code 137.
# Exact-code match matters: a blanket `|| echo killed` would also swallow
# 127 (binary missing) and pass vacuously. (No `set -e` in this suite, so
# the failing docker run does not abort — $? is captured directly.)
docker run --rm --memory 384m "$IMAGE" \
  node -e 'const b=[];for(;;){b.push(Buffer.alloc(64*1024*1024))}' >/dev/null 2>&1
OOM_RC=$?
assert_eq "$OOM_RC" "137" "memory limit enforced (kernel OOM-kill, exit 137)"

finish_suite "test_workspace_image"

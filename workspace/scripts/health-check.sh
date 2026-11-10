#!/usr/bin/env bash
# Workspace self-check: verifies both developer-facing services answer on
# container loopback. Used by integration tests and ops triage.
# Exit 0 = both healthy.
set -uo pipefail

CS_ADDR="${CODE_SERVER_BIND:-127.0.0.1:8080}"     # host:port
CS_PORT="${CS_ADDR##*:}"
OC_PORT="${OPENCODE_PORT:-4096}"

rc=0
if curl -fsSo /dev/null "http://127.0.0.1:${CS_PORT}"; then
  echo "healthy: code-server (127.0.0.1:${CS_PORT})"
else
  echo "UNHEALTHY: code-server (127.0.0.1:${CS_PORT})"
  rc=1
fi
if curl -fsSo /dev/null "http://127.0.0.1:${OC_PORT}"; then
  echo "healthy: opencode (127.0.0.1:${OC_PORT})"
else
  echo "UNHEALTHY: opencode (127.0.0.1:${OC_PORT})"
  rc=1
fi
exit "$rc"

#!/usr/bin/env bash
# destroy-dev.sh — tear down the LOCAL dev environment completely.
# Levels:
#   stack      compose down (volumes kept)               [default]
#   data       + platform volumes (postgres, coder home)
#   workspaces + ALL workspace home volumes (DEVELOPER DATA — irreversible)
# Never touches AWS (there is nothing deployed).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/lib/deploy-log.sh"
dlog_section "make destroy-dev (L=${1:-stack})"

LEVEL="${1:-stack}"
case "$LEVEL" in
  stack)
    docker compose down
    dlog "compose down: removed platform containers + network (volumes KEPT)"
    echo "destroy-dev: stack down (all volumes kept)"
    ;;
  data)
    docker compose down -v
    dlog "compose down -v: removed platform containers, network AND volumes (platform_pgdata, platform_coder_home); workspace volumes kept"
    echo "destroy-dev: platform metadata destroyed; workspace volumes kept"
    ;;
  workspaces)
    echo "WARNING: this deletes EVERY workspace's /home/coder (projects, sessions, ssh keys)."
    read -r -p "Type 'destroy workspaces' to confirm: " c
    [[ "$c" == "destroy workspaces" ]] || { echo "aborted"; exit 1; }
    docker compose down -v
    for vol in $(docker volume ls --format '{{.Name}}' | grep -E '^coder-.*-home$'); do
      docker volume rm "$vol" >/dev/null && echo "  removed $vol" && dlog "removed workspace volume $vol"
    done
    docker network ls --format '{{.Name}}' | grep -E '^ws-' | xargs -r docker network rm >/dev/null 2>&1 || true
    dlog "removed per-workspace networks (^ws-*)"
    echo "destroy-dev: local environment fully reset"
    ;;
  *)
    echo "usage: destroy-dev.sh [stack|data|workspaces]" >&2
    exit 64
    ;;
esac

#!/usr/bin/env bash
# destroy-dev.sh — tear down the LOCAL dev environment completely.
# Levels:
#   stack      compose down (volumes kept)               [default]
#   data       + platform volumes (postgres, coder home)
#   workspaces + ALL workspace home volumes (DEVELOPER DATA — irreversible)
#   all        everything above + built workspace image + session files
#              (machine back to pre-clone state except pulled images/.env;
#               rebuild from scratch: make up && make bootstrap && make build-workspace)
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
  all)
    echo "WARNING: full reset — ALL platform data, ALL workspace data (developer"
    echo "projects/sessions), the built workspace image and session files go away."
    echo "Kept: .env, pulled platform images (fast bring-up), DEPLOY_LOG.local.md."
    read -r -p "Type 'destroy all' to confirm: " c
    [[ "$c" == "destroy all" ]] || { echo "aborted"; exit 1; }
    docker compose down -v
    dlog "compose down -v: platform containers + network + platform volumes removed"
    for vol in $(docker volume ls --format '{{.Name}}' | grep -E '^coder-.*-home$'); do
      docker volume rm "$vol" >/dev/null && echo "  removed workspace volume $vol" && dlog "removed workspace volume $vol"
    done
    docker network ls --format '{{.Name}}' | grep -E '^ws-' | xargs -r docker network rm >/dev/null 2>&1 || true
    dlog "removed per-workspace networks (^ws-*)"
    if docker image inspect cloudcoding-workspace:dev >/dev/null 2>&1; then
      docker image rm cloudcoding-workspace:dev >/dev/null && dlog "removed image cloudcoding-workspace:dev"
    else
      echo "  (workspace image not present — skipped)"
    fi
    rm -f .coder-session .demo-virtual-key
    dlog "removed local session files (.coder-session, .demo-virtual-key)"
    echo "destroy-dev: full reset done. Rebuild from scratch:"
    echo "  make up && make bootstrap && make build-workspace"
    ;;
  *)
    echo "usage: destroy-dev.sh [stack|data|workspaces|all]" >&2
    exit 64
    ;;
esac

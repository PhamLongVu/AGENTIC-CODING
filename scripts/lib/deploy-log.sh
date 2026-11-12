#!/usr/bin/env bash
# =============================================================================
# deploy-log.sh — append-only record of everything deploy/test creates here.
# =============================================================================
# Purpose: the owner can clean this machine later WITHOUT re-testing or
# hunting for leftovers: every artifact gets a log line with its exact
# removal command, and `make deploy-log` prints the history next to the
# LIVE inventory (current truth wins over stale entries).
#
# DEPLOY_LOG.local.md is host-local state: gitignored, never committed.
# Scope is STRICT (this host runs other projects' containers): only
#   containers  cloud-coding-platform-* | coder-ws-*
#   volumes     cloud-coding-platform_*  | coder-*-home
#   networks    cloud-coding-platform*   | per-workspace networks
#   images      cloudcoding-workspace:*
# Usage (after setting ROOT): source this file, then:
#   dlog_section "make up"      # start a timestamped section
#   dlog "created X"            # one line under the section
#   dlog_inventory              # snapshot + removal command per artifact
# Or: bash scripts/lib/deploy-log.sh show   (what `make deploy-log` runs)
# =============================================================================
set -uo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DEPLOY_LOG="${DEPLOY_LOG:-$ROOT/DEPLOY_LOG.local.md}"

_dlog_init() {
  mkdir -p "$(dirname "$DEPLOY_LOG")"
  cat > "$DEPLOY_LOG" <<'HDR'
# Deploy log — host-local, gitignored (do not commit)

Everything created on this machine by deploying/testing the cloud coding
platform, newest section last. Live truth: `make deploy-log`.

## Cleanup cheat-sheet (scoped to THIS project only — nothing else)

| Artifact | Command |
|---|---|
| platform containers + network | `make down` |
| + platform volumes (postgres, coder home) | `make destroy-dev L=data` |
| workspace containers + ALL workspace volumes (developer data!) | `make destroy-dev L=workspaces` (types confirmation) |
| FULL reset (volumes + workspace image + session files) | `make destroy-dev L=all` (types confirmation; rebuild: `make up && make bootstrap && make build-workspace`) |
| workspace image | `docker image rm cloudcoding-workspace:dev` |
| pulled platform images (optional) | `docker image rm postgres:16.4-alpine3.20 ghcr.io/berriai/litellm-database:main-v1.83.14-stable.patch.3 ghcr.io/coder/coder:v2.36.3 hashicorp/terraform:1.9.8 curlimages/curl:8.10.1 alpine:3.20` |
| local files | `rm -f .coder-session .demo-virtual-key DEPLOY_LOG.local.md && rm -rf backups/` (keep `.env` if reusing) |

NOTE: this host runs other projects' containers (iva-*, se-*, squid, …).
Nothing outside the names above is ever created or removed by this project.
HDR
}

dlog_section() {  # <title>
  [[ -f "$DEPLOY_LOG" ]] || _dlog_init
  printf '\n## %s — %s\n' "$(date '+%F %T')" "$1" >> "$DEPLOY_LOG"
}

dlog() {  # <message...>
  [[ -f "$DEPLOY_LOG" ]] || _dlog_init
  printf -- '- [%s] %s\n' "$(date '+%T')" "$*" >> "$DEPLOY_LOG"
}

_dlog_platform_containers() {
  docker ps -a --format '{{.Names}}\t{{.State}}\t{{.Status}}' 2>/dev/null \
    | grep '^cloud-coding-platform-' \
    | while IFS=$'\t' read -r name state status; do
        printf '%s\n' "| $name | $status | \`docker rm -f $name\` (or \`make down\`) |"
      done
}

_dlog_workspace_containers() {
  docker ps -a --format '{{.Names}}\t{{.Status}}' 2>/dev/null \
    | grep '^coder-ws-' \
    | while IFS=$'\t' read -r name status; do
        printf '%s\n' "| $name | $status | stop+delete workspace in Coder UI, or \`docker rm -f $name\` |"
      done
}

_dlog_volumes() {
  docker volume ls --format '{{.Name}}' 2>/dev/null \
    | grep -E '^(cloud-coding-platform_|coder-.*-home$)' \
    | while read -r v; do
        local how="docker volume rm $v"
        case "$v" in
          coder-*-home) how="make destroy-dev L=workspaces (ALL workspace volumes)" ;;
          *) how="make destroy-dev L=data (platform volumes)" ;;
        esac
        printf '| %s | — | `%s` |\n' "$v" "$how"
      done
}

_dlog_networks() {
  docker network ls --format '{{.Name}}' 2>/dev/null \
    | grep -E '^cloud-coding-platform' \
    | while read -r n; do printf '| %s | — | `docker network rm %s` (or `make down`) |\n' "$n" "$n"; done
}

_dlog_images() {
  docker images --format '{{.Repository}}:{{.Tag}}\t{{.Size}}' 2>/dev/null \
    | grep -E '^(cloudcoding-workspace|hashicorp/terraform|curlimages/curl)' \
    | while IFS=$'\t' read -r img size; do
        printf '| %s | %s | `docker image rm %s` |\n' "$img" "$size" "$img"
      done
}

dlog_inventory() {  # append a live snapshot section to the file
  dlog_section "inventory snapshot"
  {
    echo ""
    echo "### platform containers"
    echo ""
    echo "| name | status | removal |"
    echo "|---|---|---|"
    _dlog_platform_containers
    echo ""
    echo "### workspace containers (coder-ws-*)"
    echo ""
    echo "| name | status | removal |"
    echo "|---|---|---|"
    _dlog_workspace_containers
    echo ""
    echo "### volumes"
    echo ""
    echo "| volume | | removal |"
    echo "|---|---|---|"
    _dlog_volumes
    echo ""
    echo "### networks"
    echo ""
    echo "| network | | removal |"
    echo "|---|---|---|"
    _dlog_networks
    echo ""
    echo "### project images (workspace image + test helpers)"
    echo ""
    echo "| image | size | removal |"
    echo "|---|---|---|"
    _dlog_images
  } >> "$DEPLOY_LOG"
}

dlog_show() {  # print history + live inventory to stdout (no file writes)
  echo "==================== DEPLOY LOG (history) ===================="
  [[ -f "$DEPLOY_LOG" ]] && cat "$DEPLOY_LOG" || echo "(no log yet)"
  echo ""
  echo "==================== LIVE INVENTORY (now) ===================="
  local tmp; tmp="$(mktemp)"
  DEPLOY_LOG="$tmp" dlog_section "live"
  DEPLOY_LOG="$tmp" dlog_inventory
  sed -n '/### platform containers/,$p' "$tmp"
  rm -f "$tmp"
}

# `bash scripts/lib/deploy-log.sh show` (what `make deploy-log` runs);
# harmless no-op when sourced without arguments. NOTE: must be an `if`,
# NOT `[[ ]] && dlog_show` — an AND-list with a false condition returns 1,
# and `source` propagates that status, killing any set -e caller.
if [[ "${1:-}" == "show" ]]; then
  dlog_show
fi

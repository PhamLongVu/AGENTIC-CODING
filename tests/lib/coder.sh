#!/usr/bin/env bash
# Coder API helpers for integration/security tests. Requires tests/lib/env.sh
# sourced first (CODER_API_URL, admin session).
# All functions are silent on success unless VERBOSE=1; errors exit non-zero.
# NB: no `set -e` — sourced by test scripts that own their error policy
# (see tests/lib/env.sh for the rationale).
set -uo pipefail

CODER_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CODER_SESSION_FILE="${CODER_SESSION_FILE:-$CODER_ROOT/.coder-session}"
CODER_COMPOSE_FILE="$CODER_ROOT/docker-compose.yml"

coder_token() {
  [[ -s "$CODER_SESSION_FILE" ]] || { echo "coder.sh: no .coder-session — run make bootstrap" >&2; return 1; }
  cat "$CODER_SESSION_FILE"
}

coder_api() {  # coder_api <method> <path> [json-body] -> response on stdout
  local method="$1" path="$2" body="${3:-}"
  local args=(-sS -X "$method" "$CODER_API_URL$path" \
    -H "Authorization: Bearer $(coder_token)" -H "Content-Type: application/json")
  [[ -n "$body" ]] && args+=(-d "$body")
  curl "${args[@]}"
}

coder_template_id() {  # -> template id for a name (arg 1)
  # Coder v2 GET /templates returns a plain array (not {templates:[...]})
  coder_api GET /api/v2/templates | jq -r --arg n "$1" '.[]? | select(.name==$n) | .id' | head -1
}

coder_workspace_json() {  # <workspace-name-or-id> -> workspace json
  local q="$1" id
  if [[ "$q" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    coder_api GET "/api/v2/workspaces/$q"
  else
    # Coder v2.36: /workspaces/{user}/{name} rejects usernames ("Invalid
    # UUID") — resolve the id via the list endpoint instead.
    id="$(coder_api GET /api/v2/workspaces | jq -r --arg n "$q" '.workspaces[]? | select(.name==$n) | .id' | head -1)"
    [[ -n "$id" ]] || return 1
    coder_api GET "/api/v2/workspaces/$id"
  fi
}

# create_workspace <name> <template-NAME> <virtual_key> [ttl_minutes]
# The v2.36 REST create route changed (POST /workspaces -> 405); the CLI is
# the stable contract, so shell out to it inside the coder container
# (same pattern as scripts/coder/push-template.sh).
coder_create_workspace() {
  local name="$1" tpl="$2" key="$3" ttl="${4:-45}" container
  container="$(docker compose -f "$CODER_COMPOSE_FILE" ps -q coder)"
  [[ -n "$container" ]] || { echo "coder.sh: coder container not running" >&2; return 1; }
  docker exec -i \
    -e CODER_SESSION_TOKEN="$(coder_token)" \
    -e CODER_URL="$CODER_API_URL" \
    "$container" /opt/coder create "$name" \
    --template "$tpl" \
    --parameter "litellm_virtual_key=$key" \
    --stop-after "${ttl}m" \
    --yes --use-parameter-defaults --no-wait \
    < <(sleep 300) >/dev/null
}

coder_workspace_action() {  # <ws> <stop|start>
  # v2.36: transitions go through POST builds (PUT /workspaces/{id}/stop -> 404)
  local id
  id="$(coder_workspace_json "$1" | jq -r .id)"
  coder_api POST "/api/v2/workspaces/$id/builds" "{\"transition\":\"$2\"}" >/dev/null
}

coder_delete_workspace() {  # <ws>
  # v2.36: REST DELETE /workspaces/{id} -> 405; the CLI owns this contract.
  local container
  container="$(docker compose -f "$CODER_COMPOSE_FILE" ps -q coder)"
  [[ -n "$container" ]] || return 1
  docker exec -i \
    -e CODER_SESSION_TOKEN="$(coder_token)" \
    -e CODER_URL="$CODER_API_URL" \
    "$container" /opt/coder delete "$1" --yes \
    < <(sleep 300) >/dev/null 2>&1 || true
}

# wait_workspace <ws> <status: pending|starting|running|stopping|stopped|failed|canceling|canceled|deleted> [max_seconds]
coder_wait_workspace() {
  local ws="$1" want="$2" max="${3:-300}" waited=0 status="?"
  while :; do
    status="$(coder_workspace_json "$ws" | jq -r '.latest_build.status')"
    [[ "$status" == "$want" ]] && { echo "$status"; return 0; }
    [[ "$status" == "failed" ]] && { echo "failed"; return 1; }
    sleep 3; waited=$((waited + 3))
    (( waited >= max )) && { echo "timeout-at:$status"; return 1; }
  done
}

# wait_agent_connected <ws> [max_seconds] — waits for first agent to connect
coder_wait_agent() {
  local ws="$1" max="${2:-300}" waited=0 status="?"
  while :; do
    status="$(coder_workspace_json "$ws" | jq -r '[.latest_build.resources[].agents[]?.status][0] // "none"')"
    [[ "$status" == "connected" ]] && return 0
    # keep polling through lifecycle states (starting, disconnected, ...)
    sleep 3; waited=$((waited + 3))
    (( waited >= max )) && return 1
  done
}

coder_agent_apps() {  # <ws> -> agents[].apps[] flattened
  coder_workspace_json "$1" | jq -c '[.latest_build.resources[].agents[]?.apps[]? | {slug, health: (.health // "initializing")}]'
}

# container name for a workspace (must match main.tf naming)
coder_workspace_container() {  # <ws>
  local owner ws
  owner="$(echo "$CODER_ADMIN_USER" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')"
  ws="$(echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')"
  echo "coder-ws-${owner}-${ws}"
}

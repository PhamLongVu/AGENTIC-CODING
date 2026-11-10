#!/usr/bin/env bash
# Push (or create) the workspace template from workspace/templates/standard/
# into the running Coder server, using the bootstrap admin session.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/tests/lib/env.sh"

TEMPLATE_DIR="$ROOT/workspace/templates/standard"
SESSION_FILE="$ROOT/.coder-session"
[[ -f "$TEMPLATE_DIR/main.tf" ]] || { echo "push-template: $TEMPLATE_DIR/main.tf missing" >&2; exit 1; }
[[ -f "$SESSION_FILE" ]] || { echo "push-template: run make bootstrap first (.coder-session missing)" >&2; exit 1; }

# Template name is fixed so bootstrap is idempotent (create on first push).
TEMPLATE_NAME="docker-standard"
VERSION="$(cat "$TEMPLATE_DIR/version.txt" 2>/dev/null || echo 1.0)"

# The coder CLI runs inside the coder container (binary present, no host
# install); the template directory is docker-cp'd in on every push.
CONTAINER="$(docker compose -f "$ROOT/docker-compose.yml" ps -q coder)"
[[ -n "$CONTAINER" ]] || { echo "push-template: coder container not running" >&2; exit 1; }

docker cp "$TEMPLATE_DIR" "$CONTAINER:/tmp/template" >/dev/null

docker exec -e CODER_SESSION_TOKEN="$(cat "$SESSION_FILE")" \
  -e CODER_URL="$CODER_API_URL" \
  "$CONTAINER" /opt/coder templates push "$TEMPLATE_NAME" \
  --directory /tmp/template --activate --yes \
  2>&1 | sed "s/^/  templates-push: /"

# if push failed because the template doesn't exist yet, create it
if ! docker exec -e CODER_SESSION_TOKEN="$(cat "$SESSION_FILE")" \
  -e CODER_URL="$CODER_API_URL" \
  "$CONTAINER" /opt/coder templates list 2>/dev/null | grep -q "$TEMPLATE_NAME"; then
  echo "push-template: creating new template '$TEMPLATE_NAME'"
  docker exec -e CODER_SESSION_TOKEN="$(cat "$SESSION_FILE")" \
    -e CODER_URL="$CODER_API_URL" \
    "$CONTAINER" /opt/coder templates create "$TEMPLATE_NAME" \
    --directory /tmp/template --yes \
    2>&1 | sed "s/^/  templates-create: /"
fi
echo "push-template: done ($TEMPLATE_NAME)"

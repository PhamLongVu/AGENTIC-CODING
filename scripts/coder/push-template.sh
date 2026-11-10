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

# The coder CLI runs inside the coder container (binary present, no host
# install); the template directory is docker-cp'd in on every push.
CONTAINER="$(docker compose -f "$ROOT/docker-compose.yml" ps -q coder)"
[[ -n "$CONTAINER" ]] || { echo "push-template: coder container not running" >&2; exit 1; }

coder_cli() {  # coder_cli <templates subcommand args...>
  docker exec -e CODER_SESSION_TOKEN="$(cat "$SESSION_FILE")" \
    -e CODER_URL="$CODER_API_URL" \
    "$CONTAINER" /opt/coder "$@"
}

# Fresh copy every run: `docker cp DIR container:/tmp/template` NESTS into
# the existing dir on re-runs (/tmp/template/standard) and would push stale
# files — so remove the destination first.
docker exec "$CONTAINER" rm -rf /tmp/template >/dev/null
docker cp "$TEMPLATE_DIR" "$CONTAINER:/tmp/template" >/dev/null

# Decide BEFORE pushing: `templates push` on a missing template fails, and
# under set -e a failing push must not abort before the create fallback.
if coder_cli templates list 2>/dev/null | awk '{print $1}' | grep -qx "$TEMPLATE_NAME"; then
  echo "push-template: pushing new version of '$TEMPLATE_NAME'"
  coder_cli templates push "$TEMPLATE_NAME" --directory /tmp/template --activate --yes \
    2>&1 | sed "s/^/  templates-push: /"
else
  echo "push-template: creating new template '$TEMPLATE_NAME'"
  coder_cli templates create "$TEMPLATE_NAME" --directory /tmp/template --yes \
    2>&1 | sed "s/^/  templates-create: /"
fi
echo "push-template: done ($TEMPLATE_NAME)"

#!/usr/bin/env bash
# Idempotent platform bootstrap:
#   1. wait for the coder API
#   2. create the first admin user from .env (only while none exists)
#   3. store an admin session token in .coder-session (git-ignored, 0600)
#   4. upload the workspace template if workspace/templates/standard exists
#   5. issue a demo LiteLLM virtual key (stored in .demo-virtual-key)
# Never prints secrets.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/env.sh"
source "$ROOT/scripts/lib/deploy-log.sh"
dlog_section "make bootstrap"

SESSION_FILE="$ROOT/.coder-session"
DEMO_KEY_FILE="$ROOT/.demo-virtual-key"

# --- 1. wait for coder API ---------------------------------------------------
echo "bootstrap: waiting for coder API..."
for _ in $(seq 1 60); do
  if curl -fsS "$CODER_API_URL/api/v2/buildinfo" >/dev/null 2>&1; then break; fi
  sleep 2
done
curl -fsS "$CODER_API_URL/api/v2/buildinfo" >/dev/null || { echo "ERROR: coder API unreachable" >&2; exit 1; }

# --- 2+3. admin user + session ------------------------------------------------
get_session() {  # sets SESSION (empty on failure)
  curl -s -X POST "$CODER_API_URL/api/v2/users/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$CODER_ADMIN_EMAIL\",\"password\":\"$CODER_ADMIN_PASSWORD\"}" \
    | jq -r '.session_token // empty'
}

SESSION="$(get_session || true)"
if [[ -z "$SESSION" ]]; then
  FIRST_STATE="$(curl -s "$CODER_API_URL/api/v2/users/first")"
  if echo "$FIRST_STATE" | grep -q "not been created"; then
    echo "bootstrap: creating first admin user '$CODER_ADMIN_USER'..."
    curl -s -X POST "$CODER_API_URL/api/v2/users/first" \
      -H "Content-Type: application/json" \
      -d "{\"username\":\"$CODER_ADMIN_USER\",\"email\":\"$CODER_ADMIN_EMAIL\",\"password\":\"$CODER_ADMIN_PASSWORD\"}" \
      | jq -e '.user_id' >/dev/null
    dlog "created coder admin user '$CODER_ADMIN_USER' (stored in postgres, no local artifact)"
    SESSION="$(get_session)"
  fi
fi

if [[ -z "$SESSION" ]]; then
  echo "ERROR: cannot log in as $CODER_ADMIN_EMAIL — admin exists with a different password? (recreate volumes: make destroy-data)" >&2
  exit 1
fi
umask 077
printf '%s' "$SESSION" > "$SESSION_FILE"
dlog "wrote .coder-session (gitignored; rm -f .coder-session to clean)"
echo "bootstrap: admin session stored in .coder-session"

ME="$(curl -s -H "Authorization: Bearer $SESSION" "$CODER_API_URL/api/v2/users/me")"
echo "$ME" | jq -e '.username' >/dev/null || { echo "ERROR: session invalid" >&2; exit 1; }
echo "bootstrap: logged in as $(echo "$ME" | jq -r '.username')"

# --- 4. workspace template (Phase 2; skipped until it exists) ------------------
TEMPLATE_DIR="$ROOT/workspace/templates/standard"
if compgen -G "$TEMPLATE_DIR/main.tf" >/dev/null; then
  if bash "$ROOT/scripts/coder/push-template.sh"; then
    dlog "pushed coder template 'docker-standard' (stored in coder DB)"
    echo "bootstrap: template uploaded"
  else
    echo "bootstrap: WARNING — template push failed (continuing)" >&2
  fi
else
  echo "bootstrap: no workspace template yet (workspace/templates/standard/main.tf) — skipped"
fi

# --- 5. demo virtual key --------------------------------------------------------
if [[ ! -s "$DEMO_KEY_FILE" ]]; then
  DEMO_KEY="$("$ROOT/gateway/litellm/scripts/create-virtual-key.sh" "demo-developer" \
      "$LITELLM_DEFAULT_USER_BUDGET" "$LITELLM_DEFAULT_RPM" "$LITELLM_DEFAULT_TPM")"
  printf '%s' "$DEMO_KEY" > "$DEMO_KEY_FILE"
  dlog "issued demo LiteLLM virtual key -> .demo-virtual-key (gitignored; revoke via gateway /key/delete alias demo-developer)"
  echo "bootstrap: demo virtual key stored in .demo-virtual-key (budget=\$$LITELLM_DEFAULT_USER_BUDGET)"
else
  echo "bootstrap: demo virtual key already present"
fi

echo "bootstrap: done."

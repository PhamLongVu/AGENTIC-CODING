#!/usr/bin/env bash
# Fill every CHANGE_ME placeholder in .env with a random secret.
# Idempotent: already-generated values are left untouched.
# Secrets are written to .env ONLY (git-ignored); nothing is printed.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env not found. Run:  cp .env.example .env" >&2
  exit 1
fi

gen_password() { openssl rand -hex 24; }
gen_master_key() { echo "sk-$(openssl rand -hex 24)"; }

replace_placeholder() {   # var name -> new value
  local var="$1" val="$2"
  sed -i "s|^${var}=CHANGE_ME.*|${var}=${val}|" "$ENV_FILE"
}

replace_placeholder POSTGRES_PASSWORD "$(gen_password)"
replace_placeholder CODER_PG_PASSWORD "$(gen_password)"
replace_placeholder LITELLM_PG_PASSWORD "$(gen_password)"
replace_placeholder CODER_ADMIN_PASSWORD "$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-20)"
replace_placeholder LITELLM_MASTER_KEY "$(gen_master_key)"
replace_placeholder LITELLM_SALT_KEY "$(gen_password)"

remaining="$(grep -cE '(PASSWORD|KEY)=CHANGE_ME' "$ENV_FILE" || true)"
if [[ "$remaining" -gt 0 ]]; then
  echo "ERROR: $remaining CHANGE_ME placeholders left — inspect .env" >&2
  exit 1
fi

echo "gen-secrets: all placeholders filled (values written to .env, not shown)"

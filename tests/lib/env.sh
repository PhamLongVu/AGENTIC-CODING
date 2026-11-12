#!/usr/bin/env bash
# Shared test/script environment: loads .env safely and exports the vars
# tests and scripts need. Never prints secret values.
# NB: NO `set -e` here on purpose — this file is sourced by callers that
# manage their own error policy; forcing -e on them makes any failing
# command substitution (e.g. curl exit 6) abort their scripts silently.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ ! -f "$ROOT/.env" ]]; then
  echo "env.sh: $ROOT/.env missing — run: cp .env.example .env && make gen-secrets" >&2
  exit 1
fi

# read .env without executing it; strips comments and blank lines
_env_line() { grep -E "^$1=" "$ROOT/.env" | head -1 | cut -d= -f2- | sed 's/[[:space:]]*#.*$//'; }

export LITELLM_MASTER_KEY="$(_env_line LITELLM_MASTER_KEY)"
export LITELLM_BASE_URL="http://127.0.0.1:$(_env_line LITELLM_PORT 2>/dev/null || echo 4000)"
export LITELLM_PORT="$(_env_line LITELLM_PORT)"
export CODER_HTTP_PORT="$(_env_line CODER_HTTP_PORT)"
export CODER_ACCESS_URL="$(_env_line CODER_ACCESS_URL)"
export CODER_ADMIN_USER="$(_env_line CODER_ADMIN_USER)"
export CODER_ADMIN_EMAIL="$(_env_line CODER_ADMIN_EMAIL)"
export CODER_ADMIN_PASSWORD="$(_env_line CODER_ADMIN_PASSWORD)"
export CODER_PG_DATABASE="$(_env_line CODER_PG_DATABASE)"
export LITELLM_PG_DATABASE="$(_env_line LITELLM_PG_DATABASE)"
export LITELLM_DEFAULT_USER_BUDGET="$(_env_line LITELLM_DEFAULT_USER_BUDGET)"
export AI_PROVIDER_MODE="$(_env_line AI_PROVIDER_MODE)"
export WORKSPACE_DEFAULT_AUTOSTOP_MINUTES="$(_env_line WORKSPACE_DEFAULT_AUTOSTOP_MINUTES)"
export LITELLM_DEFAULT_RPM="$(_env_line LITELLM_DEFAULT_RPM)"
export LITELLM_DEFAULT_TPM="$(_env_line LITELLM_DEFAULT_TPM)"

# non-secret conveniences for curl targets
export CODER_API_URL="http://127.0.0.1:${CODER_HTTP_PORT:-7080}"

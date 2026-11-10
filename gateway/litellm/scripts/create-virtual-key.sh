#!/usr/bin/env bash
# Issue a LiteLLM virtual key for one developer (per-developer isolation of
# AI spend — docs/decisions/ADR-0004).
#
# Usage:
#   gateway/litellm/scripts/create-virtual-key.sh <coder-username> [budget_usd] [rpm] [tpm]
#
# Output: the generated key (sk-...) on stdout; everything else on stderr.
# The caller decides where it goes (bootstrap writes demo key to a
# git-ignored file; ops runbook documents the flow).
#
# Requires the platform stack to be running (LiteLLM in DB mode).
set -euo pipefail

USERNAME="${1:?usage: create-virtual-key.sh <coder-username> [budget_usd] [rpm] [tpm]}"
BUDGET="${2:-}"
RPM="${3:-}"
TPM="${4:-}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=../../tests/lib/env.sh
source "$ROOT/tests/lib/env.sh"

# --- payload ------------------------------------------------------------
PAYLOAD=$(jq -n --arg u "$USERNAME" '{key_alias: $u, models: ["anthropic.claude-3-5-sonnet-20241022-v2:0", "amazon.nova-pro-v1:0"]}')
if [[ -n "$BUDGET" ]]; then
  PAYLOAD=$(echo "$PAYLOAD" | jq --arg b "$BUDGET" '. + {max_budget: ($b|tonumber)}')
fi
if [[ -n "$RPM" ]]; then
  PAYLOAD=$(echo "$PAYLOAD" | jq --argjson r "$RPM" '. + {rpm: $r}')
fi
if [[ -n "$TPM" ]]; then
  PAYLOAD=$(echo "$PAYLOAD" | jq --argjson t "$TPM" '. + {tpm: $t}')
fi

# --- call the gateway ----------------------------------------------------
RESP="$(curl -sS -X POST "$LITELLM_BASE_URL/key/generate" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")"

KEY="$(echo "$RESP" | jq -r '.key // empty')"
if [[ -z "$KEY" ]]; then
  echo "ERROR: key generation failed. Response:" >&2
  echo "$RESP" | jq . >&2 || echo "$RESP" >&2
  exit 1
fi

echo "$KEY"
echo "created virtual key for '$USERNAME' (budget=$BUDGET rpm=$RPM tpm=$TPM)" >&2

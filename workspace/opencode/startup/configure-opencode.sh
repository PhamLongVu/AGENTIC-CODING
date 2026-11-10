#!/usr/bin/env bash
# Standalone OpenCode->LiteLLM configurator (same logic the workspace
# template's startup_script.sh applies). Useful for image smoke tests and
# for repairing a workspace whose config was deleted.
#
# Environment: LITELLM_BASE_URL (required), OPENCODE_PROVIDER_API_KEY
# (required by opencode at runtime, never written to disk by this script).
# Optional: $1 = template file (default: opencode.json next to this script's
# config sibling at workspace/opencode/config/opencode.json)
set -euo pipefail

: "${LITELLM_BASE_URL:?LITELLM_BASE_URL must point at the LiteLLM gateway}"
CONFIG_SRC="${1:-$(dirname "$0")/../config/opencode.json}"
CONFIG_DST="$HOME/.config/opencode/opencode.json"

if [[ -f "$CONFIG_DST" ]]; then
  echo "configure-opencode: $CONFIG_DST exists — leaving user config untouched"
  exit 0
fi

mkdir -p "$HOME/.config/opencode"
sed "s|__LITELLM_BASE_URL__|${LITELLM_BASE_URL}|g" "$CONFIG_SRC" > "$CONFIG_DST"
echo "configure-opencode: wrote $CONFIG_DST (gateway: $LITELLM_BASE_URL)"

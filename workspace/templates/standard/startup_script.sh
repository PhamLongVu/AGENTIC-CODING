#!/usr/bin/env bash
# Workspace startup script — runs INSIDE the workspace container as the
# non-root `coder` user, launched and supervised by the Coder agent.
#
# Order matters:
#   1. seed OpenCode's gateway config (only if the user hasn't got one —
#      a developer's own config always wins)
#   2. hand over to start-workspace-services.sh (baked into the image),
#      which starts code-server + OpenCode on container loopback
set -euo pipefail

# --- 1. OpenCode -> LiteLLM provider config ------------------------------------
if [[ ! -f "$HOME/.config/opencode/opencode.json" ]]; then
  mkdir -p "$HOME/.config/opencode"
  # LITELLM_BASE_URL and OPENCODE_PROVIDER_API_KEY are agent env vars set by
  # the template. The API key NEVER appears in this file — opencode expands
  # {env:OPENCODE_PROVIDER_API_KEY} at runtime.
  sed "s|__LITELLM_BASE_URL__|${LITELLM_BASE_URL:?missing}|g" \
    "$(dirname "$0")/opencode.json" \
    > "$HOME/.config/opencode/opencode.json"
  echo "startup: seeded ~/.config/opencode/opencode.json (gateway: $LITELLM_BASE_URL)"
else
  echo "startup: keeping existing user opencode config"
fi

mkdir -p "$HOME/projects"

# --- 2. start code-server + OpenCode (blocks as their supervisor) ---------------
exec /usr/local/bin/start-workspace-services.sh

#!/usr/bin/env bash
# Starts both developer-facing services inside a workspace container, bound
# to container loopback ONLY (Coder's authenticated app proxy exposes them):
#   code-server : IDE-first experience   (127.0.0.1:8080)
#   opencode    : chat-first AI coding   (127.0.0.1:4096)
# Both share /home/coder — same project files by construction (ADR-0006).
#
# Runs as the non-root `coder` user under the Coder agent's supervision
# (the workspace template calls this from its startup script).
set -euo pipefail

CODE_SERVER_BIN="$(command -v code-server)"
OPENCODE_BIN="$(command -v opencode)"

mkdir -p "$HOME/projects" "$HOME/.cache"

# Seed IDE defaults ONCE per volume (user edits afterwards are preserved).
CS_SETTINGS="$HOME/.local/share/code-server/User/settings.json"
if [[ ! -f "$CS_SETTINGS" ]]; then
  mkdir -p "$(dirname "$CS_SETTINGS")"
  cat > "$CS_SETTINGS" <<'SETTINGS'
{
  "update.mode": "none",
  "telemetry.enableTelemetry": false,
  "telemetry.enableCrashReporter": false,
  "extensions.autoCheckUpdates": false,
  "files.autoSave": "onFocusChange",
  "workbench.startupEditor": "none",
  "terminal.integrated.defaultProfile.linux": "bash"
}
SETTINGS
fi

cd "$HOME/projects"

# --- code-server ---------------------------------------------------------------
# --auth none is correct here: the listener is loopback-only inside the
# container; Coder's proxy enforces authentication upstream.
"$CODE_SERVER_BIN" \
  --bind-addr "${CODE_SERVER_BIND:-127.0.0.1:8080}" \
  --auth none \
  --disable-telemetry \
  --disable-update-check \
  >"${HOME}/.cache/code-server.log" 2>&1 &

# --- opencode (web/server mode) -------------------------------------------------
"$OPENCODE_BIN" serve \
  --hostname "${OPENCODE_HOST:-127.0.0.1}" \
  --port "${OPENCODE_PORT:-4096}" \
  >"${HOME}/.cache/opencode.log" 2>&1 &

# --- readiness gate (used by tests and the coder startup script) ---------------
wait_for() {  # <url> <name> <max_seconds>
  local url="$1" name="$2" max="${3:-60}" waited=0
  until curl -fsSo /dev/null "$url"; do
    sleep 1
    waited=$((waited + 1))
    if (( waited >= max )); then
      echo "start-workspace-services: $name did not become ready at $url" >&2
      return 1
    fi
  done
  echo "start-workspace-services: $name ready at $url"
}

wait_for "http://127.0.0.1:${CODE_SERVER_BIND##*:}" "code-server"
wait_for "http://127.0.0.1:${OPENCODE_PORT:-4096}" "opencode"

wait  # keep this process alive as the supervisor of both services

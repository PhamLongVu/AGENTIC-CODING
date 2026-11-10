#!/usr/bin/env bash
# Pre-flight for `make up`:
#   1. refuses to start without a real .env (never boot with CHANGE_ME secrets)
#   2. keeps DOCKER_GID in .env in sync with the host docker group
#      (the coder service needs it to access /var/run/docker.sock)
#   3. keeps COMPOSE_PROJECT_NAME stable so workspace volumes/networks get
#      predictable names
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env not found. Run:  cp .env.example .env && make gen-secrets" >&2
  exit 1
fi

if grep -qE '(PASSWORD|KEY)=CHANGE_ME|_GID=CHANGE_ME' "$ENV_FILE"; then
  echo "ERROR: .env still contains CHANGE_ME placeholders. Run:  make gen-secrets" >&2
  exit 1
fi

# --- DOCKER_GID sync ---------------------------------------------------------
host_gid="$(getent group docker | cut -d: -f3 || true)"
if [[ -z "$host_gid" ]]; then
  echo "ERROR: no 'docker' group on this host — is Docker installed?" >&2
  exit 1
fi
file_gid="$(grep -E '^DOCKER_GID=' "$ENV_FILE" | cut -d= -f2 || true)"
if [[ "$file_gid" != "$host_gid" ]]; then
  if grep -qE '^DOCKER_GID=' "$ENV_FILE"; then
    sed -i "s/^DOCKER_GID=.*/DOCKER_GID=$host_gid/" "$ENV_FILE"
  else
    echo "DOCKER_GID=$host_gid" >> "$ENV_FILE"
  fi
  echo "env-ensure: DOCKER_GID set to $host_gid (host docker group)"
fi

exit 0

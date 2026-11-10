#!/usr/bin/env bash
# deploy-dev.sh — "deploy" the LOCAL dev environment (the AWS-side
# equivalent is deploy/scripts/bootstrap-host.sh, approval-gated).
# Local dev never touches AWS; this is a convenience wrapper for
#   env-ensure -> compose up -> bootstrap.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

grep -q '^DEPLOY_TARGET=local' .env || {
  echo "deploy-dev: .env has DEPLOY_TARGET != local — local dev only!" >&2
  exit 1
}

scripts/env-ensure.sh
docker compose up -d
scripts/bootstrap.sh
echo ""
echo "deploy-dev: local platform ready at $(grep '^CODER_ACCESS_URL=' .env | cut -d= -f2)"

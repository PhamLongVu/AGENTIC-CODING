#!/usr/bin/env bash
# =============================================================================
# bootstrap-host.sh — run ON THE EC2 POC INSTANCE (owner-triggered only!)
# =============================================================================
# Preconditions (docs/operations/deployment.md runbook):
#   * terraform applied WITH owner approval; instance reachable
#   * this repo present on the host (rsync/git)
#   * public IP known => CODER_ACCESS_URL=http://<ip>:7080
#
# What it does: creates .env in AWS mode, generates secrets, starts the
# stack with the AWS override, bootstraps admin + template + demo key.
# What it NEVER does: create AWS resources, print secrets, open ports.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

[[ $EUID -eq 0 ]] || { echo "run as root on the instance (sudo)" >&2; exit 1; }
command -v docker >/dev/null || { echo "docker missing — user_data should have installed it" >&2; exit 1; }

PUBLIC_IP="$(curl -fsS --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 || true)"
[[ -n "$PUBLIC_IP" ]] || { echo "cannot discover public IP via IMDS" >&2; exit 1; }

if [[ ! -f .env ]]; then
  cp .env.example .env
  sed -i 's/^AI_PROVIDER_MODE=.*/AI_PROVIDER_MODE=bedrock/' .env
  sed -i 's/^DEPLOY_TARGET=.*/DEPLOY_TARGET=aws/' .env
  sed -i "s|^CODER_ACCESS_URL=.*|CODER_ACCESS_URL=http://${PUBLIC_IP}:7080|" .env
  scripts/gen-secrets.sh
  echo "bootstrap-host: .env created in AWS/bedrock mode (secrets not shown)"
else
  echo "bootstrap-host: .env exists — keeping it (delete to re-seed)"
fi

scripts/env-ensure.sh

# build the workspace image on the host (registry deferred — ADR repo layout)
docker build -t cloudcoding-workspace:dev workspace/images/development/

# start platform in AWS mode
docker compose -f docker-compose.yml -f deploy/compose/aws.yml up -d

# wait for coder, then bootstrap admin/template/demo key
for _ in $(seq 1 60); do
  curl -fsS "http://127.0.0.1:${CODER_HTTP_PORT:-7080}/api/v2/buildinfo" >/dev/null 2>&1 && break
  sleep 2
done
scripts/bootstrap.sh

echo ""
echo "bootstrap-host: platform is up at http://${PUBLIC_IP}:7080"
echo "next: deploy/scripts/validate-deployment.sh"

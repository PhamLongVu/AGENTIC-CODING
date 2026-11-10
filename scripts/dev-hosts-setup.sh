#!/usr/bin/env bash
# One-time local dev machine setup: make `host.docker.internal` resolve to
# 127.0.0.1 on the HOST so the developer's browser can open
# http://host.docker.internal:7080 (the same URL workspace containers use
# via extra_hosts host-gateway). See docs/architecture/overview.md §networking.
#
# Requires sudo; idempotent.
set -euo pipefail

MARKER="# cloud-coding-platform"
ENTRY="127.0.0.1 host.docker.internal ${MARKER}"

if grep -qF "$MARKER" /etc/hosts; then
  echo "dev-hosts-setup: /etc/hosts already contains host.docker.internal entry"
  exit 0
fi

if [[ $EUID -ne 0 ]]; then
  echo "This script needs sudo to edit /etc/hosts. Re-run as:"
  echo "  sudo make dev-hosts-setup"
  exit 1
fi

echo "$ENTRY" >> /etc/hosts
echo "dev-hosts-setup: added '$ENTRY' to /etc/hosts"

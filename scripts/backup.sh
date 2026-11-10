#!/usr/bin/env bash
# backup.sh — POC-grade platform backup (docs/operations/backup-restore.md):
#   * pg_dump of both application databases (coder + litellm)
#   * tar of every workspace home volume (coder-*-home, labelled managed-by=coder)
# Backups land in ./backups/<timestamp>/ (git-ignored). No cloud upload in
# the POC (S3 deferred — TASKS.md). Run on the docker host.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DEST="backups/$STAMP"
mkdir -p "$DEST"
trap 'rmdir "$DEST" 2>/dev/null || true' ERR

echo "backup: databases -> $DEST"
for db in coder litellm; do
  docker compose exec -T postgres pg_dump -U platform_admin -d "$db" | gzip > "$DEST/$db.sql.gz"
done

echo "backup: workspace volumes -> $DEST"
for vol in $(docker volume ls --format '{{.Name}}' | grep -E '^coder-.*-home$'); do
  echo "  $vol"
  docker run --rm -v "$vol:/src:ro" -v "$ROOT/$DEST:/dst:rw" alpine:3.20 \
    tar czf "/dst/$vol.tar.gz" -C /src . >/dev/null
done

# retention: keep the newest 7 backups
ls -1d backups/*/ 2>/dev/null | head -n -7 | xargs -r rm -rf

echo "backup: done -> $DEST ($(du -sh "$DEST" | cut -f1))"
echo "restore with: scripts/restore.sh $STAMP"

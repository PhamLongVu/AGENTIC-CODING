#!/usr/bin/env bash
# restore.sh <stamp> — restore platform databases and workspace volumes
# from backups/<stamp>/ created by scripts/backup.sh.
# DESTRUCTIVE (overwrites current data): asks for confirmation.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

STAMP="${1:?usage: restore.sh <backup-stamp>}"
SRC="backups/$STAMP"
[[ -d "$SRC" ]] || { echo "no such backup: $SRC" >&2; exit 1; }

echo "about to RESTORE from $SRC — this overwrites live data."
read -r -p "Type the stamp '$STAMP' to confirm: " confirm
[[ "$confirm" == "$STAMP" ]] || { echo "aborted"; exit 1; }

echo "restore: databases"
for db in coder litellm; do
  [[ -f "$SRC/$db.sql.gz" ]] || { echo "missing $SRC/$db.sql.gz" >&2; exit 1; }
  docker compose exec -T postgres psql -U platform_admin -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$db'" >/dev/null
  docker compose exec -T postgres psql -U platform_admin -d postgres -c "DROP DATABASE IF EXISTS $db" >/dev/null
  docker compose exec -T postgres psql -U platform_admin -d postgres -c "CREATE DATABASE $db OWNER ${db}_app" >/dev/null
  gunzip -c "$SRC/$db.sql.gz" | docker compose exec -T postgres psql -U platform_admin -d "$db" >/dev/null
done

echo "restore: workspace volumes (only volumes present in the backup)"
for tgz in "$SRC"/coder-*-home.tar.gz; do
  [[ -e "$tgz" ]] || break
  vol="$(basename "$tgz" .tar.gz)"
  docker volume inspect "$vol" >/dev/null 2>&1 || docker volume create "$vol" >/dev/null
  docker run --rm -v "$vol:/dst:rw" -v "$ROOT/$SRC:/src:ro" alpine:3.20 \
    sh -c "rm -rf /dst/* && tar xzf /src/$vol.tar.gz -C /dst" >/dev/null
  echo "  restored $vol"
done

echo "restore: done. Restart the stack (make restart) before using it."

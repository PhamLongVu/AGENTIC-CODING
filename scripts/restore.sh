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

# Postgres superuser name comes from .env (never hardcoded — renames in .env
# would silently break backup/restore while the rest of the stack honors it).
PG_ADMIN="$(grep -E '^POSTGRES_USER=' .env | head -1 | cut -d= -f2-)"
PG_ADMIN="${PG_ADMIN:-platform_admin}"

# Stop the services that hold DB connections BEFORE dropping databases —
# terminating backends alone races their connection pools (they reconnect in
# the ~1s window and DROP fails with "database is being accessed by other
# users", leaving the stack half-restored). Postgres itself stays up.
echo "restore: stopping coder + litellm (postgres stays up)"
docker compose stop coder litellm >/dev/null 2>&1 || true

restore_db() {  # <db>
  local db="$1"
  [[ -f "$SRC/$db.sql.gz" ]] || { echo "missing $SRC/$db.sql.gz" >&2; exit 1; }
  docker compose exec -T postgres psql -U "$PG_ADMIN" -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$db'" >/dev/null
  docker compose exec -T postgres psql -U "$PG_ADMIN" -d postgres -c "DROP DATABASE IF EXISTS $db" >/dev/null
  docker compose exec -T postgres psql -U "$PG_ADMIN" -d postgres -c "CREATE DATABASE $db OWNER ${db}_app" >/dev/null
  gunzip -c "$SRC/$db.sql.gz" | docker compose exec -T postgres psql -U "$PG_ADMIN" -d "$db" >/dev/null
}

echo "restore: databases"
restore_db coder
restore_db litellm

echo "restore: workspace volumes (only volumes present in the backup)"
for tgz in "$SRC"/coder-*-home.tar.gz; do
  [[ -e "$tgz" ]] || break
  vol="$(basename "$tgz" .tar.gz)"
  docker volume inspect "$vol" >/dev/null 2>&1 || docker volume create "$vol" >/dev/null
  docker run --rm -v "$vol:/dst:rw" -v "$ROOT/$SRC:/src:ro" alpine:3.20 \
    sh -c "rm -rf /dst/* && tar xzf /src/$vol.tar.gz -C /dst" >/dev/null
  echo "  restored $vol"
done

echo "restore: restarting coder + litellm"
docker compose start coder litellm >/dev/null 2>&1 || true

echo "restore: done."

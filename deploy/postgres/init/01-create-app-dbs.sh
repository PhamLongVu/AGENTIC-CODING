#!/bin/bash
# Creates the application databases and owners on first postgres start.
# Runs inside the postgres container (docker-entrypoint-initdb.d) with the
# POSTGRES_* env from docker-compose.yml. Passwords arrive via environment;
# they are interpolated by psql (single quotes keep them literal strings).
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
CREATE USER ${CODER_PG_USER} WITH PASSWORD '${CODER_PG_PASSWORD}';
CREATE DATABASE ${CODER_PG_DATABASE} OWNER ${CODER_PG_USER};
CREATE USER ${LITELLM_PG_USER} WITH PASSWORD '${LITELLM_PG_PASSWORD}';
CREATE DATABASE ${LITELLM_PG_DATABASE} OWNER ${LITELLM_PG_USER};
EOSQL

echo "app databases created: ${CODER_PG_DATABASE}, ${LITELLM_PG_DATABASE}"

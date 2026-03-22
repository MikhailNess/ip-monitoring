#!/usr/bin/env bash
set -e

ROLE="${ROLE:-app}"

: "${DATABASE_URL:?DATABASE_URL must be set}"

log_json() {
  local event="$1"
  local status="$2"
  local service="${LOG_NAMESPACE:-ip_monitoring}"
  printf '{"service":"%s","event":"%s","status":"%s"}\n' "$service" "$event" "$status"
}

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-${POSTGRES_USER:-monitoring}}"
DB_NAME="${DB_NAME:-${POSTGRES_DB:-monitoring}}"

wait_for_db() {
  log_json "db_wait_start" "retrying"
  until pg_isready -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" >/dev/null 2>&1; do
    sleep 2
  done
  log_json "db_ready" "success"
}

run_migrations() {
  log_json "migrations_start" "running"
  bundle exec rake db:migrate
  log_json "migrations_finish" "success"
}

wait_for_db

if [ "${ROLE}" = "app" ]; then
  run_migrations
else
  log_json "migrations_skip" "skipped"
fi

log_json "process_start" "starting"
exec "$@"


#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/../.env}"
DDL_FILE="${DDL_FILE:-$ROOT_DIR/ddl/create_tables_test.sql}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/data/apply_logs}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

MARIADB_DB="${MARIADB_DB:-${MARIADB_DATABASE:-grocy_db}}"
MARIADB_USER="${MARIADB_USER:-root}"
MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-}"
MARIADB_PASSWORD="${MARIADB_PASSWORD:-}"
if [[ "$MARIADB_USER" == "root" ]]; then
  MARIADB_AUTH_PASSWORD="$MARIADB_ROOT_PASSWORD"
else
  MARIADB_AUTH_PASSWORD="$MARIADB_PASSWORD"
fi

mkdir -p "$OUT_DIR"
run_id="$(date +%Y%m%d_%H%M%S)"
log_file="$OUT_DIR/apply_tables_$run_id.log"
err_file="$OUT_DIR/apply_tables_$run_id.err.log"
exec > >(tee -a "$log_file") 2> >(tee -a "$err_file" >&2)

echo "[INFO] Apply tables started at $(date -Iseconds)"

if [[ ! -f "$DDL_FILE" ]]; then
  echo "[ERROR] DDL file not found: $DDL_FILE"
  exit 2
fi

cat "$DDL_FILE" | docker compose exec -T mariadb sh -c \
  "MYSQL_PWD='$MARIADB_AUTH_PASSWORD' mysql -u'$MARIADB_USER' '$MARIADB_DB'"

echo "[INFO] Apply tables finished at $(date -Iseconds)"
echo "[INFO] Log: $log_file"
echo "[INFO] Errors: $err_file"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/../.env}"
DATA_DIR="${DATA_DIR:-$ROOT_DIR/data}"
OUT_DIR="${OUT_DIR:-$DATA_DIR/import_logs}"
TABLE_LIST="${TABLE_LIST:-$DATA_DIR/table_list.txt}"
SQL_MODE_RELAXED="${SQL_MODE_RELAXED:-1}"
SQLITE_DB="${SQLITE_DB:-$DATA_DIR/grocy.db}"

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

if [[ ! -f "$TABLE_LIST" ]]; then
  echo "Table list not found: $TABLE_LIST" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"
run_id="$(date +%Y%m%d_%H%M%S)"
log_file="$OUT_DIR/import_$run_id.log"
err_file="$OUT_DIR/import_$run_id.err.log"

exec > >(tee -a "$log_file") 2> >(tee -a "$err_file" >&2)

echo "[INFO] Import started at $(date -Iseconds)"

if [[ "$SQL_MODE_RELAXED" == "1" ]]; then
  sql_mode_cmd="SET SESSION sql_mode=''; SET FOREIGN_KEY_CHECKS=0; SET SESSION sql_mode='NO_ZERO_DATE';"
else
  sql_mode_cmd="SET FOREIGN_KEY_CHECKS=0;"
fi

# Disable all triggers to avoid 1442 errors during bulk import
echo "[INFO] Disabling triggers..."
for trigger in "products_default_qu_conversions" "products_INS" "products_UPD" "products_DELETE" "cascade_product_removal" "cascade_change_qu_id_stock" "cascade_change_qu_id_stock2"; do
  docker compose exec -T mariadb mysql -ugrocy -p"$MARIADB_PASSWORD" "$MARIADB_DB" -e "DROP TRIGGER IF EXISTS \`$trigger\`;" 2>/dev/null || true
done


success=0
failed=0
missing=0
missing_empty=0

while IFS= read -r table; do
  [[ -z "$table" ]] && continue
  sql_path="$DATA_DIR/exports/${table}.sql"
  if [[ ! -s "$sql_path" ]]; then
    if [[ -f "$SQLITE_DB" ]] && command -v sqlite3 >/dev/null 2>&1; then
      count=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM \"$table\";" 2>/dev/null || echo "")
      if [[ "$count" == "0" ]]; then
        echo "[INFO] Empty source table, skipping export: $table"
        missing_empty=$((missing_empty + 1))
        continue
      fi
    fi
    echo "[WARN] Missing export: $sql_path"
    missing=$((missing + 1))
    continue
  fi

  echo "[INFO] Importing $table"
  # Pipe the SQL file directly to mysql, prepending the sql_mode commands
  {
    echo "$sql_mode_cmd"
    cat "$sql_path"
  } | docker compose exec -T mariadb sh -c \
    "MYSQL_PWD='$MARIADB_AUTH_PASSWORD' mysql -u'$MARIADB_USER' '$MARIADB_DB'" && {
    success=$((success + 1))
  } || {
    echo "[ERROR] Import failed for $table"
    failed=$((failed + 1))
  }

done < "$TABLE_LIST"

echo "[INFO] Import finished at $(date -Iseconds)"

# Re-enable foreign key checks
echo "[INFO] Re-enabling foreign key checks and triggers..."
docker compose exec -T mariadb sh -c \
  "MYSQL_PWD='$MARIADB_AUTH_PASSWORD' mysql -u'$MARIADB_USER' '$MARIADB_DB' -e \"SET FOREIGN_KEY_CHECKS=1;\"" || true

# Recreate triggers from DDL files
echo "[INFO] Recreating triggers..."
for trigger_file in "$ROOT_DIR/ddl/triggers"/*.sql; do
  [[ -f "$trigger_file" ]] && docker compose exec -T mariadb sh -c \
    "MYSQL_PWD='$MARIADB_AUTH_PASSWORD' mysql -u'$MARIADB_USER' '$MARIADB_DB' < /dev/stdin" < "$trigger_file" 2>/dev/null || echo "[WARN] Could not recreate trigger from $trigger_file" >&2
done

echo "[INFO] Import finished at $(date -Iseconds)"
echo "[INFO] Success: $success, Failed: $failed, Missing: $missing, Empty skipped: $missing_empty"

echo "[INFO] Log: $log_file"
echo "[INFO] Errors: $err_file"

if [[ "$failed" -gt 0 ]]; then
  exit 1
fi

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/../.env}"
TRIGGERS_DIR="${TRIGGERS_DIR:-$ROOT_DIR/ddl/triggers}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/data/apply_logs}"
TRIGGER_LIST="${TRIGGER_LIST:-$ROOT_DIR/ddl/trigger_list.txt}"

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
log_file="$OUT_DIR/apply_triggers_$run_id.log"
err_file="$OUT_DIR/apply_triggers_$run_id.err.log"
exec > >(tee -a "$log_file") 2> >(tee -a "$err_file" >&2)

echo "[INFO] Apply triggers started at $(date -Iseconds)"

if [[ ! -d "$TRIGGERS_DIR" ]]; then
  echo "[ERROR] Triggers dir not found: $TRIGGERS_DIR"
  exit 2
fi

if [[ -f "$TRIGGER_LIST" ]]; then
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    sql="$TRIGGERS_DIR/$name.sql"
    if [[ ! -f "$sql" ]]; then
      echo "[WARN] Missing trigger file: $sql"
      continue
    fi
    echo "[INFO] Applying $(basename "$sql")"
    # Extract trigger name from the file and drop it first, then apply
    trigger_name=$(basename "$sql" .sql)
    {
      echo "DROP TRIGGER IF EXISTS \`$trigger_name\`;";
      cat "$sql"
    } | docker compose exec -T mariadb sh -c \
      "MYSQL_PWD='$MARIADB_AUTH_PASSWORD' mysql -u'$MARIADB_USER' '$MARIADB_DB'"
  done < "$TRIGGER_LIST"
else
  for sql in "$TRIGGERS_DIR"/*.sql; do
    [[ -f "$sql" ]] || continue
    echo "[INFO] Applying $(basename "$sql")"
    # Extract trigger name from the file and drop it first, then apply
    trigger_name=$(basename "$sql" .sql)
    {
      echo "DROP TRIGGER IF EXISTS \`$trigger_name\`;";
      cat "$sql"
    } | docker compose exec -T mariadb sh -c \
      "MYSQL_PWD='$MARIADB_AUTH_PASSWORD' mysql -u'$MARIADB_USER' '$MARIADB_DB'"
  done
fi

echo "[INFO] Apply triggers finished at $(date -Iseconds)"
echo "[INFO] Log: $log_file"
echo "[INFO] Errors: $err_file"

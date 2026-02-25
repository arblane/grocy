#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${DATA_DIR:-$ROOT_DIR/data}"
SQLITE_DB="${SQLITE_DB:-$DATA_DIR/grocy.db}"
OUT_DIR="${OUT_DIR:-$DATA_DIR/exports}"
TABLE_LIST="${TABLE_LIST:-$DATA_DIR/table_list.txt}"
LOG_DIR="${LOG_DIR:-$DATA_DIR/export_logs}"

mkdir -p "$OUT_DIR"
mkdir -p "$LOG_DIR"
log_file="$LOG_DIR/export_$(date +%Y%m%d_%H%M%S).log"
err_file="$LOG_DIR/export_$(date +%Y%m%d_%H%M%S).err.log"

exec > >(tee -a "$log_file") 2> >(tee -a "$err_file" >&2)

if [[ ! -f "$SQLITE_DB" ]]; then
  echo "[ERROR] SQLite DB not found: $SQLITE_DB" >&2
  exit 2
fi

if [[ ! -f "$TABLE_LIST" ]]; then
  echo "[ERROR] Table list not found: $TABLE_LIST" >&2
  exit 2
fi

if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "[ERROR] sqlite3 command not found" >&2
  exit 2
fi

echo "[INFO] Export started at $(date -Iseconds)"
echo "[INFO] Source: $SQLITE_DB"
echo "[INFO] Output: $OUT_DIR"

# Clear existing exports
echo "[INFO] Clearing existing exports from $OUT_DIR"
rm -f "$OUT_DIR"/*.sql

success=0
skipped=0
failed=0

while IFS= read -r table; do
  [[ -z "$table" ]] && continue
  
  export_file="$OUT_DIR/${table}.sql"
  
  # Check if table is empty
  count=$(sqlite3 "$SQLITE_DB" "SELECT COUNT(*) FROM \"$table\";" 2>/dev/null || echo "0")
  
  if [[ "$count" == "0" ]]; then
    echo "[INFO] Skipping empty table: $table (0 rows)"
    skipped=$((skipped + 1))
    # Create empty SQL file as placeholder
    : > "$export_file"
    continue
  fi
  
  echo "[INFO] Exporting $table ($count rows)"
  
  # Use sqlite3 dump to get INSERT statements
  # Filter for INSERT lines only and use sed to join wrapped lines
  sqlite3 "$SQLITE_DB" ".dump '$table'" 2>/dev/null | grep "^INSERT INTO" | \
    sed ':a; /);$/! { N; ba; }; s/\n//g' > "$export_file" || true
  
  # Verify file has content
  if [[ -s "$export_file" ]]; then
    success=$((success + 1))
  else
    echo "[ERROR] Export created empty file for $table"
    failed=$((failed + 1))
  fi
  
done < "$TABLE_LIST"

echo "[INFO] Export finished at $(date -Iseconds)"
echo "[INFO] Success: $success, Skipped: $skipped, Failed: $failed"
echo "[INFO] Log: $log_file"
echo "[INFO] Errors: $err_file"

if [[ "$failed" -gt 0 ]]; then
  exit 1
fi

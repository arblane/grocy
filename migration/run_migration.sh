#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/../.env}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/data/run_logs}"
mkdir -p "$OUT_DIR"
run_id="$(date +%Y%m%d_%H%M%S)"
log_file="$OUT_DIR/run_$run_id.log"
err_file="$OUT_DIR/run_$run_id.err.log"
exec > >(tee -a "$log_file") 2> >(tee -a "$err_file" >&2)

if [[ -f "$ENV_FILE" ]]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

MARIADB_DB="${MARIADB_DB:-${MARIADB_DATABASE:-grocy_db}}"
MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-}"

run_export=0
run_reset=0
run_tables=0
run_import=0
run_views=0
run_triggers=0
run_validate=0
dry_run=0
declare -A step_status

print_usage() {
  cat <<'USAGE'
Usage: migration/run_migration.sh [options]

Options:
  --all           Run export + reset (optional) + tables + import + views + triggers + validate
  --export        Export tables from SQLite (migration/data/grocy.db)
  --reset-db      Drop and recreate the database
  --tables        Apply tables (apply_tables_with_logs.sh)
  --import        Import data (import_with_logs.sh)
  --views         Apply views (apply_views_with_logs.sh)
  --triggers      Apply triggers (apply_triggers_with_logs.sh)
  --validate      Run validation (validate_migration.sh)
  --dry-run       Print commands without executing them
  -h, --help      Show this help

Examples:
  migration/run_migration.sh --export --reset-db --tables --import --views --triggers --validate
  migration/run_migration.sh --all
  migration/run_migration.sh --export --import --validate
USAGE
}

if [[ $# -eq 0 ]]; then
  print_usage
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)
      run_export=1
      run_tables=1
      run_import=1
      run_views=1
      run_triggers=1
      run_validate=1
      ;;
    --export)
      run_export=1
      ;;
    --reset-db)
      run_reset=1
      ;;
    --tables)
      run_tables=1
      ;;
    --import)
      run_import=1
      ;;
    --views)
      run_views=1
      ;;
    --triggers)
      run_triggers=1
      ;;
    --validate)
      run_validate=1
      ;;
    --dry-run)
      dry_run=1
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      print_usage
      exit 2
      ;;
  esac
  shift

done

run_step() {
  local label="$1"
  shift
  if [[ "$dry_run" -eq 1 ]]; then
    echo "[DRY RUN] $label: $*"
    step_status["$label"]="DRY-RUN"
    return 0
  fi
  set +e
  "$@"
  local rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    step_status["$label"]="OK"
  else
    step_status["$label"]="FAIL($rc)"
  fi
  return $rc
}

run_shell() {
  local label="$1"
  local cmd="$2"
  if [[ "$dry_run" -eq 1 ]]; then
    echo "[DRY RUN] $label: $cmd"
    step_status["$label"]="DRY-RUN"
    return 0
  fi
  set +e
  bash -c "$cmd"
  local rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    step_status["$label"]="OK"
  else
    step_status["$label"]="FAIL($rc)"
  fi
  return $rc
}

check_empty_tables() {
  local tables_checked=0
  local empty_tables=()
  
  echo "[INFO] Checking for empty tables..."
  while IFS= read -r table; do
    [[ -z "$table" ]] && continue
    tables_checked=$((tables_checked + 1))
    count=$(docker compose exec -T mariadb sh -c "MYSQL_PWD='$MARIADB_PASSWORD' mysql -N -u'grocy' '$MARIADB_DB' -e \"SELECT COUNT(*) FROM \\\`$table\\\`;\"" 2>/dev/null || echo "0")
    if [[ "$count" == "0" ]]; then
      empty_tables+=("$table")
    fi
  done < "$ROOT_DIR/data/table_list.txt"
  
  if (( ${#empty_tables[@]} > 0 )); then
    echo "[WARNING] $((${#empty_tables[@]})) table(s) imported with 0 rows:"
    printf '  - %s\n' "${empty_tables[@]}"
    return 1
  else
    echo "[INFO] All $tables_checked tables have data"
    return 0
  fi
}

print_summary() {
  local overall="SUCCESS"
  local any_fail=0
  for key in "export" "reset" "tables" "import" "post_import" "import_verification" "views" "triggers" "validate"; do
    if [[ "${step_status[$key]-}" == FAIL* ]]; then
      any_fail=1
    fi
  done
  if [[ "$dry_run" -eq 1 ]]; then
    overall="DRY-RUN"
  elif [[ $any_fail -eq 1 ]]; then
    overall="PARTIAL"
  fi

  echo "[SUMMARY] Run: $overall"
  echo "[SUMMARY] export=${step_status[export]-SKIPPED} reset=${step_status[reset]-SKIPPED} tables=${step_status[tables]-SKIPPED} import=${step_status[import]-SKIPPED} post_import=${step_status[post_import]-SKIPPED} import_verification=${step_status[import_verification]-SKIPPED} views=${step_status[views]-SKIPPED} triggers=${step_status[triggers]-SKIPPED} validate=${step_status[validate]-SKIPPED}"
  echo "[SUMMARY] Log: $log_file"
  echo "[SUMMARY] Errors: $err_file"
}

trap print_summary EXIT

if [[ "$run_export" -eq 1 ]]; then
  echo "[INFO] Exporting tables from SQLite"
  run_step "export" "$ROOT_DIR/export_tables_from_sqlite.sh"
fi

if [[ "$run_reset" -eq 1 ]]; then
  echo "[INFO] Resetting database $MARIADB_DB"
  run_shell "reset" \
    "docker compose exec -T mariadb sh -c \"MYSQL_PWD='$MARIADB_ROOT_PASSWORD' mysql -uroot -e \\\"DROP DATABASE IF EXISTS $MARIADB_DB; CREATE DATABASE $MARIADB_DB CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;\\\"\""
fi

if [[ "$run_tables" -eq 1 ]]; then
  echo "[INFO] Applying tables"
  run_step "tables" "$ROOT_DIR/apply_tables_with_logs.sh"
fi

if [[ "$run_import" -eq 1 ]]; then
  echo "[INFO] Importing data"
  run_step "import" "$ROOT_DIR/import_with_logs.sh"
  
  # Auto-check for empty tables after import
  if [[ "$dry_run" -eq 0 ]] && [[ "${step_status[import]-}" == "OK" ]]; then
    check_empty_tables
    import_check_rc=$?
    if [[ $import_check_rc -ne 0 ]]; then
      step_status["import_verification"]="WARNING"
    else
      step_status["import_verification"]="OK"
    fi
    
    # Apply indexes and computed columns after import
    echo "[INFO] Applying post-import computed columns"
    {
      # Temporarily disable ALL products triggers during UPDATE
      echo "SET @TRIGGER_CHECKS=0;"
      # Drop all triggers on products table
      for trigger in default_qu_id_consume enforce_parent_product_id_null_when_empty_INS \
                     enforce_min_stock_amount_for_cumulated_childs_INS products_default_qu_conversions \
                     enforce_parent_product_id_null_when_empty_UPD enfore_product_nesting_level \
                     enforce_min_stock_amount_for_cumulated_childs_UPD cascade_product_removal \
                     products_INS products_UPD products_DELETE; do
        echo "DROP TRIGGER IF EXISTS \`$trigger\`;"
      done
      cat "$ROOT_DIR/ddl/post_import_updates.sql"
      # Re-enable trigger checks
      echo "SET @TRIGGER_CHECKS=1;"
    } | docker compose exec -T mariadb sh -c \
      "MYSQL_PWD='$MARIADB_PASSWORD' mysql -ugrocy '$MARIADB_DB'" && \
      step_status["post_import"]="OK" || \
      step_status["post_import"]="FAIL"
  fi
fi

if [[ "$run_views" -eq 1 ]]; then
  echo "[INFO] Applying views"
  run_step "views" "$ROOT_DIR/apply_views_with_logs.sh"
fi

if [[ "$run_triggers" -eq 1 ]]; then
  echo "[INFO] Applying triggers"
  run_step "triggers" "$ROOT_DIR/apply_triggers_with_logs.sh"
fi

if [[ "$run_validate" -eq 1 ]]; then
  echo "[INFO] Running validation"
  run_step "validate" "$ROOT_DIR/validate_migration.sh"
fi

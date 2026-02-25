#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/../.env}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/data/validation}"
mkdir -p "$OUT_DIR"
run_id="$(date +%Y%m%d_%H%M%S)"
log_file="$OUT_DIR/validate_$run_id.log"
err_file="$OUT_DIR/validate_$run_id.err.log"
exec > >(tee -a "$log_file") 2> >(tee -a "$err_file" >&2)
if [[ -f "$ENV_FILE" ]]; then
  set -a
  . "$ENV_FILE"
  set +a
fi
DATA_DIR="${DATA_DIR:-$ROOT_DIR/data}"
SQLITE_DB="${SQLITE_DB:-$DATA_DIR/grocy.db}"
TABLE_LIST="${TABLE_LIST:-$DATA_DIR/table_list.txt}"
MARIADB_CONTAINER="${MARIADB_CONTAINER:-}"
MARIADB_DB="${MARIADB_DB:-${MARIADB_DATABASE:-grocy_db}}"
MARIADB_USER="${MARIADB_USER:-root}"
MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-}"
MARIADB_PASSWORD="${MARIADB_PASSWORD:-}"
if [[ "$MARIADB_USER" == "root" ]]; then
  MARIADB_AUTH_PASSWORD="$MARIADB_ROOT_PASSWORD"
else
  MARIADB_AUTH_PASSWORD="$MARIADB_PASSWORD"
fi
EXPECTED_VIEWS=(
  batteries_current
  chores_assigned_users_resolved
  chores_current
  chores_execution_average_frequency
  chores_execution_timeline
  chores_execution_users_statistics
  meal_plan_internal_recipe_relation
  permission_tree
  product_barcodes_comma_separated
  product_barcodes_view
  product_qu_relations
  products_average_price
  products_current_price
  products_current_substitutions
  products_last_purchased
  products_price_history
  products_resolved
  products_view
  products_volatile_status
  quantity_unit_conversions_resolved
  quantity_units_resolved
  recipes_missing_product_counts
  recipes_nestings_resolved
  recipes_pos_resolved
  recipes_resolved
  shopping_lists_view
  stock_average_product_shelf_life
  stock_current
  stock_current_location_content
  stock_current_locations
  stock_edited_entries
  stock_missing_products
  stock_next_use
  stock_splits
  tasks_current
  uihelper_product_details
  uihelper_shopping_list
  uihelper_stock_current_overview
  uihelper_stock_entries
  uihelper_stock_journal
  uihelper_stock_journal_summary
  uihelper_user_permissions
  user_permissions_resolved
  userfield_values_resolved
  users_dto
)
EXPECTED_TRIGGERS=(
  cascade_battery_removal
  cascade_chore_removal
  cascade_product_removal
  cascade_userfield_removal
  create_internal_recipe
  default_qu_id_consume
  default_qu_INS
  default_qu_UPD
  default_start_date_when_empty_INS
  default_start_date_when_empty_UPD
  enforce_parent_product_id_null_when_empty_INS
  enforce_parent_product_id_null_when_empty_UPD
  enfore_product_nesting_level
  prevent_adding_barcodes_for_not_existing_products
  prevent_adding_no_own_stock_products_to_stock
  prevent_empty_userfields_INS
  prevent_empty_userfields_UPD
  prevent_infinite_nested_recipes_INS
  prevent_infinite_nested_recipes_UPD
  prevent_internal_meal_plan_section_removal
  prevent_self_nested_recipes_INS
  prevent_self_nested_recipes_UPD
  products_default_qu_conversions
  products_DELETE
  products_INS
  products_UPD
  quantity_unit_conversions_DEL
  quantity_unit_conversions_INS
  quantity_unit_conversions_UPD
  qu_conversions_custom_constraint_INS
  qu_conversions_custom_constraint_UPD
  recipes_desired_servings_default
  recipes_pos_qu_id_default
  remove_conversions
  remove_internal_recipe
  remove_items_from_deleted_shopping_list
  remove_recipe_from_meal_plans
  set_products_default_location_if_empty_stock
  set_products_default_location_if_empty_stock_log
  shopping_list_defaults_INS
  shopping_list_defaults_UPD
  stock_log_DEL
  stock_log_INS
  stock_log_UPD
  stock_missing_products
  update_internal_recipe
  userfield_values_special_handling_INS
)

snapshot=0
for arg in "$@"; do
  case "$arg" in
    --snapshot)
      snapshot=1
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

mkdir -p "$OUT_DIR"

if [[ ! -f "$SQLITE_DB" ]]; then
  echo "SQLite DB not found: $SQLITE_DB" >&2
  exit 2
fi

if [[ ! -f "$TABLE_LIST" ]]; then
  echo "Table list not found: $TABLE_LIST" >&2
  exit 2
fi

if [[ -n "$MARIADB_CONTAINER" ]]; then
  if ! docker inspect -f '{{.State.Running}}' "$MARIADB_CONTAINER" >/dev/null 2>&1; then
    echo "MariaDB container not running: $MARIADB_CONTAINER" >&2
    exit 2
  fi
else
  if ! docker compose ps --status running --services | grep -qx mariadb; then
    echo "MariaDB service not running: mariadb" >&2
    exit 2
  fi
fi

sqlite_counts="$OUT_DIR/sqlite_row_counts.tsv"
mariadb_counts="$OUT_DIR/mariadb_row_counts.tsv"
report="$OUT_DIR/row_count_report.tsv"
mismatches="$OUT_DIR/row_count_mismatches.tsv"
missing_tables="$OUT_DIR/mariadb_missing_tables.txt"

: > "$sqlite_counts"
: > "$mariadb_counts"
: > "$missing_tables"

while IFS= read -r table; do
  [[ -z "$table" ]] && continue
  sqlite3 -separator $'\t' "$SQLITE_DB" "SELECT '$table', COUNT(*) FROM \"$table\";" >> "$sqlite_counts"
  if [[ -n "$MARIADB_CONTAINER" ]]; then
    exists=$(docker exec -i "$MARIADB_CONTAINER" sh -c \
      "MYSQL_PWD='$MARIADB_AUTH_PASSWORD' mysql -N -u'$MARIADB_USER' '$MARIADB_DB' -e \"SELECT 1 FROM information_schema.tables WHERE table_schema = '$MARIADB_DB' AND table_name = '$table' LIMIT 1;\"" </dev/null)
  else
    exists=$(docker compose exec -T mariadb sh -c \
      "MYSQL_PWD='$MARIADB_AUTH_PASSWORD' mysql -N -u'$MARIADB_USER' '$MARIADB_DB' -e \"SELECT 1 FROM information_schema.tables WHERE table_schema = '$MARIADB_DB' AND table_name = '$table' LIMIT 1;\"" </dev/null)
  fi
  if [[ -z "$exists" ]]; then
    echo "$table" >> "$missing_tables"
    continue
  fi
  if [[ -n "$MARIADB_CONTAINER" ]]; then
    docker exec -i "$MARIADB_CONTAINER" sh -c \
      "MYSQL_PWD='$MARIADB_AUTH_PASSWORD' mysql -N -u'$MARIADB_USER' '$MARIADB_DB' -e \"SELECT '$table', COUNT(*) FROM \\\`$table\\\`;\"" \
      >> "$mariadb_counts" </dev/null
  else
    docker compose exec -T mariadb sh -c \
      "MYSQL_PWD='$MARIADB_AUTH_PASSWORD' mysql -N -u'$MARIADB_USER' '$MARIADB_DB' -e \"SELECT '$table', COUNT(*) FROM \\\`$table\\\`;\"" \
      >> "$mariadb_counts" </dev/null
  fi
done < "$TABLE_LIST"

sort -k1,1 "$sqlite_counts" > "$sqlite_counts.sorted"
sort -k1,1 "$mariadb_counts" > "$mariadb_counts.sorted"

join -t $'\t' -a 1 -a 2 -e 0 -o 0,1.2,2.2 \
  "$sqlite_counts.sorted" "$mariadb_counts.sorted" > "$report"

awk -F'\t' '$2 != $3 {print}' "$report" > "$mismatches"

exit_code=0
if [[ -s "$mismatches" ]]; then
  echo "Row count mismatches found: $mismatches"
  exit_code=1
else
  echo "Row count check OK"
fi

if [[ -s "$missing_tables" ]]; then
  echo "MariaDB missing tables listed in: $missing_tables"
  exit_code=1
fi

views_out="$OUT_DIR/views_present.txt"
triggers_out="$OUT_DIR/triggers_present.txt"
expected_views_file="$OUT_DIR/expected_views.txt"
expected_triggers_file="$OUT_DIR/expected_triggers.txt"

: > "$views_out"
: > "$triggers_out"

if [[ -n "$MARIADB_CONTAINER" ]]; then
  docker exec -i "$MARIADB_CONTAINER" sh -c \
    "MYSQL_PWD='$MARIADB_AUTH_PASSWORD' mysql -N -u'$MARIADB_USER' '$MARIADB_DB' -e \"SELECT table_name FROM information_schema.VIEWS WHERE table_schema = '$MARIADB_DB';\"" \
    | sort -u > "$views_out"

  docker exec -i "$MARIADB_CONTAINER" sh -c \
    "MYSQL_PWD='$MARIADB_AUTH_PASSWORD' mysql -N -u'$MARIADB_USER' '$MARIADB_DB' -e \"SELECT trigger_name FROM information_schema.TRIGGERS WHERE trigger_schema = '$MARIADB_DB';\"" \
    | sort -u > "$triggers_out"
else
  docker compose exec -T mariadb sh -c \
    "MYSQL_PWD='$MARIADB_AUTH_PASSWORD' mysql -N -u'$MARIADB_USER' '$MARIADB_DB' -e \"SELECT table_name FROM information_schema.VIEWS WHERE table_schema = '$MARIADB_DB';\"" \
    | sort -u > "$views_out"

  docker compose exec -T mariadb sh -c \
    "MYSQL_PWD='$MARIADB_AUTH_PASSWORD' mysql -N -u'$MARIADB_USER' '$MARIADB_DB' -e \"SELECT trigger_name FROM information_schema.TRIGGERS WHERE trigger_schema = '$MARIADB_DB';\"" \
    | sort -u > "$triggers_out"
fi

if [[ "$snapshot" -eq 1 ]]; then
  cp "$views_out" "$expected_views_file"
  cp "$triggers_out" "$expected_triggers_file"
  echo "Snapshot saved: $expected_views_file"
  echo "Snapshot saved: $expected_triggers_file"
fi

if [[ -f "$expected_views_file" ]]; then
  mapfile -t EXPECTED_VIEWS < "$expected_views_file"
fi

if [[ -f "$expected_triggers_file" ]]; then
  mapfile -t EXPECTED_TRIGGERS < "$expected_triggers_file"
fi

missing_views=()
for view in "${EXPECTED_VIEWS[@]}"; do
  if ! grep -qx "$view" "$views_out"; then
    missing_views+=("$view")
  fi
done

missing_triggers=()
for trigger in "${EXPECTED_TRIGGERS[@]}"; do
  if ! grep -qx "$trigger" "$triggers_out"; then
    missing_triggers+=("$trigger")
  fi
done

if (( ${#missing_views[@]} > 0 )); then
  printf 'Missing views:\n  %s\n' "${missing_views[@]}"
  exit_code=1
else
  echo "View check OK"
fi

if (( ${#missing_triggers[@]} > 0 )); then
  printf 'Missing triggers:\n  %s\n' "${missing_triggers[@]}"
  exit_code=1
else
  echo "Trigger check OK"
fi

if [[ -n "${MANUALS_DIR:-}" ]]; then
  if [[ ! -d "$MANUALS_DIR" ]]; then
    echo "MANUALS_DIR does not exist: $MANUALS_DIR" >&2
    exit_code=1
  else
    manuals_out="$OUT_DIR/manuals_missing.txt"
    : > "$manuals_out"
    if [[ -n "$MARIADB_CONTAINER" ]]; then
      docker exec -i "$MARIADB_CONTAINER" sh -c \
        "MYSQL_PWD='$MARIADB_AUTH_PASSWORD' mysql -N -u'$MARIADB_USER' '$MARIADB_DB' -e \"SELECT instruction_manual_file_name FROM equipment WHERE instruction_manual_file_name IS NOT NULL AND instruction_manual_file_name <> '';\"" \
        | while IFS= read -r manual; do
            [[ -z "$manual" ]] && continue
            if [[ ! -f "$MANUALS_DIR/$manual" ]]; then
              echo "$manual" >> "$manuals_out"
            fi
          done
    else
      docker compose exec -T mariadb sh -c \
        "MYSQL_PWD='$MARIADB_AUTH_PASSWORD' mysql -N -u'$MARIADB_USER' '$MARIADB_DB' -e \"SELECT instruction_manual_file_name FROM equipment WHERE instruction_manual_file_name IS NOT NULL AND instruction_manual_file_name <> '';\"" \
        | while IFS= read -r manual; do
            [[ -z "$manual" ]] && continue
            if [[ ! -f "$MANUALS_DIR/$manual" ]]; then
              echo "$manual" >> "$manuals_out"
            fi
          done
    fi
    if [[ -s "$manuals_out" ]]; then
      echo "Missing manuals listed in: $manuals_out"
      exit_code=1
    else
      echo "Manuals check OK"
    fi
  fi
fi

exit "$exit_code"

#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/../.env}"
VIEWS_DIR="${VIEWS_DIR:-$ROOT_DIR/ddl/views}"
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
log_file="$OUT_DIR/apply_views_$run_id.log"
err_file="$OUT_DIR/apply_views_$run_id.err.log"
exec > >(tee -a "$log_file") 2> >(tee -a "$err_file" >&2)

echo "[INFO] Apply views started at $(date -Iseconds)"

if [[ ! -d "$VIEWS_DIR" ]]; then
  echo "[ERROR] Views dir not found: $VIEWS_DIR"
  exit 2
fi

ordered_views=(
  "grocy_user_setting.sql"
  "permission_tree.sql"
  "users_dto.sql"
  "user_permissions_resolved.sql"
  "chores_execution_timeline.sql"
  "chores_execution_average_frequency.sql"
  "quantity_units_resolved.sql"
  "stock_edited_entries.sql"
  "products_view.sql"
  "products_resolved.sql"
  "stock_current.sql"
  "stock_next_use.sql"
  "product_qu_relations.sql"
  "products_average_price.sql"
  "products_current_price.sql"
  "products_current_substitutions.sql"
  "products_price_history.sql"
  "products_last_purchased.sql"
  "stock_missing_products.sql"
  "products_volatile_status.sql"
  "recipes_nestings_resolved.sql"
  "recipes_pos_resolved.sql"
  "recipes_missing_product_counts.sql"
  "recipes_resolved.sql"
  "product_barcodes_comma_separated.sql"
  "uihelper_shopping_list.sql"
  "stock_splits.sql"
)

for view in "${ordered_views[@]}"; do
  sql="$VIEWS_DIR/$view"
  [[ -f "$sql" ]] || continue
  echo "[INFO] Applying $view"
  cat "$sql" | docker compose exec -T mariadb sh -c \
    "MYSQL_PWD='$MARIADB_AUTH_PASSWORD' mysql -u'$MARIADB_USER' '$MARIADB_DB'"
done

for sql in "$VIEWS_DIR"/*.sql; do
  [[ -f "$sql" ]] || continue
  basename="$(basename "$sql")"
  skip=0
  for view in "${ordered_views[@]}"; do
    if [[ "$basename" == "$view" ]]; then
      skip=1
      break
    fi
  done
  if [[ "$skip" -eq 1 ]]; then
    continue
  fi
  echo "[INFO] Applying $basename"
  cat "$sql" | docker compose exec -T mariadb sh -c \
    "MYSQL_PWD='$MARIADB_AUTH_PASSWORD' mysql -u'$MARIADB_USER' '$MARIADB_DB'"
done

echo "[INFO] Apply views finished at $(date -Iseconds)"
echo "[INFO] Log: $log_file"
echo "[INFO] Errors: $err_file"

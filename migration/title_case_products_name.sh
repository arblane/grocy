#!/usr/bin/env bash
set -euo pipefail

# Utility: Preview/apply/rollback proper-case updates for grocy products.name.
# Purpose:
# - Normalize product names to title case.
# - Preserve configured small words in lowercase for non-leading positions
#   (for example: "of", "and", "the").
# - Keep a rollback-safe backup snapshot for every apply run.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ ! -f "${STACK_DIR}/docker-compose.yml" ]]; then
  echo "Could not find docker-compose.yml in ${STACK_DIR}" >&2
  exit 1
fi

if [[ ! -f "${STACK_DIR}/.env" ]]; then
  echo "Could not find .env in ${STACK_DIR}" >&2
  exit 1
fi

set -a
source "${STACK_DIR}/.env"
set +a

MODE="${1:-preview}"
RUN_ID="${2:-}"
REFRESH_FUNCTIONS="${REFRESH_FUNCTIONS:-0}"
LOCK_WAIT_TIMEOUT="${LOCK_WAIT_TIMEOUT:-15}"
LOCK_RETRY_COUNT="${LOCK_RETRY_COUNT:-5}"
LOCK_RETRY_DELAY="${LOCK_RETRY_DELAY:-3}"
PAUSE_GROCY_ON_APPLY="${PAUSE_GROCY_ON_APPLY:-0}"
BATCH_SIZE="${BATCH_SIZE:-200}"
MAX_BATCHES="${MAX_BATCHES:-0}"
OFFLINE_QUIESCE_TIMEOUT="${OFFLINE_QUIESCE_TIMEOUT:-45}"
OFFLINE_KILL_GROCY_SESSIONS="${OFFLINE_KILL_GROCY_SESSIONS:-1}"

SMALL_WORDS_CSV="${SMALL_WORDS_CSV:-a,an,and,as,at,but,by,for,from,in,into,nor,of,on,onto,or,over,per,so,the,to,up,via,vs,with,yet}"
PRESERVE_UPPER_WORDS_CSV="${PRESERVE_UPPER_WORDS_CSV:-aa,aaa}"

build_small_words_sql_list() {
  local csv="$1"
  local IFS=','
  local -a words=()
  local word
  local sql_list=""

  read -r -a words <<< "$csv"

  for word in "${words[@]}"; do
    word="$(echo "${word}" | tr '[:upper:]' '[:lower:]' | xargs)"
    [[ -z "${word}" ]] && continue
    word="${word//\'/\'\'}"
    if [[ -z "${sql_list}" ]]; then
      sql_list="'${word}'"
    else
      sql_list+=",'${word}'"
    fi
  done

  if [[ -z "${sql_list}" ]]; then
    sql_list="'__none__'"
  fi

  echo "${sql_list}"
}

build_preserve_upper_words_sql_list() {
  local csv="$1"
  local IFS=','
  local -a words=()
  local word
  local sql_list=""

  read -r -a words <<< "$csv"

  for word in "${words[@]}"; do
    word="$(echo "${word}" | tr '[:upper:]' '[:lower:]' | xargs)"
    [[ -z "${word}" ]] && continue
    word="${word//\'/\'\'}"
    if [[ -z "${sql_list}" ]]; then
      sql_list="'${word}'"
    else
      sql_list+=",'${word}'"
    fi
  done

  if [[ -z "${sql_list}" ]]; then
    sql_list="'__none__'"
  fi

  echo "${sql_list}"
}

SMALL_WORDS_SQL_LIST="$(build_small_words_sql_list "${SMALL_WORDS_CSV}")"
PRESERVE_UPPER_WORDS_SQL_LIST="$(build_preserve_upper_words_sql_list "${PRESERVE_UPPER_WORDS_CSV}")"

print_usage() {
  cat <<EOF
Usage: $0 [preview|apply|apply-offline|apply-resume <run_id>|rollback <run_id>]

Purpose:
  Title-case products.name, preserve lowercase small words after the first word,
  and keep rollback backups in products_name_backup.

Modes:
  preview             Show proposed changes only.
  apply               Backup + update products.name.
  apply-offline       Stop grocy, run apply, restart grocy.
  apply-resume <run_id>
                      Resume batched apply from a prior run_id.
  rollback <run_id>   Restore names from a prior apply run.

Configuration:
  SMALL_WORDS_CSV     Comma-separated lowercase words to keep lowercase
                      in non-leading positions.
                      Default: ${SMALL_WORDS_CSV}
  PRESERVE_UPPER_WORDS_CSV
                      Comma-separated words to force UPPERCASE output
                      regardless of position.
                      Default: ${PRESERVE_UPPER_WORDS_CSV}
  REFRESH_FUNCTIONS   Set to 1 to force DROP/CREATE of helper functions.
                      Default: ${REFRESH_FUNCTIONS}
  LOCK_WAIT_TIMEOUT   InnoDB lock wait timeout seconds per attempt.
                      Default: ${LOCK_WAIT_TIMEOUT}
  LOCK_RETRY_COUNT    Number of retry attempts on ERROR 1205.
                      Default: ${LOCK_RETRY_COUNT}
  LOCK_RETRY_DELAY    Seconds to wait between lock-timeout retries.
                      Default: ${LOCK_RETRY_DELAY}
  BATCH_SIZE          Number of products to process per apply batch.
                      Lower values reduce lock contention.
                      Default: ${BATCH_SIZE}
  MAX_BATCHES         Optional limit of batches per run (0 = unlimited).
                      Useful for test runs.
                      Default: ${MAX_BATCHES:-0}
  PAUSE_GROCY_ON_APPLY
                      Set to 1 to stop grocy service during apply and
                      restart it afterwards (recommended if lock errors persist).
                      Default: ${PAUSE_GROCY_ON_APPLY}
  OFFLINE_QUIESCE_TIMEOUT
                      Seconds to wait for lingering grocy DB transactions to end
                      after stopping grocy service in offline mode.
                      Default: ${OFFLINE_QUIESCE_TIMEOUT}
  OFFLINE_KILL_GROCY_SESSIONS
                      In offline mode, kill lingering DB sessions for user
                      'grocy' while quiescing (1=yes, 0=no).
                      Default: ${OFFLINE_KILL_GROCY_SESSIONS}

Examples:
  $0 preview
  $0 apply
  $0 apply-offline
  $0 apply-resume 20260225153045
  PRESERVE_UPPER_WORDS_CSV="aa,aaa,c,d" $0 preview
  SMALL_WORDS_CSV="a,an,and,as,at,by,for,in,of,on,the,to,with" $0 preview
  $0 rollback 20260225153045
EOF
}

if [[ -z "${MARIADB_ROOT_PASSWORD:-}" || -z "${MARIADB_DATABASE:-}" ]]; then
  echo "MARIADB_ROOT_PASSWORD and MARIADB_DATABASE must be set in ${STACK_DIR}/.env" >&2
  exit 1
fi

run_sql() {
  local sql="$1"
  printf '%s\n' "${sql}" | docker compose -f "${STACK_DIR}/docker-compose.yml" --env-file "${STACK_DIR}/.env" \
    exec -T mariadb \
    mariadb -uroot "-p${MARIADB_ROOT_PASSWORD}" "${MARIADB_DATABASE}"
}

run_sql_no_headers() {
  local sql="$1"
  printf '%s\n' "${sql}" | docker compose -f "${STACK_DIR}/docker-compose.yml" --env-file "${STACK_DIR}/.env" \
    exec -T mariadb \
    mariadb -N -s -uroot "-p${MARIADB_ROOT_PASSWORD}" "${MARIADB_DATABASE}"
}

stop_grocy_service() {
  local force="${1:-0}"
  if [[ "${PAUSE_GROCY_ON_APPLY}" != "1" && "${force}" != "1" ]]; then
    return
  fi
  log_status "Stopping grocy service to reduce DB lock contention..."
  docker compose -f "${STACK_DIR}/docker-compose.yml" --env-file "${STACK_DIR}/.env" stop grocy >/dev/null
}

start_grocy_service() {
  local force="${1:-0}"
  if [[ "${PAUSE_GROCY_ON_APPLY}" != "1" && "${force}" != "1" ]]; then
    return
  fi
  log_status "Starting grocy service after apply..."
  docker compose -f "${STACK_DIR}/docker-compose.yml" --env-file "${STACK_DIR}/.env" start grocy >/dev/null
}

get_active_grocy_trx_count() {
  run_sql_no_headers "SELECT COUNT(*)
FROM information_schema.innodb_trx t
JOIN information_schema.PROCESSLIST p ON p.ID = t.trx_mysql_thread_id
WHERE p.USER = 'grocy';"
}

get_active_grocy_thread_ids() {
  run_sql_no_headers "SELECT GROUP_CONCAT(DISTINCT t.trx_mysql_thread_id ORDER BY t.trx_mysql_thread_id SEPARATOR ',')
FROM information_schema.innodb_trx t
JOIN information_schema.PROCESSLIST p ON p.ID = t.trx_mysql_thread_id
WHERE p.USER = 'grocy';"
}

kill_grocy_db_threads() {
  local ids_csv
  local id

  ids_csv="$(get_active_grocy_thread_ids)"
  if [[ -z "${ids_csv}" || "${ids_csv}" == "NULL" ]]; then
    return
  fi

  log_status "Killing lingering grocy DB thread(s): ${ids_csv}"
  IFS=',' read -r -a ids <<< "${ids_csv}"
  for id in "${ids[@]}"; do
    [[ -z "${id}" ]] && continue
    run_sql "KILL ${id};" || true
  done
}

quiesce_grocy_db_writes() {
  local elapsed=0
  local count

  if ! [[ "${OFFLINE_QUIESCE_TIMEOUT}" =~ ^[0-9]+$ ]]; then
    echo "OFFLINE_QUIESCE_TIMEOUT must be a non-negative integer. Current value: ${OFFLINE_QUIESCE_TIMEOUT}" >&2
    return 1
  fi

  if [[ "${OFFLINE_KILL_GROCY_SESSIONS}" != "0" && "${OFFLINE_KILL_GROCY_SESSIONS}" != "1" ]]; then
    echo "OFFLINE_KILL_GROCY_SESSIONS must be 0 or 1. Current value: ${OFFLINE_KILL_GROCY_SESSIONS}" >&2
    return 1
  fi

  log_status "Waiting for grocy DB transactions to quiesce (timeout=${OFFLINE_QUIESCE_TIMEOUT}s)..."

  while true; do
    count="$(get_active_grocy_trx_count)"
    if [[ "${count}" == "0" ]]; then
      log_status "No active grocy DB transactions detected."
      return 0
    fi

    if (( elapsed >= OFFLINE_QUIESCE_TIMEOUT )); then
      log_status "Timed out waiting for grocy DB transactions to finish (active=${count})."
      return 1
    fi

    log_status "Active grocy DB transactions: ${count}"
    if [[ "${OFFLINE_KILL_GROCY_SESSIONS}" == "1" ]]; then
      kill_grocy_db_threads
    fi

    sleep 2
    elapsed=$((elapsed + 2))
  done
}

log_status() {
  local message="$1"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${message}"
}

create_function_sql() {
  cat <<SQL
DROP FUNCTION IF EXISTS proper_word;
DROP FUNCTION IF EXISTS title_case;

DELIMITER //

CREATE FUNCTION proper_word(w TEXT)
RETURNS TEXT
DETERMINISTIC
BEGIN
  DECLARE i INT DEFAULT 1;
  DECLARE c VARCHAR(1);
  DECLARE out_w TEXT DEFAULT '';
  DECLARE cap_next BOOLEAN DEFAULT TRUE;
  DECLARE lw TEXT;

  SET lw = LOWER(w);

  WHILE i <= CHAR_LENGTH(lw) DO
    SET c = SUBSTRING(lw, i, 1);

    IF cap_next AND c REGEXP '[a-z]' THEN
      SET out_w = CONCAT(out_w, UPPER(c));
      SET cap_next = FALSE;
    ELSE
      SET out_w = CONCAT(out_w, c);
      IF c IN ('-', '/', '+') THEN
        SET cap_next = TRUE;
      ELSE
        SET cap_next = FALSE;
      END IF;
    END IF;

    SET i = i + 1;
  END WHILE;

  RETURN out_w;
END//

CREATE FUNCTION title_case(s TEXT)
RETURNS TEXT
DETERMINISTIC
BEGIN
  DECLARE i INT DEFAULT 1;
  DECLARE c VARCHAR(1);
  DECLARE word TEXT DEFAULT '';
  DECLARE out_s TEXT DEFAULT '';
  DECLARE word_index INT DEFAULT 0;
  DECLARE lw TEXT;

  SET lw = LOWER(s);

  WHILE i <= CHAR_LENGTH(lw) DO
    SET c = SUBSTRING(lw, i, 1);

    IF c = '-' OR c REGEXP '[[:alnum:]#''/+]' THEN
      SET word = CONCAT(word, c);
    ELSE
      IF word <> '' THEN
        SET word_index = word_index + 1;
        IF word_index > 1 AND word IN (${SMALL_WORDS_SQL_LIST}) THEN
          SET out_s = CONCAT(out_s, word);
        ELSEIF word IN (${PRESERVE_UPPER_WORDS_SQL_LIST}) THEN
          SET out_s = CONCAT(out_s, UPPER(word));
        ELSE
          SET out_s = CONCAT(out_s, proper_word(word));
        END IF;
        SET word = '';
      END IF;
      SET out_s = CONCAT(out_s, c);
    END IF;

    SET i = i + 1;
  END WHILE;

  IF word <> '' THEN
    SET word_index = word_index + 1;
    IF word_index > 1 AND word IN (${SMALL_WORDS_SQL_LIST}) THEN
      SET out_s = CONCAT(out_s, word);
    ELSEIF word IN (${PRESERVE_UPPER_WORDS_SQL_LIST}) THEN
      SET out_s = CONCAT(out_s, UPPER(word));
    ELSE
      SET out_s = CONCAT(out_s, proper_word(word));
    END IF;
  END IF;

  RETURN out_s;
END//

DELIMITER ;
SQL
}

ensure_functions_ready() {
  local proper_word_exists
  local title_case_exists

  if [[ "${REFRESH_FUNCTIONS}" == "1" ]]; then
    log_status "Refreshing helper functions (REFRESH_FUNCTIONS=1)..."
    run_sql "$(create_function_sql)"
    return
  fi

  proper_word_exists="$(run_sql_no_headers "SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = '${MARIADB_DATABASE}' AND ROUTINE_TYPE = 'FUNCTION' AND ROUTINE_NAME = 'proper_word';")"
  title_case_exists="$(run_sql_no_headers "SELECT COUNT(*) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = '${MARIADB_DATABASE}' AND ROUTINE_TYPE = 'FUNCTION' AND ROUTINE_NAME = 'title_case';")"

  if [[ "${proper_word_exists}" == "1" && "${title_case_exists}" == "1" ]]; then
    log_status "Using existing helper functions (set REFRESH_FUNCTIONS=1 to recreate)."
  else
    log_status "Helper functions missing; creating them now..."
    run_sql "$(create_function_sql)"
  fi
}

create_backup_table_sql='CREATE TABLE IF NOT EXISTS products_name_backup (
  run_id VARCHAR(32) NOT NULL,
  product_id INT NOT NULL,
  old_name TEXT NOT NULL,
  backup_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (run_id, product_id)
);'

preview_sql='SELECT id, name, title_case(name) AS new_name
FROM products
WHERE name <> title_case(name)
ORDER BY id;'

count_remaining_sql='SELECT COUNT(*) AS remaining_to_update
FROM products
WHERE name <> title_case(name);'

run_sql_with_lock_retries() {
  local sql="$1"
  local label="$2"
  local attempt=1
  local tmp_output
  local output

  while (( attempt <= LOCK_RETRY_COUNT )); do
    tmp_output="$(mktemp)"

    if run_sql "${sql}" >"${tmp_output}" 2>&1; then
      output="$(cat "${tmp_output}")"
      rm -f "${tmp_output}"
      printf '%s\n' "${output}"
      return 0
    fi

    output="$(cat "${tmp_output}")"
    rm -f "${tmp_output}"

    if (( attempt < LOCK_RETRY_COUNT )); then
      log_status "${label} failed (attempt ${attempt}/${LOCK_RETRY_COUNT}); retrying in ${LOCK_RETRY_DELAY}s..."
      log_status "${label} last error: $(printf '%s\n' "${output}" | tail -n 1)"
      sleep "${LOCK_RETRY_DELAY}"
      ((attempt++))
      continue
    fi

    echo "${output}" >&2
    return 1
  done
}

apply_changes() {
  local requested_run_id="${1:-}"
  local run_id
  local rows_backed_up="0"
  local rows_updated="0"
  local remaining_to_update
  local initial_remaining
  local remaining_before
  local remaining_after
  local collision_rows="0"
  local progress_done
  local progress_pct
  local backup_sql
  local update_sql
  local backup_output=""
  local update_output=""
  local batch_rows_backed_up="0"
  local batch_rows_updated="0"
  local batch_num=0
  local batch_ids_csv=""
  local apply_failed=0

  if [[ -n "${requested_run_id}" ]]; then
    run_id="${requested_run_id}"
  else
    run_id="$(date +%Y%m%d%H%M%S)"
  fi

  if ! [[ "${BATCH_SIZE}" =~ ^[1-9][0-9]*$ ]]; then
    echo "BATCH_SIZE must be a positive integer. Current value: ${BATCH_SIZE}" >&2
    return 1
  fi

  if ! [[ "${MAX_BATCHES}" =~ ^[0-9]+$ ]]; then
    echo "MAX_BATCHES must be 0 or a positive integer. Current value: ${MAX_BATCHES}" >&2
    return 1
  fi

  initial_remaining="$(run_sql_no_headers "SELECT COUNT(*) FROM products WHERE name <> title_case(name);")"

  log_status "Applying title case updates with backup snapshot..."
  if [[ -n "${requested_run_id}" ]]; then
    log_status "Resume mode: continuing run_id=${run_id}."
  fi
  log_status "Batch size: ${BATCH_SIZE}"
  if [[ "${MAX_BATCHES}" != "0" ]]; then
    log_status "Batch limit for this run: ${MAX_BATCHES}"
  fi
  log_status "Rows needing update at start: ${initial_remaining}"
  log_status "Step 1/4: Generating run_id..."
  echo "run_id"
  echo "${run_id}"

  log_status "Step 2/4: Processing batches (backup + update)..."
  while true; do
    if [[ "${MAX_BATCHES}" != "0" && ${batch_num} -ge ${MAX_BATCHES} ]]; then
      log_status "Reached MAX_BATCHES=${MAX_BATCHES}; stopping by request."
      break
    fi

    remaining_before="$(run_sql_no_headers "SELECT COUNT(*) FROM products WHERE name <> title_case(name);")"
    if [[ "${remaining_before}" == "0" ]]; then
      break
    fi

    batch_num=$((batch_num + 1))
    batch_ids_csv="$(run_sql_no_headers "SELECT GROUP_CONCAT(id ORDER BY id SEPARATOR ',') FROM (
SELECT p.id
FROM products p
WHERE p.name <> title_case(p.name)
  AND NOT EXISTS (
    SELECT 1
    FROM products p2
    WHERE p2.id <> p.id
      AND p2.name = title_case(p.name)
  )
ORDER BY p.id
LIMIT ${BATCH_SIZE}
) AS batch_ids;")"

    if [[ -z "${batch_ids_csv}" || "${batch_ids_csv}" == "NULL" ]]; then
      log_status "No eligible rows left for safe update in this pass."
      break
    fi

    log_status "Batch ${batch_num}: preparing backup for up to ${BATCH_SIZE} rows (remaining before batch: ${remaining_before})..."

    backup_sql="SET SESSION innodb_lock_wait_timeout = ${LOCK_WAIT_TIMEOUT};
INSERT INTO products_name_backup (run_id, product_id, old_name)
SELECT '${run_id}', p.id, p.name
FROM products p
LEFT JOIN products_name_backup b
  ON b.run_id = '${run_id}' AND b.product_id = p.id
WHERE FIND_IN_SET(p.id, '${batch_ids_csv}')
  AND b.product_id IS NULL;
SELECT ROW_COUNT() AS rows_backed_up_batch;"

    if backup_output="$(run_sql_with_lock_retries "${backup_sql}" "Backup insert (batch ${batch_num})")"; then
      batch_rows_backed_up="$(printf '%s\n' "${backup_output}" | tail -n 1 | tr -d '\r')"
    else
      apply_failed=1
      batch_rows_backed_up="0"
    fi

    log_status "Batch ${batch_num}: applying title-case update..."
    update_sql="SET SESSION innodb_lock_wait_timeout = ${LOCK_WAIT_TIMEOUT};
START TRANSACTION;
UPDATE products
SET name = title_case(name)
WHERE FIND_IN_SET(id, '${batch_ids_csv}')
  AND name <> title_case(name);
SELECT ROW_COUNT() AS rows_updated_batch;
COMMIT;"

    if update_output="$(run_sql_with_lock_retries "${update_sql}" "Products update (batch ${batch_num})")"; then
      batch_rows_updated="$(printf '%s\n' "${update_output}" | tail -n 1 | tr -d '\r')"
    else
      apply_failed=1
      batch_rows_updated="0"
    fi

    rows_backed_up=$((rows_backed_up + batch_rows_backed_up))
    rows_updated=$((rows_updated + batch_rows_updated))
    remaining_after="$(run_sql_no_headers "SELECT COUNT(*) FROM products WHERE name <> title_case(name);")"
    progress_done=$((initial_remaining - remaining_after))
    if (( initial_remaining > 0 )); then
      progress_pct=$((progress_done * 100 / initial_remaining))
    else
      progress_pct=100
    fi

    log_status "Batch ${batch_num} complete: backed_up=${batch_rows_backed_up}, updated=${batch_rows_updated}, remaining=${remaining_after}, progress=${progress_done}/${initial_remaining} (${progress_pct}%)."

    if [[ "${batch_rows_backed_up}" == "0" && "${batch_rows_updated}" == "0" && "${remaining_after}" != "0" ]]; then
      log_status "No progress in current batch; stopping to avoid endless retries under lock contention."
      apply_failed=1
      break
    fi
  done

  log_status "Step 3/4: Batch processing finished."
  log_status "Step 4/4: Reporting rows backed up, updated, and remaining..."

  remaining_to_update="$(run_sql_no_headers "SELECT COUNT(*) FROM products WHERE name <> title_case(name);")"
  collision_rows="$(run_sql_no_headers "SELECT COUNT(*)
FROM products p
WHERE p.name <> title_case(p.name)
  AND EXISTS (
    SELECT 1
    FROM products p2
    WHERE p2.id <> p.id
      AND p2.name = title_case(p.name)
  );")"

  echo "rows_backed_up"
  echo "${rows_backed_up}"
  echo "rows_updated"
  echo "${rows_updated}"
  echo "remaining_to_update"
  echo "${remaining_to_update}"
  echo "collision_rows"
  echo "${collision_rows}"

  if [[ "${remaining_to_update}" != "0" ]]; then
    if [[ "${collision_rows}" != "0" ]]; then
      log_status "Apply finished with ${collision_rows} collision row(s) that would violate unique name constraints; these were skipped."
    fi
    log_status "Apply finished with remaining rows due to contention or collisions. You can rerun apply safely."
    log_status "If lock timeouts persist, temporarily stop app writes: docker compose stop grocy; run apply; then docker compose start grocy."
  else
    log_status "Apply complete. Save the reported run_id for rollback."
  fi

  if (( apply_failed == 1 )); then
    log_status "Apply encountered errors during backup/update."
    return 1
  fi

  return 0
}

apply_changes_offline() {
  local requested_run_id="${1:-}"
  local apply_rc=0

  log_status "Offline mode enabled: grocy service will be stopped before apply and restarted afterwards."
  stop_grocy_service 1

  if ! quiesce_grocy_db_writes; then
    log_status "Offline quiesce failed; aborting apply to avoid lock storms."
    start_grocy_service 1
    return 1
  fi

  if apply_changes "${requested_run_id}"; then
    apply_rc=0
  else
    apply_rc=$?
    log_status "Apply failed while offline mode was active."
  fi

  start_grocy_service 1
  return ${apply_rc}
}

rollback_sql() {
  local run_id="$1"
  cat <<SQL
START TRANSACTION;
UPDATE products p
JOIN products_name_backup b
  ON b.product_id = p.id
SET p.name = b.old_name
WHERE b.run_id = '${run_id}';
COMMIT;

SELECT '${run_id}' AS rolled_back_run_id, ROW_COUNT() AS rows_restored;
SQL
}

if [[ "${MODE}" == "help" || "${MODE}" == "-h" || "${MODE}" == "--help" ]]; then
  print_usage
  exit 0
fi

log_status "Preparing helper function/table..."
ensure_functions_ready
run_sql "${create_backup_table_sql}"

case "${MODE}" in
  preview)
    log_status "Previewing proposed casing changes..."
    run_sql "${preview_sql}"
    ;;
  apply)
    if [[ "${PAUSE_GROCY_ON_APPLY}" == "1" ]]; then
      apply_changes_offline
    else
      apply_changes
    fi
    ;;
  apply-offline)
    # Enable maintenance mode (show maintenance page)
    "${STACK_DIR}/maintenance/maintenance_mode.sh" on || true
    apply_changes_offline
    # Disable maintenance mode (restore normal access)
    "${STACK_DIR}/maintenance/maintenance_mode.sh" off || true
    ;;
  apply-resume)
    if [[ -z "${RUN_ID}" ]]; then
      echo "Usage: $0 apply-resume <run_id>" >&2
      exit 1
    fi
    if [[ "${PAUSE_GROCY_ON_APPLY}" == "1" ]]; then
      apply_changes_offline "${RUN_ID}"
    else
      apply_changes "${RUN_ID}"
    fi
    ;;
  rollback)
    if [[ -z "${RUN_ID}" ]]; then
      print_usage >&2
      exit 1
    fi
    log_status "Rolling back run_id=${RUN_ID} ..."
    run_sql "$(rollback_sql "${RUN_ID}")"
    ;;
  *)
    print_usage >&2
    exit 1
    ;;
esac

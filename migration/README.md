# Grocy SQLite -> MariaDB Migration

This folder contains a repeatable, logged migration workflow to move a Grocy
SQLite database into MariaDB, including schema, data, views, triggers, and
validation checks.

## Requirements
- Docker and Docker Compose
- `sqlite3` available on the host
- A Grocy SQLite backup at `migration/data/grocy.db`

## Configuration
Migration scripts load `../.env` by default. Ensure at least:
- `MARIADB_ROOT_PASSWORD`
- `MARIADB_DATABASE` (default: `grocy_db`)

## One-command run (recommended)
```bash
chmod +x migration/run_migration.sh
migration/run_migration.sh --all
```

This automatically runs:
1. Export tables from SQLite (`grocy.db`)
2. Apply schema (tables) to MariaDB
3. Import data with verification
4. Apply views and triggers
5. Full validation

Dry run (prints commands only):
```bash
migration/run_migration.sh --all --dry-run
```

Full reset with re-export:
```bash
migration/run_migration.sh --export --reset-db --all
```

## Individual steps
```bash
chmod +x migration/*.sh

# Export tables from SQLite to SQL files
migration/export_tables_from_sqlite.sh

# Reset database (optional)
docker compose exec -T mariadb sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" mysql -uroot -e "DROP DATABASE IF EXISTS $MARIADB_DATABASE; CREATE DATABASE $MARIADB_DATABASE CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;"'

# Apply tables (MariaDB-safe DDL)
migration/apply_tables_with_logs.sh

# Import data (logged, triggers auto-disabled to prevent 1442 errors)
migration/import_with_logs.sh
  # Automatically checks for empty tables after import
  # Reports any tables with 0 rows for manual intervention

# Apply views (ordered dependencies)
migration/apply_views_with_logs.sh

# Apply triggers (recreates all triggers after import)
migration/apply_triggers_with_logs.sh

# Validate row counts and DDL completeness
migration/validate_migration.sh
```

## Logs and reports
- Run summary logs: `migration/data/run_logs/`
- Export logs: `migration/data/exports/`
- Apply logs: `migration/data/apply_logs/`
- Import logs: `migration/data/import_logs/`
- Validation logs/reports: `migration/data/validation/`

The orchestrator prints a summary at the end of each run:
`SUCCESS`, `PARTIAL`, or `DRY-RUN`, with per-step statuses.

**Import verification:** After importing data, the script automatically checks
for any tables with 0 rows and reports them as a warning. If any tables are
empty after import, check the import error log for 1442 errors or other issues.

## DDL and Data Sources
- `migration/data/grocy.db`: SQLite source database (required for export).
- `migration/data/exports/`: Generated SQL exports from SQLite (created by `export_tables_from_sqlite.sh`).
  - Cleared and re-generated on each `--export` run.
- `migration/data/table_list.txt`: List of tables to migrate (defines export/import scope).
- `migration/ddl/create_tables_test.sql`: MariaDB-ready table DDL used by the scripts.
- `migration/ddl/views/`: MariaDB-ready view definitions (including helper views).
- `migration/ddl/triggers/`: MariaDB-safe triggers (BEFORE triggers where needed).

## Troubleshooting

### Export fails or incomplete
- Verify `migration/data/grocy.db` exists and is readable
- Check `migration/data/exports/export_*.log` for sqlite3 errors
- Ensure `table_list.txt` contains all table names from your SQLite database

### Tables imported as empty (0 rows)
- The import script automatically checks for empty tables and reports them as warnings
- If tables have data in SQLite but import as 0 rows, check `migration/data/import_logs/import_*.err.log`
- Most likely cause: **Error 1442** (trigger self-reference during bulk insert)
  - Solution: Edit `import_with_logs.sh` to disable additional triggers before import if needed
  - See lines ~48-52 for the trigger disable pattern
- Alternative: Manually reimport the problematic table after disabling its triggers

### View creation errors
- Check `migration/data/apply_logs/apply_views_*.err.log`
- Most issues are dependency order (resolved in the ordered view list)
- If a view references a missing table or another view, verify both dependencies imported successfully

### Validation reports mismatches
- Inspect `migration/data/validation/row_count_mismatches.tsv`
- Compares SQLite row counts vs. MariaDB post-import counts
- If counts don't match, check import logs for errors on that specific table
- Use `--snapshot` flag to save current view/trigger state: `migration/validate_migration.sh --snapshot`

## Notes
- **Automated export:** The `--export` option regenerates all SQL exports from SQLite, clearing old files before export.
- **Trigger handling:** The import script automatically disables problematic triggers before bulk insert (to avoid Error 1442), then recreates them after import completes.
- **Post-import checks:** The orchestrator automatically verifies all tables have data after import and reports any empty tables as warnings.
- **Empty table handling:** Empty tables in SQLite are skipped during export and reported as "Skipping empty table" (placeholder files created).
- **Repeatable workflow:** All steps are logged and can be re-run independently or combined via the orchestrator.

## Admin checklist (post-run)

### Before committing to git
Suggested `.gitignore` entries:
```gitignore
# Migration data exports (auto-generated, contains sensitive data)
migration/data/exports/*.sql

# Migration logs (for local debugging only)
migration/data/apply_logs/
migration/data/import_logs/
migration/data/run_logs/
migration/data/validation/
```

### Post-import verification
After running the migration:
1. Check the orchestrator summary for any `WARNING` on `import_verification`
2. If tables show as empty, consult Troubleshooting > "Tables imported as empty"
3. Run `migration/validate_migration.sh` to get a full row count report
4. Test Grocy UI: verify all products, inventory, etc. display correctly

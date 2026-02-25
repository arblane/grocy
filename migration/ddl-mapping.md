# SQLite → MariaDB (MariaDB/MySQL) DDL Mapping Notes

This document explains the transformation rules used by `transform_tables.py`.

Type & token mappings (examples)
- `AUTOINCREMENT` → `AUTO_INCREMENT`
- `INTEGER PRIMARY KEY` (SQLite rowid PK pattern) → `INT AUTO_INCREMENT PRIMARY KEY` (manual review recommended)
- `BOOLEAN` → `TINYINT(1)`
- `BLOB` → `LONGBLOB`
- `IFNULL(x,y)` → `COALESCE(x,y)` (used in expressions)

Engine & charset
- Append `ENGINE=InnoDB DEFAULT CHARSET=utf8mb4` to every `CREATE TABLE` unless already present.

Constraints & indexes
- SQLite allows some implicit behaviors (rowid, omitted types). Convert explicit `FOREIGN KEY` clauses to MySQL syntax and ensure `InnoDB` engine.
- Unique/index differences: prefer creating explicit `CREATE INDEX` statements when appropriate.

Functions & expressions
- `STRFTIME` and datetime functions: MariaDB uses `DATE_FORMAT`, `STR_TO_DATE`, or `DATE` functions — complex expressions should be reviewed manually.
- `TYPEOF()` is SQLite-specific; manual refactor required if present.

STRFTIME mapping notes
- The automated transform will attempt a best-effort rewrite: `STRFTIME('%Y-%m-%d', mydate)` -> `DATE_FORMAT(mydate, '%Y-%m-%d')`.
- This swap preserves common format tokens but complex uses (nested functions, literals, or multiple arguments) must be reviewed.

CHECK constraints
- MySQL/MariaDB historically treated `CHECK` as parsed but not enforced until recent versions; transforms will tag CHECKs with a review comment. Decide whether to keep CHECKs, convert to triggers, or map to application logic.

Index notes
- `CREATE INDEX` statements in SQLite are largely compatible with MariaDB, but watch for:
	- Partial indexes using `WHERE` — MariaDB does not support partial indexes; convert logic to a generated column + index or application logic.
	- Expression-based indexes (e.g., `lower(name)`) — MariaDB requires generated columns to index expressions.
	- `IF NOT EXISTS` on index creation is removed by the transform; dedupe is recommended.


- Views and CTEs: MariaDB supports CTEs (recent versions); manually validate recursive CTEs and performance.

Notes / Caveats
- This mapping is intentionally conservative: the automated transform makes textual replacements and enforces engine/charset; manual review is required for complex expressions, CHECK constraints, and ANY use of PRAGMA or SQLite-specific pragmas.
- Always run validation steps (row counts, checksums) after data import.

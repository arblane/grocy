#!/usr/bin/env python3
"""Convert SQLite datetime('now','localtime') defaults to MariaDB equivalents.
Creates .bak copies before modifying files.

Rules (conservative):
- DATETIME DEFAULT (datetime('now','localtime')) -> DATETIME DEFAULT CURRENT_TIMESTAMP
- DATETIME columns named '*updated*' -> add ON UPDATE CURRENT_TIMESTAMP
- DATE DEFAULT (datetime(...)) -> DATE DEFAULT CURRENT_DATE
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    ROOT / 'sql' / 'create_tables.sql',
    ROOT / 'migration' / 'ddl' / 'create_tables_test.sql',
]

dt_expr = r"\(\s*datetime\('\s*now\s*'\s*,\s*'localtime'\s*\)\s*\)"

re_datetime_col = re.compile(rf"(?P<col>\b[A-Za-z0-9_]+)\s+DATETIME\s+DEFAULT\s*{dt_expr}", re.IGNORECASE)
re_date_col = re.compile(rf"(?P<col>\b[A-Za-z0-9_]+)\s+DATE\s+DEFAULT\s*{dt_expr}", re.IGNORECASE)

modified = []

for p in FILES:
    if not p.exists():
        continue
    txt = p.read_text(encoding='utf-8')
    new = txt

    def dt_repl(m):
        col = m.group('col')
        if 'updated' in col.lower():
            return f"{col} DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP"
        return f"{col} DATETIME DEFAULT CURRENT_TIMESTAMP"

    new = re_datetime_col.sub(dt_repl, new)
    new = re_date_col.sub(lambda m: f"{m.group('col')} DATE DEFAULT CURRENT_DATE", new)

    if new != txt:
        bak = p.with_suffix(p.suffix + '.bak')
        if not bak.exists():
            bak.write_text(txt, encoding='utf-8')
        p.write_text(new, encoding='utf-8')
        modified.append(p.relative_to(ROOT))

if modified:
    print('Modified files:')
    for m in modified:
        print('-', m)
else:
    print('No changes applied')

#!/usr/bin/env python3
"""Remove CHECK constraints from table DDL (MariaDB compatibility).

Creates .bak backups before modifying files.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    ROOT / 'sql' / 'create_tables.sql',
    ROOT / 'migration' / 'ddl' / 'create_tables_test.sql',
]

# Remove standalone CHECK(...) clauses; assumes no nested parentheses
CHECK_RE = re.compile(r'\s+CHECK\s*\([^)]*\)', re.IGNORECASE)

def convert_file(path: Path) -> bool:
    text = path.read_text(encoding='utf-8')
    new = CHECK_RE.sub('', text)
    if new != text:
        bak = path.with_suffix(path.suffix + '.bak')
        if not bak.exists():
            bak.write_text(text, encoding='utf-8')
        path.write_text(new, encoding='utf-8')
        return True
    return False

modified = []
for f in FILES:
    if f.exists() and convert_file(f):
        modified.append(f.relative_to(ROOT))

if modified:
    print('Modified files:')
    for m in modified:
        print('-', m)
else:
    print('No changes applied')

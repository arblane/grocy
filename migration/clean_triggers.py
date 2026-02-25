#!/usr/bin/env python3
"""Normalize trigger SQL for MariaDB.

Fixes:
- INSERT OR REPLACE -> REPLACE
- DATETIME('now','localtime') -> NOW()
- NOTNULL / ISNULL -> IS NOT NULL / IS NULL
- CAST(... AS TEXT) -> CAST(... AS CHAR)
- Concatenation with || -> CONCAT(...)
- Quote reserved column name `type`

Creates .bak backups before modifying files.
"""
from pathlib import Path
import re
import glob

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    ROOT / 'migration' / 'ddl' / 'create_triggers_test.sql',
    ROOT / 'sql' / 'create_triggers.sql',
]
FILES += [Path(p) for p in glob.glob(str(ROOT / 'migration' / 'ddl' / 'triggers' / '*.sql'))]

re_insert_or_replace = re.compile(r'\bINSERT\s+OR\s+REPLACE\b', re.IGNORECASE)
re_datetime_now = re.compile(r"DATETIME\('\s*now\s*'\s*,\s*'localtime'\s*\)", re.IGNORECASE)
re_notnull = re.compile(r'\bNOTNULL\b', re.IGNORECASE)
re_isnull = re.compile(r'\bISNULL\b', re.IGNORECASE)
re_cast_text = re.compile(r'CAST\(([^)]+)\s+AS\s+TEXT\)', re.IGNORECASE)


def replace_concat(text: str) -> str:
    # Replace simple a || b || c chains with CONCAT(a, b, c)
    # This is conservative and only targets lines with '||'.
    def repl_line(line: str) -> str:
        if '||' not in line:
            return line
        parts = [p.strip() for p in line.split('||')]
        if len(parts) < 2:
            return line
        return 'CONCAT(' + ', '.join(parts) + ')'

    return '\n'.join(repl_line(line) for line in text.splitlines()) + ('\n' if text.endswith('\n') else '')


def quote_type(text: str) -> str:
    # Replace bare column name type with `type` (not inside quotes)
    # Covers common patterns like " type =", "AND type", "(type", ", type", "type,"
    pattern = re.compile(r'(?<![`\w])type(?![`\w])')
    return pattern.sub('`type`', text)


def convert(text: str) -> str:
    out = text
    out = re_insert_or_replace.sub('REPLACE', out)
    out = re_datetime_now.sub('NOW()', out)
    out = re_notnull.sub('IS NOT NULL', out)
    out = re_isnull.sub('IS NULL', out)
    out = re_cast_text.sub(r'CAST(\1 AS CHAR)', out)
    out = replace_concat(out)
    out = quote_type(out)
    return out


modified = []
for path in FILES:
    if not path.exists():
        continue
    text = path.read_text(encoding='utf-8')
    new = convert(text)
    if new != text:
        bak = path.with_suffix(path.suffix + '.bak')
        if not bak.exists():
            bak.write_text(text, encoding='utf-8')
        path.write_text(new, encoding='utf-8')
        modified.append(path.relative_to(ROOT))

if modified:
    print('Modified files:')
    for m in modified:
        print('-', m)
else:
    print('No changes applied')

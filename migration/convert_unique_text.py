#!/usr/bin/env python3
"""Convert TEXT columns that are used in UNIQUE constraints to VARCHAR(255).

Targets:
- inline UNIQUE column definitions (e.g., name TEXT NOT NULL UNIQUE)
- table-level UNIQUE constraints (e.g., UNIQUE(user_id, `key`))

Creates .bak backups before modifying files.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    ROOT / 'sql' / 'create_tables.sql',
    ROOT / 'migration' / 'ddl' / 'create_tables_test.sql',
]

create_re = re.compile(r'^\s*CREATE\s+TABLE\b', re.IGNORECASE)
unique_inline_re = re.compile(r'\bUNIQUE\b', re.IGNORECASE)
unique_table_re = re.compile(r'\bUNIQUE\s*\(([^)]+)\)', re.IGNORECASE)
column_re = re.compile(r'^\s*`?([A-Za-z0-9_]+)`?\s+(\w+)', re.IGNORECASE)


def parse_unique_cols(lines):
    unique_cols = set()
    for line in lines:
        m = unique_table_re.search(line)
        if not m:
            continue
        cols = m.group(1)
        for part in cols.split(','):
            col = part.strip().strip('`')
            if col:
                unique_cols.add(col)
    return unique_cols


def rewrite_block(lines):
    # Map column name -> (index, type)
    col_types = {}
    for idx, line in enumerate(lines):
        m = column_re.match(line)
        if not m:
            continue
        col_name = m.group(1)
        col_type = m.group(2)
        col_types[col_name] = (idx, col_type)

    unique_cols = parse_unique_cols(lines)

    # Inline UNIQUE columns
    for col_name, (idx, col_type) in list(col_types.items()):
        if col_type.lower() != 'text':
            continue
        if unique_inline_re.search(lines[idx]):
            unique_cols.add(col_name)

    # Replace TEXT -> VARCHAR(255) for unique columns
    new_lines = list(lines)
    for col_name in unique_cols:
        if col_name not in col_types:
            continue
        idx, col_type = col_types[col_name]
        if col_type.lower() != 'text':
            continue
        new_lines[idx] = re.sub(r'\bTEXT\b', 'VARCHAR(255)', new_lines[idx], count=1, flags=re.IGNORECASE)
    return new_lines


def convert_file(path):
    text = path.read_text(encoding='utf-8')
    lines = text.splitlines(keepends=True)
    out = []
    buf = []
    in_table = False
    changed = False

    for line in lines:
        if create_re.match(line):
            in_table = True
            buf = [line]
            continue

        if in_table:
            buf.append(line)
            if line.strip().endswith(');') or line.strip() == ');':
                new_buf = rewrite_block(buf)
                if new_buf != buf:
                    changed = True
                out.extend(new_buf)
                in_table = False
                buf = []
            continue

        out.append(line)

    if in_table and buf:
        new_buf = rewrite_block(buf)
        if new_buf != buf:
            changed = True
        out.extend(new_buf)

    if changed:
        bak = path.with_suffix(path.suffix + '.bak')
        if not bak.exists():
            bak.write_text(text, encoding='utf-8')
        path.write_text(''.join(out), encoding='utf-8')
    return changed


modified = []
for f in FILES:
    if not f.exists():
        continue
    if convert_file(f):
        modified.append(f.relative_to(ROOT))

if modified:
    print('Modified files:')
    for m in modified:
        print('-', m)
else:
    print('No changes applied')

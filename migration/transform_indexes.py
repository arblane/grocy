#!/usr/bin/env python3
"""Transform SQLite CREATE INDEX blocks into MariaDB-compatible DDL.

Usage: python3 transform_indexes.py --src sql/create_indexes.sql --out migration/ddl

This script extracts `CREATE INDEX` / `CREATE UNIQUE INDEX` statements,
removes `IF NOT EXISTS`, flags partial or expression-based indexes, and
emits per-index files plus a combined `create_indexes.sql`.
"""
import re
import os
import argparse


def extract_index_blocks(sql_text):
    pattern = re.compile(r"(CREATE\s+(?:UNIQUE\s+)?INDEX\b.*?;)", re.I | re.S)
    return pattern.findall(sql_text)


def index_name_from_block(block):
    m = re.search(r"CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?[`\"]?([^\s`\"\(]+)[`\"]?",
                  block, re.I)
    return m.group(1) if m else None


def apply_mappings(block):
    s = block
    # Remove IF NOT EXISTS (MySQL INDEX does not support IF NOT EXISTS reliably)
    s = re.sub(r"IF\s+NOT\s+EXISTS\s+", "", s, flags=re.I)
    # Normalize whitespace
    s = re.sub(r"\s+", " ", s).strip()
    return s + "\n"


def analyze_index(block):
    flags = []
    # Detect partial indexes (WHERE ...)
    if re.search(r"\bWHERE\b", block, re.I):
        flags.append('Partial index (WHERE) — MariaDB does not support partial indexes')

    # Detect expression-based index: columns containing non-simple tokens
    m = re.search(r"ON\s+[^\s(]+\s*\(([^)]+)\)", block, re.I)
    if m:
        cols = m.group(1)
        parts = [c.strip() for c in cols.split(',')]
        for p in parts:
            # accept simple column names with optional ASC/DESC
            if not re.match(r"^[`\"]?\w+[`\"]?(?:\s+(?:ASC|DESC))?$", p, re.I):
                flags.append(f'Expression-based index on "{p}" — review/convert to generated column')
    return flags


def write_outputs(out_dir, items):
    os.makedirs(out_dir, exist_ok=True)
    per_dir = os.path.join(out_dir, "indexes")
    os.makedirs(per_dir, exist_ok=True)
    combined = []
    for name, ddl in items:
        fname = os.path.join(per_dir, f"{name}.sql")
        with open(fname, 'w', encoding='utf8') as f:
            f.write(ddl)
        combined.append(ddl.rstrip())

    combined_path = os.path.join(out_dir, 'create_indexes.sql')
    with open(combined_path, 'w', encoding='utf8') as f:
        f.write('\n\n'.join(combined) + '\n')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--src', default='sql/create_indexes.sql')
    p.add_argument('--out', default='migration/ddl')
    p.add_argument('--dry-run', action='store_true')
    args = p.parse_args()

    with open(args.src, 'r', encoding='utf8') as f:
        src = f.read()

    blocks = extract_index_blocks(src)
    items = []
    flagged = {}
    for b in blocks:
        name = index_name_from_block(b) or 'unknown_index'
        mapped = apply_mappings(b)
        items.append((name, mapped))
        flags = analyze_index(b)
        if flags:
            flagged[name] = flags

    if args.dry_run:
        print(f'Found {len(items)} index statements; sample: {items[:3]}')
        if flagged:
            print('\nFlagged indexes needing manual review:')
            for k, v in flagged.items():
                print(f'- {k}: {", ".join(v)}')
        return

    write_outputs(args.out, items)
    print(f'Wrote {len(items)} per-index files and combined create_indexes.sql to {args.out}')


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Transform SQLite CREATE TABLE blocks into MariaDB-compatible DDL.

Usage: python3 transform_tables.py --src sql/create_tables.sql --out migration/ddl

This is a simple, auditable scaffold: it extracts non-greedily each
CREATE TABLE (...) block, applies configurable text mappings and emits
per-table SQL files plus a combined `tables.sql`.
"""
import re
import os
import argparse
from collections import defaultdict


DEFAULT_MAPPING = [
    # basic token replacements (case-insensitive)
    (re.compile(r"\bAUTOINCREMENT\b", re.I), "AUTO_INCREMENT"),
    (re.compile(r"\bBOOLEAN\b", re.I), "TINYINT(1)"),
    (re.compile(r"\bIFNULL\(", re.I), "COALESCE("),
    (re.compile(r"\bBLOB\b", re.I), "LONGBLOB"),
    # Keep STRFTIME mapping handled in apply_mappings (needs expression-order swap)
]


def extract_table_blocks(sql_text):
    # Match CREATE TABLE ... ); non-greedy across lines
    pattern = re.compile(r"(CREATE\s+TABLE\b.*?\)\s*;)", re.I | re.S)
    return pattern.findall(sql_text)


def table_name_from_block(block):
    m = re.search(r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?[`\"]?([^\s`\"\(]+)[`\"]?",
                  block, re.I)
    return m.group(1) if m else None


def apply_mappings(block, mappings):
    s = block
    for pat, rep in mappings:
        s = pat.sub(rep, s)
    # Handle common SQLite INTEGER PRIMARY KEY rowid pattern -> INT AUTO_INCREMENT
    def _fix_int_pk(m):
        col = m.group('col')
        notnull = m.group('notnull') or ''
        # produce INT [NOT NULL] PRIMARY KEY AUTO_INCREMENT
        return f"{col} INT {notnull}PRIMARY KEY AUTO_INCREMENT"

    s = re.sub(r"(?P<col>[`\"]?\w+[`\"]?)\s+INTEGER\s+(?P<notnull>NOT\s+NULL\s+)?PRIMARY\s+KEY(?:\s+UNIQUE)?(?:\s+AUTO_INCREMENT)?",
               _fix_int_pk, s, flags=re.I)

    # Flag common ambiguous defaults (datetime('now', 'localtime')) by replacing with CURRENT_TIMESTAMP and adding a note in comments
    s = re.sub(r"DEFAULT\s*\(\s*datetime\('\s*now\s*'\s*,\s*'localtime'\s*\)\s*\)",
               "DEFAULT CURRENT_TIMESTAMP /* REVIEW: was datetime('now','localtime') */", s, flags=re.I)
    # Ensure InnoDB + utf8mb4
    if re.search(r"ENGINE\s*=", s, re.I) is None:
        s = re.sub(r"\)\s*;\s*$", ") ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;", s)
    # Replace TYPEOF usage with a review comment (manual rewrite likely needed)
    if re.search(r"TYPEOF\s*\(", s, re.I):
        s = re.sub(r"TYPEOF\s*\(", "/* REVIEW: TYPEOF( */ ", s, flags=re.I)

    # Mark CHECK constraints for manual review (MySQL may ignore or enforce differently)
    if re.search(r"\bCHECK\s*\(", s, re.I):
        s = re.sub(r"\bCHECK\s*\(", "/* REVIEW: CHECK */ CHECK(", s, flags=re.I)

    # Convert STRFTIME('fmt', expr) -> DATE_FORMAT(expr, 'fmt') when possible
    # This is a best-effort swap; complex expressions should be reviewed.
    s = re.sub(r"STRFTIME\s*\(\s*'([^']*)'\s*,\s*([^\)]+?)\s*\)",
               lambda m: f"DATE_FORMAT({m.group(2).strip()}, '{m.group(1)}')",
               s, flags=re.I)
    
    # Apply targeted CHECK conversions
    s = _convert_checks(s)
    return s

def _convert_checks(s):
    # 1) CHECK(col IN (0,1)) -> make col TINYINT(1) and remove/check comment
    def in_check_replace(match):
        col = match.group('col')
        vals = match.group('vals')
        vals_list = [v.strip().strip("'\"") for v in vals.split(',')]
        col_regex = re.compile(rf"([`\"]?{re.escape(col).strip('`\"')}[`\"]?\s+)([^,\n]+)", re.I)
        new_s = s
        if set(vals_list) <= {'0', '1'}:
            # set column type to TINYINT(1)
            new_s = col_regex.sub(lambda m: m.group(1) + re.sub(r"^\w+(?:\([^)]*\))?", "TINYINT(1)", m.group(2), flags=re.I), new_s, count=1)
            return '/* CHECK converted: ' + match.group(0) + ' */'
        # if small set of strings, consider ENUM
        clean_vals = [v for v in vals_list if re.match(r"^[A-Za-z0-9_ -]+$", v)]
        if len(clean_vals) == len(vals_list) and 1 < len(clean_vals) <= 10:
            enum = ",".join("'{}'".format(v.replace("'","''")) for v in clean_vals)
            new_s = col_regex.sub(lambda m: m.group(1) + 'ENUM(' + enum + ')', new_s, count=1)
            return '/* CHECK converted to ENUM: ' + match.group(0) + ' */'
        return '/* REVIEW: ' + match.group(0) + ' */'

    s = re.sub(r"CHECK\s*\(\s*(?P<col>[`\"]?\w+[`\"]?)\s+IN\s*\(\s*(?P<vals>[^)]+)\s*\)\s*\)",
               lambda m: in_check_replace(m), s, flags=re.I)

    # 2) LENGTH(col) <= N -> if column is TEXT, convert to VARCHAR(N)
    def length_check_replace(match):
        col = match.group('col')
        maxlen = int(match.group('len'))
        col_regex = re.compile(rf"([`\"]?{re.escape(col).strip('`\"')}[`\"]?\s+)([^,\n]+)", re.I)
        def repl(m):
            typ = m.group(2)
            if re.search(r"\bTEXT\b", typ, re.I):
                return m.group(1) + f"VARCHAR({maxlen})"
            return m.group(0)
        return col_regex.sub(repl, s, count=1) and '/* CHECK converted: LENGTH -> VARCHAR */'

    s = re.sub(r"CHECK\s*\(\s*LENGTH\(\s*(?P<col>[`\"]?\w+[`\"]?)\s*\)\s*<=\s*(?P<len>\d+)\s*\)",
               lambda m: length_check_replace(m), s, flags=re.I)

    # 3) col >= 0 -> add UNSIGNED to integer types
    def nonneg_replace(match):
        col = match.group('col')
        col_regex = re.compile(rf"([`\"]?{re.escape(col).strip('`\"')}[`\"]?\s+)([^,\n]+)", re.I)
        def repl(m):
            typ = m.group(2)
            if re.search(r"\bINT\b|\bINTEGER\b", typ, re.I) and 'UNSIGNED' not in typ.upper():
                return m.group(1) + typ + ' UNSIGNED'
            return m.group(0)
        return col_regex.sub(repl, s, count=1) and '/* CHECK converted: >=0 -> UNSIGNED */'

    s = re.sub(r"CHECK\s*\(\s*(?P<col>[`\"]?\w+[`\"]?)\s*>=\s*0\s*\)",
               lambda m: nonneg_replace(m), s, flags=re.I)

    return s
    return s


def analyze_block(block):
    flags = []
    if re.search(r"STRFTIME\s*\(", block, re.I):
        flags.append('STRFTIME usage (date formatting)')
    if re.search(r"TYPEOF\s*\(", block, re.I):
        flags.append('TYPEOF usage (SQLite-specific)')
    if re.search(r"PRAGMA\b", block, re.I):
        flags.append('PRAGMA present (SQLite-specific)')
    if re.search(r"\bCHECK\s*\(", block, re.I):
        flags.append('CHECK constraints (review semantics)')
    if re.search(r"RAISE\s*\(\s*ABORT", block, re.I):
        flags.append('RAISE(ABORT,...) in triggers/constraints -> map to SIGNAL')
    return flags


def write_outputs(out_dir, items):
    os.makedirs(out_dir, exist_ok=True)
    per_dir = os.path.join(out_dir, "tables")
    os.makedirs(per_dir, exist_ok=True)
    combined = []
    for name, ddl in items:
        # skip sqlite internal tables
        if name.lower().startswith('sqlite_'):
            continue
        fn = os.path.join(per_dir, f"{name}.sql")
        with open(fn, "w", encoding="utf8") as f:
            f.write(ddl.rstrip() + "\n")
        combined.append(ddl.rstrip())

    combined_path = os.path.join(out_dir, "tables.sql")
    with open(combined_path, "w", encoding="utf8") as f:
        f.write("\n\n".join(combined) + "\n")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--src", default="sql/create_tables.sql")
    p.add_argument("--out", default="migration/ddl")
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    with open(args.src, "r", encoding="utf8") as f:
        src = f.read()

    blocks = extract_table_blocks(src)
    items = []
    flagged = defaultdict(list)
    for b in blocks:
        name = table_name_from_block(b) or "unknown_table"
        transformed = apply_mappings(b, DEFAULT_MAPPING)
        items.append((name, transformed))
        flags = analyze_block(b)
        if flags:
            flagged[name].extend(flags)

    if args.dry_run:
        print(f"Found {len(items)} table blocks; sample: {items[:3]}")
        if flagged:
            print("\nFlagged tables needing manual review:")
            for tn, fl in flagged.items():
                print(f"- {tn}: {', '.join(fl)}")
        return

    write_outputs(args.out, items)
    print(f"Wrote {len(items)} per-table files and combined tables.sql to {args.out}")


if __name__ == '__main__':
    main()

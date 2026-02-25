#!/usr/bin/env python3
import re
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'sql' / 'create_views.sql'
OUT_DIR = ROOT / 'migration' / 'ddl' / 'views'
COMBINED = ROOT / 'migration' / 'ddl' / 'create_views.sql'


def read_src():
    return SRC.read_text(encoding='utf-8')


def sanitize_name(name: str) -> str:
    return re.sub(r"[^0-9A-Za-z_]+", '_', name)


def convert_concat(expr: str) -> str:
    # Simple iterative conversion of `a || b || c` -> CONCAT(a, b, c)
    # This will handle common cases; complex nested expressions should be reviewed.
    while '||' in expr:
        # find a simple left || right and replace with CONCAT(left, right)
        m = re.search(r"(?P<l>[^\s,()]+)\s*\|\|\s*(?P<r>[^\s,()]+)", expr)
        if not m:
            break
        l = m.group('l')
        r = m.group('r')
        expr = expr[:m.start()] + f"CONCAT({l}, {r})" + expr[m.end():]
    return expr


def basic_rewrites(body: str) -> (str, list):
    flags = []
    # IFNULL -> COALESCE
    if 'IFNULL(' in body.upper():
        body = re.sub(r"IFNULL\s*\(", 'COALESCE(', body, flags=re.I)
        flags.append('IFNULL -> COALESCE')

    # STRFTIME occurrences -> flag for manual review (do not auto-replace)
    if 'STRFTIME(' in body.upper():
        flags.append('STRFTIME() used — manual review')

    # TYPEOF occurrences -> mark for review
    if 'TYPEOF(' in body.upper():
        flags.append('TYPEOF() used — manual review')

    # Replace simple || concatenations
    if '||' in body:
        body = convert_concat(body)
        flags.append("'||' -> CONCAT() (best-effort)")

    # SQLite-specific 'CAST(... AS INTEGER)' is usually OK in MySQL

    return body, flags


def transform_block(block: str) -> (str, str, list):
    header_re = re.compile(r"CREATE\s+VIEW\s+(?P<name>[`\"\[]?\w+[`\"\]]?)\s+AS\s+(?P<body>.*);", re.I | re.S)
    m = header_re.search(block)
    if not m:
        # fallback
        simple = re.match(r"CREATE\s+VIEW\s+(?P<name>\S+)\s+AS\s*(?P<body>.*)", block, flags=re.I | re.S)
        name = simple.group('name') if simple else 'unknown_view'
        out = f"-- UNPARSED VIEW {name}\n-- Original:\n-- {block.replace('\n','\n-- ')}\n\n"
        return sanitize_name(name), out, ['unparsed']

    name = m.group('name')
    body = m.group('body').strip()

    transformed, flags = basic_rewrites(body)

    # build CREATE OR REPLACE VIEW
    out = f"CREATE OR REPLACE VIEW {name} AS\n{transformed};\n"
    return sanitize_name(name), out, flags


def main():
    text = read_src()
    parts = [p for p in re.split(r'(?=CREATE\s+VIEW\b)', text, flags=re.I) if p.strip()]

    os.makedirs(OUT_DIR, exist_ok=True)
    combined = []
    summary = []
    for part in parts:
        name, transformed, flags = transform_block(part)
        fn = OUT_DIR / f"{name}.sql"
        header = "-- Converted view (MariaDB-compatible)\n\n"
        if flags:
            header += "-- Flags: " + ", ".join(flags) + "\n"
        fn.write_text(header + transformed, encoding='utf-8')
        combined.append(header + transformed)
        summary.append((name, flags))

    COMBINED.parent.mkdir(parents=True, exist_ok=True)
    COMBINED.write_text("\n".join(combined), encoding='utf-8')
    print(f"Wrote {len(combined)} views to {OUT_DIR} and combined file {COMBINED}")

    # small summary print
    for name, flags in summary:
        print(f"{name}: {', '.join(flags) if flags else 'ok'}")


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""
Regenerate views from sql/create_views.sql using conservative transformations:
- IFNULL -> COALESCE
- Replace top-level || concatenations with CONCAT(...)
- Flag STRFTIME occurrences for manual review (do NOT auto-replace)
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'sql' / 'create_views.sql'
OUT_DIR = ROOT / 'migration' / 'ddl' / 'views'
COMBINED = ROOT / 'migration' / 'ddl' / 'create_views.sql'


def read_src():
    return SRC.read_text(encoding='utf-8')


def split_top_level_concat(expr: str):
    tokens = []
    cur = []
    depth = 0
    in_quote = None
    i = 0
    L = len(expr)
    while i < L:
        ch = expr[i]
        if in_quote:
            cur.append(ch)
            if ch == in_quote:
                in_quote = None
            i += 1
            continue
        if ch in ('"', "'"):
            in_quote = ch
            cur.append(ch)
            i += 1
            continue
        if ch == '(':
            depth += 1
            cur.append(ch)
            i += 1
            continue
        if ch == ')':
            depth = max(0, depth-1)
            cur.append(ch)
            i += 1
            continue
        if depth == 0 and expr[i:i+2] == '||':
            token = ''.join(cur).strip()
            tokens.append(token)
            cur = []
            i += 2
            continue
        cur.append(ch)
        i += 1
    last = ''.join(cur).strip()
    if last:
        tokens.append(last)
    return tokens


def replace_concat_top_level(s: str):
    if '||' not in s:
        return s, 0
    replaced = 0
    # find occurrences of expressions containing || at top level
    # naive approach: split by lines and replace within each line using parser
    lines = s.splitlines()
    out_lines = []
    for line in lines:
        if '||' not in line:
            out_lines.append(line)
            continue
        # attempt to replace top-level || sequences in the line
        new_line = line
        # find all spans where || occurs and try to extract full expression span
        # We'll attempt to split the line on '||' using split_top_level_concat for the whole line
        parts = split_top_level_concat(line)
        if len(parts) > 1:
            new_line = 'CONCAT(' + ', '.join(parts) + ')'
            replaced += 1
        out_lines.append(new_line)
    return '\n'.join(out_lines), replaced


def basic_rewrites(body: str):
    flags = []
    # IFNULL -> COALESCE
    if 'IFNULL(' in body.upper():
        body = re.sub(r"IFNULL\s*\(", 'COALESCE(', body, flags=re.I)
        flags.append('IFNULL -> COALESCE')
    # STRFTIME -> flag
    if 'STRFTIME(' in body.upper():
        flags.append('STRFTIME() used — manual review')
    # replace top-level || with CONCAT
    new_body, cnt = replace_concat_top_level(body)
    if cnt:
        body = new_body
        flags.append("'||' -> CONCAT() (best-effort)")
    return body, flags


def transform_block(block: str):
    m = re.match(r"CREATE\s+VIEW\s+(?P<name>\S+)\s+AS\s+(?P<body>.*)$", block, flags=re.I | re.S)
    if not m:
        return None
    name = m.group('name')
    body = m.group('body').strip()
    transformed, flags = basic_rewrites(body)
    out = f"CREATE OR REPLACE VIEW {name} AS\n{transformed};\n"
    return name.strip('`"[]'), out, flags


def main():
    text = read_src()
    parts = [p for p in re.split(r'(?=CREATE\s+VIEW\b)', text, flags=re.I) if p.strip()]
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    combined = []
    summary = []
    for p in parts:
        res = transform_block(p)
        if not res:
            continue
        name, out, flags = res
        fn = OUT_DIR / f"{name}.sql"
        header = "-- Converted view (MariaDB-compatible)\n\n"
        if flags:
            header += "-- Flags: " + ", ".join(flags) + "\n"
        fn.write_text(header + out, encoding='utf-8')
        combined.append(header + out)
        summary.append((name, flags))
    COMBINED.write_text('\n\n'.join(combined), encoding='utf-8')
    print(f"Wrote {len(summary)} views to {OUT_DIR} and combined file {COMBINED}")
    for name, flags in summary:
        print(f"{name}: {', '.join(flags) if flags else 'ok'}")

if __name__ == '__main__':
    main()

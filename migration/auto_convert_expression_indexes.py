#!/usr/bin/env python3
"""Auto-generate suggested fixes for expression-based and partial indexes.

Produces SQL files in `migration/suggested_fixes/convert_idx_<name>.sql` containing
ALTER TABLE ADD COLUMN ... GENERATED ... and CREATE INDEX statements.

This is best-effort and must be reviewed before applying.
"""
import re
import os
import argparse
from pathlib import Path

# reuse extractor from transform_indexes if available
try:
    from transform_indexes import extract_index_blocks, index_name_from_block, analyze_index
except Exception:
    # fallback simple extractor
    def extract_index_blocks(s):
        return re.findall(r"(CREATE\s+(?:UNIQUE\s+)?INDEX\b.*?;)", s, flags=re.I | re.S)
    def index_name_from_block(b):
        m = re.search(r"CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?[`\"]?([^\s`\"\(]+)[`\"]?",
                      b, re.I)
        return m.group(1) if m else None
    def analyze_index(b):
        flags = []
        if re.search(r"\bWHERE\b", b, re.I):
            flags.append('partial')
        m = re.search(r"ON\s+[^\s(]+\s*\(([^)]+)\)", b, re.I)
        if m:
            parts = [p.strip() for p in m.group(1).split(',')]
            for p in parts:
                if not re.match(r"^[`\"]?\w+[`\"]?(?:\s+(?:ASC|DESC))?$", p, re.I):
                    flags.append(('expr', p))
        return flags


def safe_name(n):
    return re.sub(r"[^A-Za-z0-9_]+", "_", n)


def infer_type_for_expr(expr):
    # simple heuristic: if expr contains letters -> VARCHAR, if digits/operators -> INT
    if re.search(r"[A-Za-z]", expr) and not re.search(r"\bCASE\b|\bWHEN\b", expr, re.I):
        return 'VARCHAR(255)'
    # arithmetic-like
    if re.search(r"[\+\-\*/]\s*\d|\d\s*[\+\-\*/]", expr):
        return 'INT'
    # default to VARCHAR
    return 'VARCHAR(255)'


def build_generated_column_sql(table, gen_col, expr, col_type):
    return f"ALTER TABLE {table} ADD COLUMN {gen_col} {col_type} GENERATED ALWAYS AS ({expr}) STORED;"


def build_index_sql(index_name, table, cols):
    return f"CREATE INDEX {index_name} ON {table} ({cols});"


def process_index(block, outdir):
    name = index_name_from_block(block)
    m = re.search(r"ON\s+([`\"]?\w+[`\"]?)\s*\(([^)]+)\)", block, re.I)
    if not m:
        return None
    table = m.group(1)
    cols = [p.strip() for p in m.group(2).split(',')]

    # detect expression parts and where clause
    expr_parts = []
    simple_cols = []
    for p in cols:
        if re.match(r"^[`\"]?\w+[`\"]?(?:\s+(?:ASC|DESC))?$", p, re.I):
            simple_cols.append(p)
        else:
            expr_parts.append(p)

    where_clause = None
    w = re.search(r"WHERE\s+(.+?)\s*;\s*$", block, re.I | re.S)
    if w:
        where_clause = w.group(1).strip()

    if not expr_parts and not where_clause:
        return None

    statements = []
    suggestions = []
    # For each expression, add a generated column
    gen_cols = []
    for i, expr in enumerate(expr_parts, start=1):
        clean_expr = expr
        gen_col = f"gen_{safe_name(name)}_{i}"
        col_type = infer_type_for_expr(expr)
        statements.append(build_generated_column_sql(table, gen_col, clean_expr, col_type))
        gen_cols.append(gen_col)
        suggestions.append(f"Generated column {gen_col} AS ({expr}) {col_type}")

    if where_clause:
        # create a generated bool column for the predicate
        gen_col = f"gen_{safe_name(name)}_where"
        # best-effort: use CASE WHEN predicate THEN 1 ELSE 0 END
        predicate = where_clause
        statements.append(build_generated_column_sql(table, gen_col, f"CASE WHEN {predicate} THEN 1 ELSE 0 END", 'TINYINT(1)'))
        gen_cols.insert(0, gen_col)
        suggestions.append(f"Generated column {gen_col} AS (CASE WHEN {predicate} THEN 1 ELSE 0 END) TINYINT(1)")

    # Build new index using generated cols + simple cols (preserve original order roughly)
    new_index_cols = ', '.join(gen_cols + simple_cols)
    new_index_name = f"gen_idx_{safe_name(name)}"
    statements.append(build_index_sql(new_index_name, table, new_index_cols))

    # Write to file
    outdir = Path(outdir)
    outdir.mkdir(parents=True, exist_ok=True)
    fname = outdir / f"convert_{safe_name(name)}.sql"
    if fname.exists():
        return str(fname)
    with open(fname, 'w', encoding='utf8') as f:
        f.write('-- Auto-generated suggestion to emulate expression/partial index\n')
        f.write('-- Original index:\n')
        f.write(block.strip() + '\n\n')
        for s in statements:
            f.write(s + '\n')
    return str(fname)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--src', default='sql/create_indexes.sql')
    p.add_argument('--out', default='migration/suggested_fixes')
    args = p.parse_args()

    with open(args.src, 'r', encoding='utf8') as f:
        src = f.read()

    blocks = extract_index_blocks(src)
    created = []
    for b in blocks:
        flags = analyze_index(b)
        # flags may be list of strings or tuples; consider any non-empty as candidate
        if flags:
            path = process_index(b, args.out)
            if path:
                created.append(path)

    print(f'Created {len(created)} suggested fixes:')
    for c in created:
        print('-', c)


if __name__ == '__main__':
    main()

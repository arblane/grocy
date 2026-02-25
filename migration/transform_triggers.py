#!/usr/bin/env python3
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'sql' / 'create_triggers.sql'
OUT_DIR = ROOT / 'migration' / 'ddl' / 'triggers'
COMBINED = ROOT / 'migration' / 'ddl' / 'create_triggers.sql'

def read_src():
    return SRC.read_text(encoding='utf-8')

def sanitize_name(name: str) -> str:
    return re.sub(r"[^0-9A-Za-z_]+", '_', name)

def replace_raise(body: str) -> str:
    # handle RAISE(type, 'msg') or RAISE(type, "msg")
    def _repl(m):
        msg = m.group('msg1') or m.group('msg2') or ''
        return f"SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='{msg}';"
    return re.sub(r"RAISE\s*\(\s*(?:ABORT|FAIL|ROLLBACK|IGNORE)\s*,\s*('(?P<msg1>[^']*)'|\"(?P<msg2>[^\"]*)\")\s*\)", _repl, body, flags=re.I)

def transform_block(block: str) -> (str, str):
    # Attempt to parse header
    header_re = re.compile(r"CREATE\s+TRIGGER\s+(?P<name>[`\"\[]?\w+[`\"\]]?)\s+(?P<timing>BEFORE|AFTER)\s+(?P<event>INSERT|UPDATE|DELETE|INSTEAD\s+OF)\s+ON\s+(?P<table>[`\"\[]?\w+[`\"\]]?)(?:\s+FOR\s+EACH\s+ROW)?(?:\s+WHEN\s*\((?P<when>.*?)\))?\s*BEGIN\s*(?P<body>.*)\s*END;", re.I | re.S)
    m = header_re.search(block)
    if not m:
        # fallback: try a simpler header match
        simple = re.match(r"CREATE\s+TRIGGER\s+(?P<name>\S+)\s+(?P<rest>.*)", block, flags=re.I)
        name = simple.group('name') if simple else 'unknown_trigger'
        out = f"-- UNPARSED TRIGGER {name}\n-- Original:\n-- {block.replace('\n','\n-- ')}\n\n"
        return (sanitize_name(name), out)

    name = m.group('name')
    timing = m.group('timing').upper()
    event = m.group('event').upper()
    table = m.group('table')
    when = m.group('when')
    body = m.group('body').strip()

    # Detect INSTEAD OF triggers (not supported in MySQL) and mark for manual review
    if 'INSTEAD' in event:
        out = f"-- INSTEAD OF trigger {name} on {table} requires manual conversion (not supported in MariaDB/MySQL)\n-- Original:\n-- {block.replace('\n','\n-- ')}\n\n"
        return (sanitize_name(name), out)

    # Replace RAISE(...) with SIGNAL
    body = replace_raise(body)

    # Convert WHEN clause into IF wrapper inside body
    if when:
        body = f"IF ({when}) THEN\n{body}\nEND IF;"

    # Build MariaDB trigger DDL. Use stored delimiter $$ to allow semicolons.
    header = f"CREATE TRIGGER {name} {timing} {event.replace('INSTEAD OF','').strip()} ON {table} FOR EACH ROW"
    out = f"{header}\nBEGIN\n{body}\nEND;\n"
    return (sanitize_name(name), out)

def main():
    text = read_src()
    # split by CREATE TRIGGER occurrences
    parts = [p for p in re.split(r'(?=CREATE\s+TRIGGER\b)', text, flags=re.I) if p.strip()]

    os.makedirs(OUT_DIR, exist_ok=True)
    combined_parts = []
    for part in parts:
        name, transformed = transform_block(part)
        # write per-trigger file
        fn = OUT_DIR / f"{name}.sql"
        fn.write_text("-- Converted trigger (MariaDB compatible)\n\nDELIMITER $$\n" + transformed + "$$\nDELIMITER ;\n", encoding='utf-8')
        combined_parts.append("DELIMITER $$\n" + transformed + "$$\nDELIMITER ;\n")

    # write combined file
    COMBINED.parent.mkdir(parents=True, exist_ok=True)
    COMBINED.write_text("\n".join(combined_parts), encoding='utf-8')
    print(f"Wrote {len(combined_parts)} triggers to {OUT_DIR} and combined file {COMBINED}")

if __name__ == '__main__':
    main()

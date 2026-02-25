#!/usr/bin/env python3
"""Conservatively convert double-quoted identifiers to backticks in DDL files.
Creates a .bak copy before changing each file and writes a log at
`migration/ddl/quote_conversion_log.txt` with the list of modified files.

Only replaces occurrences matching "identifier" where identifier is [A-Za-z0-9_]+.
This avoids touching string literals containing spaces or punctuation.
"""
import re
import glob
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = []
# common SQL files
FILES += [
    ROOT / 'sql' / 'create_tables.sql',
    ROOT / 'sql' / 'create_views.sql',
    ROOT / 'sql' / 'create_triggers.sql',
    ROOT / 'migration' / 'ddl' / 'create_tables_test.sql',
    ROOT / 'migration' / 'ddl' / 'create_triggers_test.sql',
    ROOT / 'migration' / 'ddl' / 'create_views_test.sql',
    ROOT / 'migration' / 'ddl' / 'create_indexes.sql',
]

# per-object folders
FILES += glob.glob(str(ROOT / 'migration' / 'ddl' / 'views' / '*.sql'))
FILES += glob.glob(str(ROOT / 'migration' / 'ddl' / 'triggers' / '*.sql'))

PAT = re.compile(r'"([A-Za-z0-9_]+)"')

log = []

for f in FILES:
    p = Path(f)
    if not p.exists():
        continue
    txt = p.read_text(encoding='utf-8')
    new = PAT.sub(r'`\1`', txt)
    if new != txt:
        bak = p.with_suffix(p.suffix + '.bak')
        if not bak.exists():
            p.rename(bak)
            bak.write_text(txt, encoding='utf-8')
            p.write_text(new, encoding='utf-8')
            log.append(f"UPDATED: {p.relative_to(ROOT)} (backup: {bak.name})")
        else:
            # If .bak already exists, just overwrite file and note it
            p.write_text(new, encoding='utf-8')
            log.append(f"UPDATED (bak existed): {p.relative_to(ROOT)}")

out = ROOT / 'migration' / 'ddl' / 'quote_conversion_log.txt'
out.write_text('\n'.join(log) + ('\n' if log else ''), encoding='utf-8')
print(f"Processed {len(FILES)} files, modified {len(log)} files. Log: {out}")

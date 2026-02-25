#!/usr/bin/env python3
"""Replace AUTOINCREMENT -> AUTO_INCREMENT in DDL files (conservative).
Creates .bak backups and writes a log to `migration/ddl/autoinc_conversion_log.txt`.
"""
import re
from pathlib import Path
import glob

ROOT = Path(__file__).resolve().parents[1]
patterns = [
    str(ROOT / 'sql' / 'create_tables.sql'),
    str(ROOT / 'migration' / 'ddl' / 'create_tables_test.sql'),
]
patterns += glob.glob(str(ROOT / 'migration' / 'ddl' / '**' / '*.sql'), recursive=True)

PAT = re.compile(r'\bAUTOINCREMENT\b', re.IGNORECASE)
PRIMARY_AUTOINC = re.compile(r'\bPRIMARY\s+AUTOINCREMENT\b', re.IGNORECASE)
PRIMARY_KEY_AUTOINC = re.compile(r'\bPRIMARY\s+KEY\s+AUTOINCREMENT\b', re.IGNORECASE)

modified = []

for f in sorted(set(patterns)):
    p = Path(f)
    if not p.exists():
        continue
    txt = p.read_text(encoding='utf-8')
    new = txt
    # Normalize SQLite-style PRIMARY AUTOINCREMENT -> PRIMARY KEY AUTO_INCREMENT
    new = PRIMARY_KEY_AUTOINC.sub('PRIMARY KEY AUTO_INCREMENT', new)
    new = PRIMARY_AUTOINC.sub('PRIMARY KEY AUTO_INCREMENT', new)
    # Replace any remaining AUTOINCREMENT tokens
    new = PAT.sub('AUTO_INCREMENT', new)
    if new != txt:
        bak = p.with_suffix(p.suffix + '.bak')
        if not bak.exists():
            bak.write_text(txt, encoding='utf-8')
        p.write_text(new, encoding='utf-8')
        modified.append(p.relative_to(ROOT))

out = ROOT / 'migration' / 'ddl' / 'autoinc_conversion_log.txt'
out.write_text('\n'.join([str(x) for x in modified]) + ('\n' if modified else ''), encoding='utf-8')
print(f"Processed {len(patterns)} paths, modified {len(modified)} files. Log: {out}")

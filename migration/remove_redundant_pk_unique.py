#!/usr/bin/env python3
"""Remove redundant UNIQUE after PRIMARY KEY AUTO_INCREMENT.

Creates .bak backups before modifying files.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    ROOT / 'sql' / 'create_tables.sql',
    ROOT / 'migration' / 'ddl' / 'create_tables_test.sql',
]

PAT = re.compile(r'PRIMARY\s+KEY\s+AUTO_INCREMENT\s+UNIQUE', re.IGNORECASE)

def convert_file(path: Path) -> bool:
    text = path.read_text(encoding='utf-8')
    new = PAT.sub('PRIMARY KEY AUTO_INCREMENT', text)
    if new != text:
        bak = path.with_suffix(path.suffix + '.bak')
        if not bak.exists():
            bak.write_text(text, encoding='utf-8')
        path.write_text(new, encoding='utf-8')
        return True
    return False

modified = []
for f in FILES:
    if f.exists() and convert_file(f):
        modified.append(f.relative_to(ROOT))

if modified:
    print('Modified files:')
    for m in modified:
        print('-', m)
else:
    print('No changes applied')

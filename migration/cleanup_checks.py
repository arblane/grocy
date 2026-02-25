#!/usr/bin/env python3
"""Remove CHECK constraints and clean up leftover parentheses.

This fixes artifacts like "DEFAULT 0)," or "NOT NULL)," after CHECK removal.
Creates .bak backups before modifying files.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
FILES = [
    ROOT / 'sql' / 'create_tables.sql',
    ROOT / 'migration' / 'ddl' / 'create_tables_test.sql',
]

CHECK_RE = re.compile(r'\s+CHECK\s*\([^)]*\)', re.IGNORECASE)

def clean(text: str) -> str:
    out = CHECK_RE.sub('', text)

    # Remove stray ')' left behind after CHECK removal
    out = re.sub(r'(\bDEFAULT\b[^,;\n]*?)\)\s*,', r'\1,', out)
    out = re.sub(r'(\bDEFAULT\b[^;\n]*?)\)\s*\);', r'\1);', out)
    out = re.sub(r'\bNOT NULL\s*\)\s*,', 'NOT NULL,', out, flags=re.IGNORECASE)
    out = re.sub(r'\bNOT NULL\s*\)\s*\);', 'NOT NULL);', out, flags=re.IGNORECASE)
    return out


def convert_file(path: Path) -> bool:
    text = path.read_text(encoding='utf-8')
    new = clean(text)
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

#!/usr/bin/env python3
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
COUNT=0
for dirpath in (ROOT / 'migration' / 'ddl' / 'views', ROOT / 'migration' / 'ddl' / 'triggers'):
    d = Path(dirpath)
    if not d.exists():
        continue
    for bak in d.glob('*.bak'):
        orig = bak.with_suffix('')
        print(f"Restoring {bak} -> {orig}")
        orig.write_text(bak.read_text(encoding='utf-8'), encoding='utf-8')
        COUNT += 1
print(f"Restored {COUNT} files")

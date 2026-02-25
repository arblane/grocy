#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
TARGETS = [ROOT / 'migration' / 'ddl' / 'views', ROOT / 'migration' / 'ddl' / 'triggers']

MAP = {
    '%Y-%m-%d': '%Y-%m-%d',
    '%H:%M:%S': '%H:%i:%s',
    '%Y-%W': '%Y-%v',
}

STRF_RE = re.compile(r"STRFTIME\s*\(\s*(['\"])(?P<fmt>[^'\"]+)\1\s*,\s*(?P<expr>[^)]+)\)", re.I | re.S)

def replace_in_text(text: str):
    changed = 0
    notes = []
    def repl(m):
        nonlocal changed, notes
        fmt = m.group('fmt')
        expr = m.group('expr').strip()
        mapped = MAP.get(fmt)
        if mapped:
            changed += 1
            return f"DATE_FORMAT({expr}, '{mapped}')"
        else:
            notes.append((fmt, expr))
            return m.group(0)
    new = STRF_RE.sub(repl, text)
    return new, changed, notes

def process_path(p: Path):
    s = p.read_text(encoding='utf-8')
    new, changed, notes = replace_in_text(s)
    if changed:
        bak = p.with_suffix(p.suffix + '.bak')
        bak.write_text(s, encoding='utf-8')
        p.write_text(new, encoding='utf-8')
    return changed, notes

def main():
    total = 0
    all_notes = []
    for d in TARGETS:
        if not d.exists():
            continue
        for f in sorted(d.glob('*.sql')):
            c, notes = process_path(f)
            if c:
                print(f"{f}: applied {c} STRFTIME -> DATE_FORMAT mapping(s)")
                total += c
            for n in notes:
                all_notes.append((f.name, n))
    print(f"Total applied: {total}")
    if all_notes:
        print('Files with unmapped STRFTIME formats:')
        for fname, (fmt, expr) in all_notes:
            print(f" - {fname}: '{fmt}' in STRFTIME(..., {expr})")

if __name__ == '__main__':
    main()

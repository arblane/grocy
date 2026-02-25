#!/usr/bin/env python3
"""
Fix DATE_FORMAT(format_literal, expr) -> DATE_FORMAT(expr, format_literal)
and map common strftime tokens to MySQL DATE_FORMAT tokens.
Runs over migration/ddl/views/*.sql and migration/ddl/triggers/*.sql
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
TARGET_DIRS = [ROOT / 'migration' / 'ddl' / 'views', ROOT / 'migration' / 'ddl' / 'triggers']
TOKEN_MAP = {
    '%Y': '%Y',
    '%y': '%y',
    '%m': '%m',
    '%d': '%d',
    '%H': '%H',
    '%M': '%i',
    '%S': '%s',
    '%f': '%f',
    '%W': '%v',
    '%w': '%w',
    '%j': '%j',
}


def find_dateformat_spans(text: str):
    # find occurrences of DATE_FORMAT( and parse balanced parentheses
    i = 0
    L = len(text)
    while True:
        idx = text.lower().find('date_format(', i)
        if idx == -1:
            break
        p = idx + len('date_format(')
        depth = 1
        while p < L and depth > 0:
            if text[p] == '(':
                depth += 1
            elif text[p] == ')':
                depth -= 1
            p += 1
        yield idx, p
        i = p


def map_tokens(fmt: str):
    out = ''
    i = 0
    L = len(fmt)
    while i < L:
        if fmt[i] == '%' and i + 1 < L:
            tok = fmt[i:i+2]
            out += TOKEN_MAP.get(tok, tok)
            i += 2
        else:
            out += fmt[i]
            i += 1
    return out


def process_file(path: Path):
    s = path.read_text(encoding='utf-8')
    changed = 0
    out = []
    last = 0
    for start, end in find_dateformat_spans(s):
        out.append(s[last:start])
        span = s[start:end]
        # extract first argument if it's a string literal
        m = re.match(r"DATE_FORMAT\s*\(\s*('(?P<fmt1>[^']*)'|\"(?P<fmt2>[^\"]*)\")\s*,\s*(?P<expr>.*)\)\s*$", span, flags=re.I | re.S)
        if not m:
            # try more lenient: capture first quoted arg and rest before closing )
            m2 = re.match(r"DATE_FORMAT\s*\(\s*('(?P<fmt1>[^']*)'|\"(?P<fmt2>[^\"]*)\")\s*,\s*(?P<expr>.*)\)", span, flags=re.I | re.S)
            m = m2
        if m and (m.group('fmt1') or m.group('fmt2')):
            fmt = m.group('fmt1') or m.group('fmt2')
            expr = m.group('expr').rstrip(')\n ').strip()
            mapped_fmt = map_tokens(fmt)
            new = f"DATE_FORMAT({expr}, '{mapped_fmt}')"
            out.append(new)
            changed += 1
        else:
            out.append(span)
        last = end
    out.append(s[last:])
    new_s = ''.join(out)
    if changed:
        path.write_text(new_s, encoding='utf-8')
    return changed


def main():
    total = 0
    for d in TARGET_DIRS:
        if not d.exists():
            continue
        for p in sorted(d.glob('*.sql')):
            c = process_file(p)
            if c:
                print(f"{p}: fixed {c} DATE_FORMAT() call(s)")
                total += c
    print(f"Total DATE_FORMAT fixes: {total}")


if __name__ == '__main__':
    main()

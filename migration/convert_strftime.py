#!/usr/bin/env python3
"""
Heuristic converter: STRFTIME(fmt, expr) -> DATE_FORMAT(expr, mapped_fmt)
- Applies to files in migration/ddl/views/*.sql
- Performs conservative token mapping; leaves an INFO comment when unsupported tokens are present.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
VIEWS_DIR = ROOT / 'migration' / 'ddl' / 'views'
COMBINED = ROOT / 'migration' / 'ddl' / 'create_views.sql'

# Mapping from SQLite strftime tokens -> MySQL DATE_FORMAT tokens
TOKEN_MAP = {
    '%Y': '%Y',
    '%y': '%y',
    '%m': '%m',
    '%d': '%d',
    '%H': '%H',
    '%M': '%i',  # minutes
    '%S': '%s',  # seconds
    '%f': '%f',  # fractional seconds (microseconds)
    '%W': '%v',  # week number (approximate mapping; REVIEW)
    '%w': '%w',
    '%j': '%j',
    '%%': '%%'
}

UNSUPPORTED = set()
for k in TOKEN_MAP.keys():
    # keep set ready
    pass

FMT_RE = re.compile(r"STRFTIME\s*\(", re.I)


def find_strftime_spans(text: str):
    """Yield (start_idx, end_idx, fmt, expr) for each STRFTIME(...) occurrence.
    This parser handles single- or double-quoted format strings and nested parentheses in the expression.
    """
    i = 0
    L = len(text)
    while True:
        m = FMT_RE.search(text, i)
        if not m:
            break
        start = m.start()
        # parse until matching closing parenthesis for STRFTIME(...)
        p = m.end()  # position after 'STRFTIME('
        depth = 1
        content_start = p
        while p < L and depth > 0:
            if text[p] == '(':
                depth += 1
            elif text[p] == ')':
                depth -= 1
            p += 1
        end = p  # position after closing ')'
        inner = text[content_start:end-1].strip()
        # inner expected: <format>, <expr>
        # split on first comma that's not inside quotes or parentheses
        comma_idx = None
        qdepth = 0
        in_quote = None
        for idx, ch in enumerate(inner):
            if in_quote:
                if ch == in_quote:
                    in_quote = None
                continue
            if ch in ('"', "'"):
                in_quote = ch
                continue
            if ch == '(':
                qdepth += 1
                continue
            if ch == ')':
                qdepth = max(0, qdepth-1)
                continue
            if ch == ',' and qdepth == 0:
                comma_idx = idx
                break
        if comma_idx is None:
            fmt_part = inner
            expr_part = ''
        else:
            fmt_part = inner[:comma_idx].strip()
            expr_part = inner[comma_idx+1:].strip()

        # extract fmt string without surrounding quotes
        fmt = None
        if len(fmt_part) >= 2 and fmt_part[0] in ('"', "'") and fmt_part[-1] == fmt_part[0]:
            fmt = fmt_part[1:-1]
        else:
            # not a literal format — skip
            fmt = None

        yield start, end, fmt, expr_part
        i = end


def map_format(fmt: str):
    # replace tokens like %Y with mapped tokens; flag uncommon tokens
    out = ''
    i = 0
    L = len(fmt)
    flags = []
    while i < L:
        if fmt[i] == '%':
            if i + 1 < L:
                tok = fmt[i:i+2]
                mapped = TOKEN_MAP.get(tok)
                if mapped:
                    out += mapped
                else:
                    # unknown token — keep as-is but flag for manual review
                    out += tok
                    flags.append(f'unmapped_token:{tok}')
                i += 2
            else:
                out += '%'
                i += 1
        else:
            out += fmt[i]
            i += 1
    return out, flags


def convert_in_text(text: str):
    changed = 0
    notes = []
    out = []
    last = 0
    for start, end, fmt, expr in find_strftime_spans(text):
        out.append(text[last:start])
        if fmt is None:
            # leave original and flag
            snippet = text[start:end]
            out.append(f"/* NOTE: STRFTIME with non-literal format left as-is */{snippet}")
            notes.append((None, snippet, ['non_literal_format']))
        else:
            mapped, flags = map_format(fmt)
            if flags:
                notes.append((fmt, expr, flags))
                out.append(f"/* NOTE: STRFTIME mapping incomplete: {flags} */ DATE_FORMAT({expr}, '{mapped}')")
                changed += 1
            else:
                out.append(f"DATE_FORMAT({expr}, '{mapped}')")
                changed += 1
        last = end
    out.append(text[last:])
    new_text = ''.join(out)
    return new_text, changed, notes


def process_file(path: Path):
    s = path.read_text(encoding='utf-8')
    if 'STRFTIME' not in s.upper():
        return 0, []
    new_s, changed, notes = convert_in_text(s)
    if changed:
        # prepend a brief note if there were unmapped tokens
        extra = ''
        for fmt, expr, flags in notes:
            extra += f"-- NOTE: STRFTIME('{fmt}', {expr}) had tokens {flags}\n"
        new_s = extra + new_s
        path.write_text(new_s, encoding='utf-8')
    return changed, notes


def rebuild_combined():
    files = sorted(VIEWS_DIR.glob('*.sql'))
    parts = []
    for f in files:
        parts.append(f.read_text(encoding='utf-8'))
    COMBINED.write_text('\n\n'.join(parts), encoding='utf-8')


def main():
    VIEWS_DIR.mkdir(parents=True, exist_ok=True)
    total = 0
    all_notes = []
    for p in sorted(VIEWS_DIR.glob('*.sql')):
        changed, notes = process_file(p)
        if changed:
            print(f"{p.name}: converted {changed} STRFTIME() occurrence(s)")
            total += changed
        for n in notes:
            all_notes.append((p.name, n))
    rebuild_combined()
    print(f"Total STRFTIME conversions: {total}")
    if all_notes:
        print('Files with unmapped tokens:')
        for fname, (fmt, expr, flags) in all_notes:
            print(f" - {fname}: STRFTIME('{fmt}', {expr}) => flags={flags}")

if __name__ == '__main__':
    main()

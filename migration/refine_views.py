#!/usr/bin/env python3
"""
Refine converted view SQL files:
- Convert sequences of `expr || expr || ...` into CONCAT(expr, expr, ...)
  with a simple top-level tokenizer that ignores `||` inside parentheses.
- Add INFO comments where STRFTIME remains for manual mapping.
- Rebuild combined create_views.sql
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
VIEWS_DIR = ROOT / 'migration' / 'ddl' / 'views'
COMBINED = ROOT / 'migration' / 'ddl' / 'create_views.sql'


def split_top_level_concat(s: str):
    """Split an expression string into top-level tokens separated by || (ignoring || in parentheses)."""
    tokens = []
    cur = []
    depth = 0
    i = 0
    L = len(s)
    while i < L:
        if s[i] == '(':
            depth += 1
            cur.append(s[i])
            i += 1
        elif s[i] == ')':
            depth = max(0, depth-1)
            cur.append(s[i])
            i += 1
        elif depth == 0 and s[i:i+2] == '||':
            token = ''.join(cur).strip()
            tokens.append(token)
            cur = []
            i += 2
        else:
            cur.append(s[i])
            i += 1
    last = ''.join(cur).strip()
    if last:
        tokens.append(last)
    return tokens


def replace_concats_in_text(text: str):
    # find occurrences of || outside quotes; we'll do a simple scan to find candidate spans
    # fallback: apply regex for small patterns, and a safe iterative parser for longer ones

    if '||' not in text:
        return text, 0

    count = 0
    out = []
    i = 0
    L = len(text)
    while i < L:
        if text[i:i+2] == '||':
            # shouldn't normally happen at top-level because surrounding tokens are needed
            out.append('||')
            i += 2
            continue
        # try to find an expression span that contains '||'
        m = re.search(r"([\w\)\]'\"]+\s*(?:\|\|\s*[\w\(\['\"]+)+)", text[i:])
        if not m:
            out.append(text[i:])
            break
        start = i + m.start()
        end = i + m.end()
        # append prefix
        out.append(text[i:start])
        span = text[start:end]
        # split and join using safer top-level splitter
        tokens = split_top_level_concat(span)
        if len(tokens) > 1:
            # wrap tokens with CONCAT
            new = 'CONCAT(' + ', '.join(t for t in tokens) + ')'
            out.append(new)
            count += 1
        else:
            out.append(span)
        i = end
    new_text = ''.join(out)
    return new_text, count


def process_file(path: Path):
    s = path.read_text(encoding='utf-8')
    header_lines = []
    body = s
    if s.startswith('-- Converted view'):
        parts = s.split('\n', 5)
        # keep first header block if present
        # simple approach: leave header as-is and operate on whole file
    # replace concats
    new_s, replaced = replace_concats_in_text(s)
    flags = []
    if replaced:
        flags.append(f"Rewrote {replaced} '||' concatenation(s) into CONCAT()")
    # annotate STRFTIME occurrences
    if re.search(r"STRFTIME\s*\(", new_s, flags=re.I):
        flags.append('STRFTIME() occurrences left for manual mapping to DATE_FORMAT()')
        # add an INFO comment near top
        new_s = new_s.replace('\n', '\n', 1)  # no-op to preserve content
        new_s = '-- NOTE: STRFTIME() detected — manual mapping to DATE_FORMAT() may be required\n' + new_s
    if flags:
        # prepend a flags comment block
        flag_comment = '-- Refine notes: ' + '; '.join(flags) + '\n'
        if not new_s.startswith('-- Refine notes:'):
            new_s = flag_comment + new_s
    if new_s != s:
        path.write_text(new_s, encoding='utf-8')
    return path.name, replaced, flags


def rebuild_combined():
    files = sorted(VIEWS_DIR.glob('*.sql'))
    parts = []
    for f in files:
        parts.append(f.read_text(encoding='utf-8'))
    COMBINED.write_text('\n\n'.join(parts), encoding='utf-8')


def main():
    VIEWS_DIR.mkdir(parents=True, exist_ok=True)
    summary = []
    total_rewrites = 0
    for p in sorted(VIEWS_DIR.glob('*.sql')):
        name, replaced, flags = process_file(p)
        summary.append((name, replaced, flags))
        total_rewrites += replaced
    rebuild_combined()
    print(f"Processed {len(summary)} view files, rewrote {total_rewrites} concatenation(s).")
    for name, replaced, flags in summary:
        print(f"{name}: rewrites={replaced}, notes={'; '.join(flags) if flags else 'ok'}")

if __name__ == '__main__':
    main()

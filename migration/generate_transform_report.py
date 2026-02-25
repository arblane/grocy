#!/usr/bin/env python3
"""Generate a markdown report of table-by-table transformations.

This imports the transformer utilities and writes `migration/transform_report.md`.
"""
import os
import importlib.util
import sys

proj_root = os.path.dirname(os.path.dirname(__file__))
sys.path.insert(0, os.path.join(proj_root, 'migration'))

import transform_tables as tt

SRC = os.path.join(proj_root, 'sql', 'create_tables.sql')
OUT = os.path.join(proj_root, 'migration', 'transform_report.md')


def main():
    with open(SRC, 'r', encoding='utf8') as f:
        src = f.read()

    blocks = tt.extract_table_blocks(src)
    reports = []
    for b in blocks:
        name = tt.table_name_from_block(b) or 'unknown_table'
        try:
            transformed = tt.apply_mappings(b, tt.DEFAULT_MAPPING)
        except Exception as e:
            transformed = None
            error = str(e)
        else:
            error = None
        flags = tt.analyze_block(b) if hasattr(tt, 'analyze_block') else []
        # Detect check conversion comments inserted by transformer
        conversions = []
        for marker in ['/* CHECK converted:', '/* CHECK converted to ENUM:', "/* CHECK converted: LENGTH -> VARCHAR */", "/* CHECK converted: >=0 -> UNSIGNED */"]:
            if transformed and marker in transformed:
                conversions.append(marker.strip('/* ').strip())

        newtxt = transformed.strip() if transformed else ''
        reports.append((name, flags, conversions, b.strip(), newtxt))

    with open(OUT, 'w', encoding='utf8') as f:
        f.write('# CREATE_TABLES Transformation Report\n\n')
        f.write(f'Total tables found: {len(reports)}\n\n')
        for name, flags, convs, orig, new in reports:
            f.write(f'## {name}\n\n')
            if flags:
                f.write('**Flags:** ' + ', '.join(flags) + '\n\n')
            if convs:
                f.write('**Automatic CHECK conversions applied:** ' + ', '.join(convs) + '\n\n')
            f.write('**Original:**\n\n')
            f.write('```sql\n')
            f.write(orig + '\n')
            f.write('```\n\n')
            f.write('**Transformed:**\n\n')
            f.write('```sql\n')
            f.write((new or '') + '\n')
            f.write('```\n\n')
            if error:
                f.write('**Transformation error:** ' + error + '\n\n')

    print('Wrote report to', OUT)


if __name__ == '__main__':
    main()

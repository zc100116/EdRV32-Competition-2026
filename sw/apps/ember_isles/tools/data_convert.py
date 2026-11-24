#!/usr/bin/env python3
# File: data_convert.py; ember_isles gdd 10 and tech 5.
# Convert UTF-8 content tables to C11 records; outputs belong in build/.
import csv
import json
from pathlib import Path

APP = Path(__file__).resolve().parents[1]
ROOT = APP.parents[2]
TEXT = {'id', 'name', 'tags', 'effect', 'attribute', 'calculation', 'passive', 'skill_a',
        'skill_b', 'ultimate', 'talents', 'affinity', 'weapon', 'rarity', 'element',
        'shape', 'trigger', 'enemy', 'affix', 'stage', 'behavior', 'target'}


def convert():
    out = ROOT / 'build/ember_isles/generated'
    out.mkdir(parents=True, exist_ok=True)
    lines = ['/* Generated CSV records; attributes include gameplay and numeric caps (gdd 2.2a). */', '#ifndef EMBER_DATA_H',
             '#define EMBER_DATA_H', '#include <stdint.h>']
    for path in sorted((APP / 'data').glob('*.csv')):
        with path.open(encoding='utf-8', newline='') as stream:
            reader = csv.DictReader(stream)
            fields = reader.fieldnames
            rows = list(reader)
        table = path.stem
        if table == 'attributes':
            lines.append('enum ember_data_attribute_index {')
            for index, row in enumerate(rows):
                lines.append(f'    EMBER_DATA_ATTR_{row["id"].upper()} = {index},')
            lines.append('};')
        lines.append(f'struct ember_{table}_row {{')
        for field in fields:
            kind = 'const char *' if field in TEXT else 'int32_t '
            lines.append(f'    {kind}{field};')
        lines.append('};')
        lines.append(f'#define EMBER_{table.upper()}_COUNT {len(rows)}u')
        if rows:
            lines.append(f'static const struct ember_{table}_row ember_{table}[] = {{')
            for row in rows:
                values = [json.dumps(row[f], ensure_ascii=True) if f in TEXT
                          else str(int(row[f])) for f in fields]
                lines.append('    {' + ', '.join(values) + '},')
            lines.append('};')
    lines += ['#endif', '']
    (out / 'data.h').write_text('\n'.join(lines), encoding='utf-8')
    print('data: generated ' + str(out / 'data.h'))


if __name__ == '__main__':
    convert()

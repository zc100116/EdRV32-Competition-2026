#!/usr/bin/env python3
# File: e4_table_test.py; demonstrate CSV-only gameplay tuning with normal rebuild.
import csv
import io
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
APP = ROOT / 'sw/apps/ember_isles'
OUT = ROOT / 'build/ember_isles'
fragment = OUT / 'e4-table.mk'
fragment.write_text('''include sw/apps/ember_isles/Makefile
$(OUT)/e4-table-test: $(APP)/tools/e4_table_test.c $(OUT)/generated/data.h $(HEADERS)
\t$(CC) $(CFLAGS) $(APP)/tools/e4_table_test.c $(APP)/src/sim/combat.c $(APP)/src/core/core.c -o $@
''')

def rebuild(expected):
    subprocess.run(['python3', str(APP / 'tools/data_convert.py')], cwd=ROOT, check=True)
    subprocess.run(['make', '-f', str(fragment), str(OUT / 'e4-table-test'), '-j1'],
                   cwd=ROOT, check=True)
    output = subprocess.check_output([str(OUT / 'e4-table-test')], text=True).strip()
    if output != f'ironwall={expected}':
        raise AssertionError(f'expected ironwall={expected}, got {output}')
    print(output, flush=True)

path = APP / 'data/characters.csv'
original = path.read_text()
rebuild(50)
reader = csv.DictReader(io.StringIO(original))
fields = reader.fieldnames
rows = list(reader)
next(row for row in rows if row['id'] == 'smith')['skill_l_value'] = '37'
try:
    with path.open('w', newline='') as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)
    rebuild(37)
finally:
    path.write_text(original)
    subprocess.run(['python3', str(APP / 'tools/data_convert.py')], cwd=ROOT, check=True)
rebuild(50)
print('PASS CSV-only ironwall 50 -> 37 -> 50; C source unchanged')

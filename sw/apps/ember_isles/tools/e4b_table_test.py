#!/usr/bin/env python3
# File: e4b_table_test.py; gdd 2.4 numeric tuning with unchanged C mechanisms.
import csv
import io
import subprocess
from pathlib import Path
ROOT = Path(__file__).resolve().parents[4]
APP = ROOT / 'sw/apps/ember_isles'
OUT = ROOT / 'build/ember_isles'
fragment = OUT / 'e4b-table.mk'
fragment.write_text('''include sw/apps/ember_isles/Makefile
$(OUT)/e4b-table-test: $(APP)/tools/e4b_table_test.c $(OUT)/generated/data.h $(HEADERS)
\t$(CC) $(CFLAGS) $(APP)/tools/e4b_table_test.c $(APP)/src/sim/combat.c $(APP)/src/core/core.c -o $@
''')
def rebuild(expected):
    subprocess.run(['python3', str(APP / 'tools/data_convert.py')], cwd=ROOT, check=True)
    subprocess.run(['make', '-f', str(fragment), str(OUT / 'e4b-table-test'), '-j1'], cwd=ROOT, check=True)
    actual = subprocess.check_output([str(OUT / 'e4b-table-test')], text=True).strip()
    assert actual == expected, f'expected {expected}, got {actual}'
    print(actual, flush=True)
changes = {'characters': {'nameless': {'facing_lock_frames': 7},
                         'seer': {'skill_k_slow_percent': 45, 'skill_k_slow_frames': 70},
                         'lamplighter': {'skill_l_value': 40, 'skill_l_value2': 6}},
           'relics': {'star_hourglass': {'value': 17}},
           'resonances': {'abyss': {'slow_frames': 40}}}
originals = {table: (APP / 'data' / f'{table}.csv').read_text() for table in changes}
baseline = 'lock=12 gate=30/90 abyss=90 discount=60 damage=24 armor=10'
rebuild(baseline)
try:
    for table, entries in changes.items():
        reader = csv.DictReader(io.StringIO(originals[table]))
        fields = reader.fieldnames
        rows = list(reader)
        for row in rows:
            for key, value in entries.get(row['id'], {}).items():
                row[key] = str(value)
        with (APP / 'data' / f'{table}.csv').open('w', newline='') as stream:
            writer = csv.DictWriter(stream, fieldnames=fields, lineterminator='\n')
            writer.writeheader()
            writer.writerows(rows)
    rebuild('lock=7 gate=45/70 abyss=40 discount=17 damage=28 armor=6')
finally:
    for table, text in originals.items():
        (APP / 'data' / f'{table}.csv').write_text(text)
    subprocess.run(['python3', str(APP / 'tools/data_convert.py')], cwd=ROOT, check=True)
rebuild(baseline)
print('PASS E4b CSV-only tuning; C source unchanged')

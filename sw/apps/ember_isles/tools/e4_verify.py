#!/usr/bin/env python3
# File: e4_verify.py; tech 6 E4 directed assertions, per-row coverage and capture.
# Python standard library only; all compilation products belong in build/.
import csv
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
APP = ROOT / 'sw/apps/ember_isles'
OUT = ROOT / 'build/ember_isles'
OUT.mkdir(parents=True, exist_ok=True)
(ROOT / 'outputs/ember_isles/e4').mkdir(parents=True, exist_ok=True)
fragment = OUT / 'e4.mk'
fragment.write_text('''include sw/apps/ember_isles/Makefile
E4_INPUTS := $(APP)/src/sim/sim.c $(APP)/src/sim/combat.c $(APP)/src/core/core.c
$(OUT)/e4-content-test: $(APP)/tools/e4_content_test.c $(E4_INPUTS) $(OUT)/generated/data.h $(HEADERS)
\t$(CC) $(CFLAGS) $(APP)/tools/e4_content_test.c $(APP)/src/sim/combat.c $(APP)/src/core/core.c -o $@
$(OUT)/e4-capture: $(SOURCES) $(APP)/src/game.c $(APP)/tools/e4_capture.c $(GEN) $(HEADERS)
\t$(CC) -pthread $(PCFLAGS) $(SOURCES) $(APP)/src/game.c $(APP)/tools/e4_capture.c $(addprefix $(ROOT)/,$(DRIVERS) $(PC) tools/gpu/emu/pc/png.c) -o $@
''')
subprocess.run(['make', '-f', str(fragment), str(OUT / 'e4-content-test'),
                str(OUT / 'e4-capture'), '-j1'], cwd=ROOT, check=True)
with (OUT / 'e4-content.log').open('w') as log:
    subprocess.run([str(OUT / 'e4-content-test')], cwd=ROOT, stdout=log, check=True)
with (OUT / 'e4-coverage.csv').open('w', newline='') as stream:
    writer = csv.writer(stream)
    writer.writerow(['表', '稳定ID', '名称', '定向用例'])
    for line in (OUT / 'e4-content.log').read_text().splitlines():
        if line.startswith('COVER,'):
            _, table, id_ = line.split(',')
            with (APP / 'data' / (table + '.csv')).open() as source:
                row = next(r for r in csv.DictReader(source) if r['id'] == id_)
            functions = {'weapons': 'weapons/evolutions', 'relics': 'relics/relic_rules',
                         'characters': 'characters/determinism', 'summons': 'entity_rules',
                         'enemies': 'enemies/entity_rules', 'pets': 'pets/pet_runes',
                         'pet_weapons': 'pets/pet_runes', 'affixes': 'enemies/entity_rules/dark_projectile_snapshot',
                         'cleansers': 'contracts'}
            writer.writerow([table, id_, row['name'],
                             'e4_content_test.c::' + functions.get(table, table)])
subprocess.run([str(OUT / 'e4-capture')], cwd=ROOT, check=True)
print((OUT / 'e4-content.log').read_text().splitlines()[-1])

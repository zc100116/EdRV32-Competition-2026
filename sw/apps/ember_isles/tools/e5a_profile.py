#!/usr/bin/env python3
# File: e5a_profile.py; tech 4: real object host profiling.
# Description: Reproduce measurements with logs in build/.
# Clock domain: fixed 60 Hz simulation and host measurement.
"""tech 4: reproduce actual 1500-enemy/3000-projectile host simulation profiling."""
import csv
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[4]
APP = ROOT / 'sw/apps/ember_isles'
OUT = ROOT / 'build/ember_isles'
subprocess.run(['make', '-C', str(APP), 'e5a-stress',
                str(OUT / 'e5a-stress-profile'), '-j1'], check=True)
with (OUT / 'e5a-stress.csv').open() as stream:
    rows = [r for r in csv.DictReader(line for line in stream if line.startswith("STRESS,"))
            if r["STRESS"] == "STRESS"]
combat = [r for i, r in enumerate(rows) if i and r['combat'] != rows[i - 1]['combat']]
for name in ['enemies', 'shots']:
    values = [int(r[name]) for r in rows]
    print(f'{name}: initial={values[0]} final={values[-1]} '
          f'min={min(values)} peak={max(values)}')
values = [int(r['microseconds']) for r in combat]
print(f'combat ticks={len(combat)}; CPU us mean={sum(values) / len(values):.2f} '
      f'peak={max(values)}; hits={rows[-1]["hits"]} kills={rows[-1]["kills"]}')
profiles = []
for _ in range(100):
    process = subprocess.Popen([str(OUT / 'e5a-stress-profile')],
        env=dict(os.environ, GMON_OUT_PREFIX=str(OUT / 'e5a-gmon')),
        stdout=subprocess.DEVNULL)
    code = process.wait()
    if code:
        raise subprocess.CalledProcessError(code, process.args)
    profiles.append(f'e5a-gmon.{process.pid}')
subprocess.run(['gprof', '-s', 'e5a-stress-profile', *profiles], cwd=OUT, check=True)
with (OUT / 'e5a-profile.txt').open('w') as stream:
    subprocess.run(['gprof', '-b', 'e5a-stress-profile', 'gmon.sum'],
                   cwd=OUT, stdout=stream, check=True)
print(f'100 fresh diagnostic runs; gprof sampling/call graph: {OUT / "e5a-profile.txt"}')

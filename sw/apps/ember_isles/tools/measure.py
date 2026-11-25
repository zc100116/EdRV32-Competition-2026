#!/usr/bin/env python3
# File: measure.py; ember_isles tech 3-4 acceptance measurements.
# Run Spike, compare field summaries and report actual instruction budgets.
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / 'build/ember_isles'
with (OUT / 'spike.log').open('w') as log:
    subprocess.run(['spike', '--isa=rv32im_zicsr_zicntr', '--priv=m', '--pmpregions=0',
                    '--no-dm', '--disable-dtb', '-m0x80000000:0x40000000',
                    '--pc=0x80000000', str(OUT / 'ember_isles-spike.elf')],
                   stdout=log, stderr=subprocess.STDOUT, check=True)
pc = (OUT / 'pc.log').read_text().splitlines()
spike = (OUT / 'spike.log').read_text().splitlines()
pc_states = [line for line in pc if line.startswith('STATE,')]
spike_states = [line for line in spike if line.startswith('STATE,')]
assert pc_states == spike_states, 'PC/Spike field-by-field state mismatch'
assert pc_states, 'No replay summaries were produced'
assert ',stage=0,' in next(line for line in pc if line.startswith('RUN,')), (
    'Complete mode acceptance must start at stage zero')
rows = [list(map(int, line.split(',')[1:])) for line in spike
        if line.startswith('INST,') and not line.startswith('INST,frame')]
print(f'PC/Spike identical summaries: {len(pc_states)}')
for column, name, budget in [(1, 'simulation', 1200000), (2, 'presentation', 500000),
                             (3, 'audio', 150000), (4, 'total', 1850000)]:
    values = [row[column] for row in rows]
    average = sum(values) / len(values)
    maximum = max(values)
    print(f'{name}: average {average:.2f}, max {maximum} instret; '
          f'CPI1.3 average {average * 1.3:.2f}, max {maximum * 1.3:.2f} cycles; '
          f'budget {budget}')
pc_end = next(line for line in pc if line.startswith('END,'))
spike_end = next(line for line in spike if line.startswith('END,'))
assert pc_end == spike_end, 'PC/Spike final state mismatch'
assert pc_end.split(',')[2:4] == ['3', '10'] and pc_end.split(',')[5] == '0', (
    'Replay did not finish the coast arena at the exit')
print(pc_end)
print(spike_end)

print(next(line for line in pc if line.startswith('AUDIO,')))
perf = [list(map(int, line.split(',')[2:])) for line in pc
        if line.startswith('PERF,') and not line.startswith('PERF,frame')]
print('GPU PERF maxima: ' + ','.join(str(max(row[i] for row in perf)) for i in range(9)))

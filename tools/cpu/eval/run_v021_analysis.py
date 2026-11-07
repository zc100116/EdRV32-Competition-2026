#!/usr/bin/env python3
# File: run_v021_analysis.py; Spec: T-CPU-N-T3BE model decomposition; Clock: host.
# Separate decode, latency, occupancy, eligibility and system-resolution costs.
# Way prediction uses immediate per-set last-way training as an idealized estimate.
"""Run after preparing build/v017/input/{coremark,vision,render}."""
import json
from pathlib import Path

from ooo_model import memory_trace
from pipe_model import program_and_trace, simulate
from run_frontend_t2_eval import IcacheProbe
from run_pipeline_cut_eval import BASE, MemoryProbe

C1 = dict(decode_split=True)
C13 = dict(C1, load_latency=3)
CAPTURE = dict(C13, memory_capture=True, capture_early='legacy', csr_latency=2,
               system_capture=False)
EXCLUDE = dict(CAPTURE, capture_early='conservative')
CSR3 = dict(EXCLUDE, csr_latency=3)
SYSTEM = dict(CSR3, system_capture=True)
REGISTERED = dict(SYSTEM, capture_early='registered')
CONFIGS = {
    'v0.20': {}, 'C1': C1, 'load3-only': dict(load_latency=3), 'C1-load3': C13,
    'capture-records': CAPTURE, 'capture-exclusion': EXCLUDE,
    'capture-csr3': CSR3, 'capture-system': SYSTEM, 'registered-early': REGISTERED,
    'C3-actual': dict(load_latency=3, memory_capture=True),
    'way-prediction': dict(load_latency=2, memory_capture=True),
    'C1-way-prediction': dict(decode_split=True, load_latency=2, memory_capture=True),
}


class WayProbe(MemoryProbe):
    """Two fixed ways, true-LRU allocation; last resolved way predicts the next read.

    One global repair cycle on a wrong ordinary-hit prediction. Predictor training
    is immediate here, making this an estimate rather than a timed implementation.
    Early-success loads still use their ordinary two-way validated early result.
    A failed early query repairs in M2, adding the same extra cycle as C3.
    """
    def __init__(self, addresses):
        super().__init__(addresses, repair=1)
        self.tags = [[None, None] for _ in range(512)]
        self.last = [0] * 512
        self.way_hits = self.way_errors = 0

    def query(self, record, active, consumers=()):
        delay = super().query(record, active, consumers)
        inst = record.instruction
        if inst.kind not in {'load', 'store'}:
            return delay
        address = self.addresses[record.trace_index]
        if not (0x10000000 <= address < 0x10010000 or
                0x80000000 <= address < 0xc0000000):
            return delay
        line = address >> 5
        index = line & 511
        ways = self.tags[index]
        hit = line in ways
        guess = self.last[index]
        if hit:
            way = ways.index(line)
        else:
            way = ways.index(None) if None in ways else 1 - self.last[index]
            ways[way] = line
        wrong = inst.kind == 'load' and not record.early_load and hit and guess != way
        self.way_hits += active and inst.kind == 'load' and not record.early_load and hit
        self.way_errors += active and wrong
        self.last[index] = way
        return delay + int(wrong)


def evaluate(workload, names, destination):
    directory = Path('build/v017/input') / workload
    program, symbols, trace = program_and_trace(directory)
    addresses = memory_trace(directory, program, trace)
    with Path(destination).open('w') as output:
        for name in names:
            options = CONFIGS[name]
            probe = WayProbe(addresses) if name in {'way-prediction', 'C1-way-prediction'} else MemoryProbe(
                addresses, repair=int(options.get('load_latency', 2) == 3))
            result = simulate(program, trace, symbols['start_time'], symbols['stop_time'],
                              'V3s', **dict(BASE, **options), frontend_probe=IcacheProbe(1),
                              frontend_registered_margin=True, memory_probe=probe)
            row = dict(workload=workload, name=name, options=options, **result,
                       repairs=probe.repairs, dc_misses=probe.misses,
                       devices=probe.devices)
            if name in {'way-prediction', 'C1-way-prediction'}:
                row.update(way_hits=probe.way_hits, way_errors=probe.way_errors)
            output.write(json.dumps(row) + '\n')
            output.flush()
            print(workload, name, result['cycles'], flush=True)


def main():
    output = Path('build/t3be/decomposition')
    output.mkdir(parents=True, exist_ok=True)
    for workload in ('coremark', 'vision', 'render'):
        evaluate(workload, CONFIGS, output / (workload + '.jsonl'))
    print_summary(output)

# Card 62: PDS 2022.2-SP6.1 / PG2L200H-6 / 150 MHz / slow setup.
# Group removal is an optimistic ceiling, not timing of a new implementation.
SLACK62 = {'A1': -.752, 'A2': -.720, 'A3': -.625,
           'B1': -.501, 'B2': -.394, 'B3': -.318,
           'C1': -.681, 'C2': -.177, 'D1': -.468, 'D2': -.391,
           'E1': -.485, 'E2': -.325, 'F-div': -.341, 'F-W': -.402,
           'F-HPM': -.365, 'F-update': -.314}
EQUIVALENT_TARGETS = {'A1', 'A2', 'A3', 'C1', 'C2',
                      'F-div', 'F-W', 'F-HPM', 'F-update'}


def frequency_ceiling(name, frontend_data_fixed=False):
    removed = set(EQUIVALENT_TARGETS)
    if name in {'C1', 'registered-early', 'C1-way-prediction'}:
        removed.add('E1')
    if name in {'C3-actual', 'registered-early', 'way-prediction', 'C1-way-prediction'}:
        removed.update(('B1', 'B2', 'B3'))
    if frontend_data_fixed:
        removed.update(('D1', 'D2'))
    group = min((g for g in SLACK62 if g not in removed), key=SLACK62.get)
    return group, 1000 / (6.667 - SLACK62[group])


def print_summary(output):
    rows = [json.loads(line) for line in (output / 'coremark.jsonl').read_text().splitlines()]
    by_name = {row['name']: row for row in rows}
    for name in ('v0.20', 'C1', 'C3-actual', 'registered-early', 'way-prediction', 'C1-way-prediction'):
        cycles = by_name[name]['cycles']
        group, frequency = frequency_ceiling(name)
        fixed_group, fixed_frequency = frequency_ceiling(name, True)
        print(f'{name}: {cycles} cycles; remaining {group}, {frequency:.3f} MHz, '
              f'score {10000000 / cycles * frequency:.3f}; '
              f'D1/D2 assumed closed: {fixed_group}, {fixed_frequency:.3f} MHz, '
              f'score {10000000 / cycles * fixed_frequency:.3f}')


if __name__ == '__main__':
    main()

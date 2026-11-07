#!/usr/bin/env python3
# File: run_pipeline_cut_eval.py; Spec: T-CPU-N-CUT; Clock: host.
# Replay v0.20 plus v0.19 frontend costs, then individual and combined pipeline cuts.
# D$ probes add only incremental cut costs; original bus/refill time remains absent.
"""Source edrv32 env; flock /tmp/edrv32-sim.lock python3 tools/cpu/eval/run_pipeline_cut_eval.py."""
import json
from pathlib import Path

from ooo_model import memory_trace
from pipe_model import program_and_trace, simulate
from run_frontend_t2_eval import IcacheProbe

BASE = dict(btb_entries=128, gshare_entries=4096, ras_entries=4, gshare_pc_shift=2,
            e_penalty=4, d_penalty=3, mul_latency=4, registered_control=True,
            early_address='v017', direction_predictor='tournament', second_level=True)
C1 = dict(decode_split=True)
C2 = dict(branch_register=True)
C3 = dict(load_latency=3)
C4 = dict(registered_memory=True)
C5 = dict(alu_latency=2)
C6 = dict(taken_bubble=1, line_predictor=True)
CONFIGS = {
    'S2': dict(direction_predictor=None, second_level=False),
    'tournament': {}, 'baseline': {},
    'C1': C1, 'C2': C2, 'C3': C3, 'C4': C4,
    'C5-shift': dict(shift_latency=2),
    'C5-shift-compare': dict(shift_latency=2, compare_latency=2), 'C5-all': C5,
    'C6-bubble': dict(taken_bubble=1), 'C6-line': C6,
    'C1+C2': dict(C1, **C2), 'C1+C2+C3': dict(C1, **C2, **C3),
    'C3+C4': dict(C3, **C4), 'C1+C3+C4': dict(C1, **C3, **C4),
    'C1+C2+C3+C4+C5+C6': dict(C1, **C2, **C3, **C4, **C5, **C6),
}


class MemoryProbe:
    """cache-spec 2.1/2.2: 512 sets, two ways, 32-byte lines, write allocate.

    C4 chooses registered freeze: every miss/device adds one global hold cycle;
    no instruction is flushed/replayed. C3 adds one repair cycle on early failure.
    The model omits store-buffer/maintenance failures and all baseline bus latency.
    """
    def __init__(self, addresses, registered=False, repair=0):
        self.addresses = addresses
        self.registered = registered
        self.repair = repair
        self.sets = [[] for _ in range(512)]
        self.misses = self.devices = self.early_failures = self.repairs = 0

    def query(self, record, active, consumers=()):
        inst = record.instruction
        if inst.kind not in {'load', 'store'}:
            return 0
        address = self.addresses[record.trace_index]
        device = not (0x10000000 <= address < 0x10010000 or
                      0x80000000 <= address < 0xc0000000)
        miss = False
        if not device:
            line = address >> 5
            ways = self.sets[line & 511]
            miss = line not in ways
            if miss:
                if len(ways) == 2:
                    ways.pop(0)
            else:
                ways.remove(line)
            ways.append(line)
        failed = record.early_load and (miss or device)
        self.misses += active and miss
        self.devices += active and device
        self.early_failures += active and failed
        dependent = failed and any(inst.rd and inst.rd in r.instruction.sources
                                   for r in consumers)
        self.repairs += active and dependent
        return int(self.registered and (miss or device)) + self.repair * dependent


def main():
    output = Path('build/pipeline-cut/results.jsonl')
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('w') as stream:
        for workload in ('coremark', 'vision', 'render'):
            directory = Path('build/v017/input') / workload
            program, symbols, trace = program_and_trace(directory)
            addresses = memory_trace(directory, program, trace)
            for name, changes in CONFIGS.items():
                if workload != 'coremark' and name in {'S2', 'tournament'}:
                    continue
                options = dict(BASE, **changes)
                registered = options.pop('registered_memory', False)
                original = name in {'S2', 'tournament'}
                probe = MemoryProbe(addresses, registered, int(options.get('load_latency', 2) == 3))
                result = simulate(program, trace, symbols['start_time'], symbols['stop_time'],
                                  'V3s', **options,
                                  frontend_probe=None if original else IcacheProbe(1),
                                  frontend_registered_margin=not original,
                                  memory_probe=None if original else probe)
                row = dict(workload=workload, name=name, **result,
                           dc_misses=probe.misses, devices=probe.devices,
                           early_failures=probe.early_failures, repairs=probe.repairs)
                line = json.dumps(row)
                stream.write(line + '\n')
                stream.flush()
                print(f'{workload} {name}: {result["cycles"]}', flush=True)


# Card 60 slow setup, PDS 2022.2-SP6.1, PG2L200H-6, 150 MHz.
# Source: origin/win/20261105-60-cpu-v018-tournament-probe,
# tasks/win/20261105-60-cpu-v018-tournament-probe/artifacts/R1/timing_setup_fail_all.txt.
# P9 is absent in that endpoint export and never determines these maxima.
SLACK60 = {'P1': -1.745, 'P2': -2.157, 'P3': -2.090, 'P4': -2.102,
           'P5': -0.854, 'P6': -1.773, 'P7': -2.505, 'P8': -2.318, 'P10': -0.811}
REMOVED = {'C1': {'P3', 'P4'}, 'C2': {'P1'}, 'C3': {'P6'}, 'C4': {'P2'},
           'C5-all': {'P5'}, 'C6-bubble': {'P7'}, 'C6-line': {'P7'}}


def ceiling(name, frontend_fixed=False):
    """Optimistic group excision only; new split paths are not timed by this model."""
    removed = {'P7', 'P8'} if frontend_fixed else set()
    for cut in name.split('+'):
        key = {'C5': 'C5-all', 'C6': 'C6-line'}.get(cut, cut)
        removed |= REMOVED.get(key, set())
    group = min((g for g in SLACK60 if g not in removed), key=SLACK60.get)
    return group, SLACK60[group], 1000 / (6.667 - SLACK60[group])


def print_tables():
    """Reprint the design-record numbers from the completed replay, without simulation."""
    rows = [json.loads(line) for line in Path('build/pipeline-cut/results.jsonl').read_text().splitlines()]
    by_key = {(r['workload'], r['name']): r for r in rows}
    base = by_key['coremark', 'baseline']['cycles']
    base_score = 10000000 / base * ceiling('baseline')[2]
    for name in CONFIGS:
        if name in {'S2', 'tournament'}:
            continue
        cells = []
        for workload in ('coremark', 'vision', 'render'):
            cycles = by_key[workload, name]['cycles']
            reference = by_key[workload, 'baseline']['cycles']
            cells.append(f'{cycles:,} ({(cycles / reference - 1) * 100:+.2f}%)')
        print('| ' + name + ' | ' + ' | '.join(cells) + ' |')
    print('Frequency and score (raw / frontend P7+P8 assumed fixed):')
    for name in CONFIGS:
        if name in {'S2', 'tournament'}:
            continue
        cm = 10000000 / by_key['coremark', name]['cycles']
        group, slack, frequency = ceiling(name)
        fixed_group, fixed_slack, fixed_frequency = ceiling(name, True)
        score = cm * frequency
        print(f'| {name} | {group}/{slack:.3f}/{frequency:.2f} | '
              f'{fixed_group}/{fixed_slack:.3f}/{fixed_frequency:.2f} | {cm:.3f} | '
              f'{score:.1f} ({(score / base_score - 1) * 100:+.2f}% / '
              f'{(score / (4.354 * 125) - 1) * 100:+.2f}%) |')


if __name__ == '__main__':
    main()
    print_tables()

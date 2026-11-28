#!/usr/bin/env python3
# File: run_store_queue.py; Spec: cpu-v2 v0.3 3.7/C11; Clock: host.
# Scan cacheable store beats with fixed single/dual completion windows of 8/16.
# Reuse M01 Zba traces and emit all generated measurements under build/.
"""python3 tools/cpu/eval/run_store_queue.py coremark [--entries 0 2 4]."""
import argparse
import json
from pathlib import Path

from ooo_model import memory_trace
from pipe_model import program_and_trace, simulate
from run_frontend_t2_eval import IcacheProbe
from run_v2_round2 import divider_cycles
from run_v2_round4 import BASES
from v2_round4_structures import RamTage


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('workload', choices=('coremark', 'vision', 'render'))
    parser.add_argument('--entries', type=int, nargs='+', choices=(0, 2, 4), default=[0, 2, 4])
    args = parser.parse_args()
    directory = Path('build/cpu-v2/isa/zba') / args.workload
    program, symbols, trace = program_and_trace(directory)
    addresses = memory_trace(directory, program, trace)
    output = Path('build/cpu2-store-queue') / (args.workload + '.jsonl')
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('w') as stream:
        for base, mode, window in (('small', 'early-div', 8), ('full', 'radix4-early', 16)):
            divs = divider_cycles(directory, program, trace, mode, complete_schedule=True)
            for entries in args.entries:
                options = dict(BASES[base])
                if base == 'full':
                    options.update(direction_predictor=RamTage(4, 512), second_level=True,
                                   unaligned_fetch=True)
                result = simulate(program, trace, symbols['start_time'], symbols['stop_time'],
                                  'V3s', **options, division_cycles=divs,
                                  frontend_probe=IcacheProbe(1), frontend_registered_margin=True,
                                  completion_entries=window, completion_addresses=addresses,
                                  store_queue_model=True, store_queue_entries=entries)
                result.update(workload=args.workload, base=base)
                if args.workload == 'coremark':
                    result['coremark_per_mhz'] = 1e7 / result['cycles']
                stream.write(json.dumps(result) + '\n')
                stream.flush()
                print(base, entries, result['cycles'], result['store_queue_load_waits'],
                      result['store_queue_load_wait_cycles'], flush=True)


if __name__ == '__main__':
    main()

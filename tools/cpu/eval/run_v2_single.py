#!/usr/bin/env python3
# File: run_v2_single.py; Spec: CPU v2 2.2/7; Clock: host.
# Replay the fixed small + Zba configuration using round-four inputs and budgets.
# Keep one workload per process; generated results stay in build/.
"""Source edrv32 env; python3 tools/cpu/eval/run_v2_single.py coremark."""
import argparse
import json
import math
from pathlib import Path

from ooo_model import memory_trace
from pipe_model import program_and_trace, simulate
from run_frontend_t2_eval import IcacheProbe
from run_v2_round2 import divider_cycles
from run_v2_round4 import BASES
from v2_round4_estimates import estimate


def resources():
    area = estimate('small', 'rf-async')
    # The small series has no HPM; restore two 64-bit counters (HPM3/4).
    # Zba adds the round-four 128-LUT ALU input budget, with no extra FF.
    area['lut'] += 128 + 128
    area['ff'] += 128
    area['clm'] = math.ceil(max(area['lut'] / 4, area['ff'] / 8) / .70)
    return {key: area[key] for key in ('lut', 'ff', 'clm', 'drm', 'apm')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('workload', choices=('coremark', 'vision', 'render'))
    parser.add_argument('--completion-entries', type=int, default=0)
    parser.add_argument('--completion-same-cycle-credit', action='store_true')
    parser.add_argument('--completion-head-authorization', action='store_true')
    args = parser.parse_args()
    directory = Path('build/cpu-v2/isa/zba') / args.workload
    program, symbols, trace = program_and_trace(directory)
    addresses = memory_trace(directory, program, trace) if (args.completion_entries or
                                                               args.completion_head_authorization) else None
    divs = divider_cycles(directory, program, trace, 'early-div', complete_schedule=True)
    result = simulate(program, trace, symbols['start_time'], symbols['stop_time'],
                      'V3s', **BASES['small'], division_cycles=divs,
                      completion_entries=args.completion_entries, completion_addresses=addresses,
                      completion_same_cycle_credit=args.completion_same_cycle_credit,
                      completion_head_authorization=args.completion_head_authorization,
                      frontend_probe=IcacheProbe(1), frontend_registered_margin=True)
    instructions = trace.index(symbols['stop_time']) - trace.index(symbols['start_time'])
    result.update(workload=args.workload, name='single-small-zba', instructions=instructions,
                  ipc=instructions / result['cycles'], resources=resources())
    if args.workload == 'coremark':
        result['coremark_per_mhz'] = 1e7 / result['cycles']
    suffix = f'-n{args.completion_entries}' if args.completion_entries else ''
    output = Path('build/cpu-v2-single') / (args.workload + suffix + '.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result), flush=True)


if __name__ == '__main__':
    main()

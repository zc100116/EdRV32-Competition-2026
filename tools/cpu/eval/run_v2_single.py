#!/usr/bin/env python3
# File: run_v2_single.py; Spec: CPU v2 2.2/7; Clock: host.
# Replay the fixed small + Zba configuration using round-four inputs and budgets.
# Keep one workload per process; generated results stay in build/.
"""Source edrv32 env; python3 tools/cpu/eval/run_v2_single.py coremark."""
import argparse
import json
import math
from pathlib import Path

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
    args = parser.parse_args()
    directory = Path('build/cpu-v2/isa/zba') / args.workload
    program, symbols, trace = program_and_trace(directory)
    divs = divider_cycles(directory, program, trace, 'early-div')
    result = simulate(program, trace, symbols['start_time'], symbols['stop_time'],
                      'V3s', **BASES['small'], division_cycles=divs,
                      frontend_probe=IcacheProbe(1), frontend_registered_margin=True)
    instructions = trace.index(symbols['stop_time']) - trace.index(symbols['start_time'])
    result.update(workload=args.workload, name='single-small-zba', instructions=instructions,
                  ipc=instructions / result['cycles'], resources=resources())
    if args.workload == 'coremark':
        result['coremark_per_mhz'] = 1e7 / result['cycles']
    output = Path('build/cpu-v2-single') / (args.workload + '.json')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result), flush=True)


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
# File: run_completion_window.py; Spec: cpu-v2 5.1/5.6; Clock: host.
# Scan only completion capacity on the fixed single-small / dual-full Zba models.
# Replay one workload at a time and keep generated results under build/.
"""Source edrv32 env; python3 tools/cpu/eval/run_completion_window.py coremark."""
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
    args = parser.parse_args()
    directory = Path('build/cpu-v2/isa/zba') / args.workload
    program, symbols, trace = program_and_trace(directory)
    addresses = memory_trace(directory, program, trace)
    output = Path('build/cpu2-completion-window') / (args.workload + '.jsonl')
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('w') as stream:
        for base, mode in (('small', 'early-div'), ('full', 'radix4-early')):
            divs = divider_cycles(directory, program, trace, mode, complete_schedule=True)
            cases = [(False, False, None), (True, False, None)] + [
                (head, early, n) for head in (False, True) for early in (False, True)
                for n in (4, 8, 12, 16)]
            for head, same_cycle, entries in cases:
                options = dict(BASES[base])
                if base == 'full':
                    options.update(direction_predictor=RamTage(4, 512), second_level=True,
                                   unaligned_fetch=True)
                result = simulate(program, trace, symbols['start_time'], symbols['stop_time'],
                                  'V3s', **options, division_cycles=divs,
                                  frontend_probe=IcacheProbe(1), frontend_registered_margin=True,
                                  completion_entries=entries, completion_addresses=addresses,
                                  completion_same_cycle_credit=same_cycle,
                                  completion_head_authorization=head)
                result.update(workload=args.workload, base=base, capacity=entries,
                              credit_same_cycle=same_cycle, head_authorization=head)
                if args.workload == 'coremark':
                    result['coremark_per_mhz'] = 1e7 / result['cycles']
                stream.write(json.dumps(result) + '\n')
                stream.flush()
                print(base, entries, head, same_cycle, result['cycles'], flush=True)


if __name__ == '__main__':
    main()

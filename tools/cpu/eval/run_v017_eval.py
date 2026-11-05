#!/usr/bin/env python3
# File: run_v017_eval.py; Spec: cpu-spec v0.17 2.3, 4.4, 4.9-4.11; Clock: host.
# Replay S0-S3 and individual next-round options sequentially on three warm traces.
"""Inputs copied to build/v017/input/{coremark,vision,render}; exactly one model at a time."""
import json
from pathlib import Path

from ipc_structures import FUSIONS
from pipe_model import program_and_trace, simulate

OUT = Path('build/v017')
S1 = dict(e_penalty=4, d_penalty=3, mul_latency=4, registered_control=True)
S2 = dict(S1, early_address='v017')
S3 = dict(S2, lcb='v017')
CONFIGS = {
    'S0': {}, 'S1': S1, 'S2': S2, 'S3': S3,
    'S3-split-lcb': dict(S3, lcb_split=True),
    'S2-old-address1': dict(S1, early_address=1),
    'tournament': dict(S3, direction_predictor='tournament', second_level=True),
    'tournament-confident': dict(S3, direction_predictor='tournament-confident',
                                second_level=True),
    'fusion-all': dict(S3, fusion=FUSIONS),
    'fusion-subset': dict(S3, fusion=('addi-andi', 'srli-or', 'slli-add')),
    'serial-simple': dict(S3, serial_alu='simple'),
    'dual-lsu': dict(S3, dual_lsu=True),
}


def main():
    for workload in ('coremark', 'vision', 'render'):
        program, symbols, trace = program_and_trace(OUT / 'input' / workload)
        with (OUT / (workload + '.jsonl')).open('w') as output:
            for name, options in CONFIGS.items():
                result = simulate(program, trace, symbols['start_time'], symbols['stop_time'],
                                  'V3s', btb_entries=128, gshare_entries=4096,
                                  ras_entries=4, gshare_pc_shift=2, **options)
                row = dict(workload=workload, name=name, options=options, **result)
                line = json.dumps(row)
                output.write(line + '\n')
                output.flush()
                print(line, flush=True)


if __name__ == '__main__':
    main()

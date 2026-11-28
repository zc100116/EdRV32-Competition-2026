#!/usr/bin/env python3
# File: run_v2_round3.py; Spec: C2-I3 architecture task; Clock: host.
# Counterfactual ceilings and explicit sequential-ALU, issue and fetch experiments.
# Preserve the original trace and B0 model; all results are model estimates.
"""python3 tools/cpu/eval/run_v2_round3.py coremark [--names ...]."""
import argparse
import json
from pathlib import Path

from analyze import CONTROL
from pipe_model import program_and_trace, simulate
from run_frontend_t2_eval import IcacheProbe
from run_v2_round2 import CONFIGS as SECOND, divider_cycles

IDEALS = {
    'prediction': dict(perfect_prediction=True),
    'load': dict(load_latency=1),
    'raw': dict(relax_raw=True),
    'pair': dict(ideal_pairing=True),
    'second': dict(perfect_frontend=True),
    'mul': dict(mul_latency=1),
}
IDEALS['all'] = {k: v for options in IDEALS.values() for k, v in options.items()}
EXPERIMENTS = {
    'base': {},
    'late-alu': dict(late_execute='alu', late_pair=True),
    'late-branch': dict(late_execute='alu_branch', late_pair=True),
    'lsu-slots': dict(slot1_lsu=True),
    'mul-slots': dict(slot1_mul=True),
    'dual-mul': dict(slot1_mul='dual'),
    'branch-one': {},  # V3s already supports both slots with one control/group.
    'branch-two': dict(control_slots=2, slot1_control=True),
    'control-one': dict(slot1_control=True),
    'dual-lsu': dict(dual_lsu=True),
    'fetch128': dict(fetch_bytes=16),
    'queue8': dict(queue_depth=8),
    'queue16': dict(queue_depth=16),
    'fetch128-q16': dict(fetch_bytes=16, queue_depth=16),
    'combo-alu': dict(late_execute='alu', late_pair=True, slot1_mul=True),
    'combo-branch': dict(late_execute='alu_branch', late_pair=True, slot1_mul=True),
    'combo-fetch': dict(late_execute='alu', late_pair=True, slot1_mul=True, fetch_bytes=16),
    'combo-queue': dict(late_execute='alu', late_pair=True, slot1_mul=True, queue_depth=8),
    'combo-lsu': dict(late_execute='alu', late_pair=True, slot1_mul=True, dual_lsu=True),
    'combo-branch-queue': dict(late_execute='alu_branch', late_pair=True,
                               slot1_mul=True, queue_depth=8),
    'combo-branch-lsu': dict(late_execute='alu_branch', late_pair=True,
                             slot1_mul=True, dual_lsu=True),
    'combo-control': dict(late_execute='alu_branch', late_pair=True, slot1_mul=True,
                          slot1_control=True, queue_depth=8),
    'combo-control-lsu': dict(late_execute='alu_branch', late_pair=True, slot1_mul=True,
                              slot1_control=True, queue_depth=8, dual_lsu=True),
    'combo-all': dict(late_execute='alu_branch', late_pair=True, slot1_mul=True,
                     dual_lsu=True, fetch_bytes=16, queue_depth=16),
}
CONFIGS = {}
for base in ('default2-early-div', 'full2-no-late'):
    for name, options in EXPERIMENTS.items():
        CONFIGS[base + '/' + name] = dict(SECOND[base], **options)
    for name, options in IDEALS.items():
        CONFIGS[base + '/ideal-' + name] = dict(SECOND[base], **options)


def frontend_alignment(program, trace, begin, end):
    """Count architectural taken targets at the last word of each fetch width."""
    counts = dict(taken_controls=0, target_tail64=0, target_tail128=0)
    for index in range(trace.index(begin), trace.index(end)):
        instruction = program[trace[index]]
        target = trace[index + 1]
        if instruction.kind in CONTROL and (
                instruction.kind != 'branch' or target != instruction.pc + instruction.size):
            counts['taken_controls'] += 1
            counts['target_tail64'] += target % 8 == 4
            counts['target_tail128'] += target % 16 == 12
    return counts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('workload', choices=('coremark', 'vision', 'render'))
    parser.add_argument('--names', nargs='+', choices=CONFIGS, default=list(CONFIGS))
    parser.add_argument('--input-root', type=Path, default=Path('build/v017/input'))
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    directory = args.input_root / args.workload
    program, symbols, trace = program_and_trace(directory)
    instructions = trace.index(symbols['stop_time']) - trace.index(symbols['start_time'])
    alignment = frontend_alignment(program, trace, symbols['start_time'], symbols['stop_time'])
    divs = {mode: divider_cycles(directory, program, trace, mode)
            for mode in ('early-div', 'radix4-early')}
    output = args.output or Path('build/cpu-v2-round3') / (args.workload + '.jsonl')
    output.parent.mkdir(parents=True, exist_ok=True)
    cache = {}
    with output.open('w') as stream:
        for name in args.names:
            options = dict(CONFIGS[name])
            mode = 'early-div' if name.startswith('default') else 'radix4-early'
            options['division_cycles'] = divs[mode]
            key = (mode, tuple(sorted(CONFIGS[name].items())))
            if key not in cache:
                if name.endswith('/ideal-second'):
                    # Freeze baseline dynamic predictions: an ideal supplier must not
                    # acquire different tournament misses just by querying at D instead of F.
                    captured = {}
                    baseline = dict(SECOND[name.split('/')[0]], division_cycles=divs[mode])
                    simulate(program, trace, symbols['start_time'], symbols['stop_time'],
                             'V3s', **baseline, frontend_probe=IcacheProbe(1),
                             frontend_registered_margin=True, prediction_capture=captured)
                    options['fixed_predictions'] = captured
                cache[key] = simulate(
                    program, trace, symbols['start_time'], symbols['stop_time'],
                    'V3s', **options, frontend_probe=IcacheProbe(1),
                    frontend_registered_margin=True)
            # Ideal pairing can retire stop_time with the preceding instruction.
            # Normalize IPC to the exact trace window, not the old group HPM boundary.
            result = dict(cache[key], instructions=instructions,
                          ipc=instructions / cache[key]['cycles'])
            stream.write(json.dumps(dict(workload=args.workload, name=name,
                                         alignment=alignment, **result)) + '\n')
            stream.flush()
            print(args.workload, name, result['cycles'], flush=True)


if __name__ == '__main__':
    main()

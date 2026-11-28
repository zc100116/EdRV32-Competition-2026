#!/usr/bin/env python3
# File: run_v2_round2.py; Spec: C2-I2 architecture evaluation; Clock: host.
# Replay one workload per process, preserving B0 defaults and exclusive CPI accounting.
# Operand-based divider latencies come from architectural Spike register commits.
"""Source edrv32 env; python3 tools/cpu/eval/run_v2_round2.py coremark."""
import argparse
import json
import re
from pathlib import Path

from ooo_model import memory_trace
from pipe_model import program_and_trace, simulate
from run_frontend_t2_eval import IcacheProbe
from run_pipeline_cut_eval import BASE, MemoryProbe
from run_v2_eval import CONFIGS as FIRST, V5, cpi_stack

B0_FIX = dict(BASE, decode_split=True, e_penalty=5, d_penalty=4, taken_bubble=1)
A = dict(V5, early_address='rf_wb')
CONFIGS = {
    'B0': BASE, 'B0-fix': B0_FIX,
    'B0-fix-predecode': dict(BASE, e_penalty=5, d_penalty=4, taken_bubble=1),
    'B0-fix-parallel': dict(BASE), 'B0-fix-parallel-div': dict(BASE),
    'V5-default': FIRST['V5-default'], 'V5-ip-full': FIRST['V5-ip-full'],
    'V5': V5, 'V5-id-address': A,
    'V5-late-alu': dict(V5, late_execute='alu'),
    'V5-late-branch': dict(V5, late_execute='alu_branch'),
    'V5-pht-drm': dict(V5, taken_bubble=1, e_penalty=3, d_penalty=2),
    'B0-radix4': BASE, 'B0-early-div': BASE, 'B0-radix4-early': BASE,
    'V5-radix4': V5, 'V5-early-div': V5, 'V5-radix4-early': V5,
    'B0-fix-best': dict(BASE, e_penalty=5, d_penalty=4, taken_bubble=1),
    'default2': dict(A), 'default2-early-div': dict(A),
    'full2': dict(A, late_execute='alu_branch', direction_predictor='tournament',
                  second_level=True, ras_entries=8),
    'full2-no-late': dict(A, direction_predictor='tournament',
                          second_level=True, ras_entries=8),
    'small2': dict(A, issue_width=1, btb_entries=64),
    'small2-early-div': dict(A, issue_width=1, btb_entries=64),
}


def divider_cycles(directory, program, trace, mode):
    regs = [0] * 32
    cycles = {}
    index = 0
    commit = re.compile(r'core\s+0:\s+3 0x([0-9a-f]+) \(0x[0-9a-f]+\)(.*)')
    write = re.compile(r'\bx(\d+)\s+0x([0-9a-f]+)')
    with (directory / 'spike.log').open() as log:
        for line in log:
            match = commit.match(line)
            if not match:
                continue
            pc = int(match[1], 16)
            inst = program[pc]
            if inst.kind == 'div':
                a, b = regs[(inst.bits >> 15) & 31], regs[(inst.bits >> 20) & 31]
                signed = ((inst.bits >> 12) & 7) in (4, 6)
                if signed:
                    a = abs(a - (1 << 32) if a >> 31 else a)
                    b = abs(b - (1 << 32) if b >> 31 else b)
                steps = max(0, a.bit_length() - b.bit_length() + 1)
                if b == 0:
                    steps = 0
                radix4 = mode in ('radix4', 'radix4-early')
                if mode == 'radix4':
                    steps = 32
                cycles[index] = 1 + ((steps + 1) // 2 if radix4 else steps)
            for reg, value in write.findall(match[2]):
                if int(reg):
                    regs[int(reg)] = int(value, 16)
            index += 1
            if index == len(trace):
                break
    return cycles


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('workload', choices=('coremark', 'vision', 'render'))
    parser.add_argument('--input-root', type=Path, default=Path('build/v017/input'))
    parser.add_argument('--names', nargs='+', choices=CONFIGS, default=list(CONFIGS))
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    directory = args.input_root / args.workload
    output = args.output or Path('build/cpu-v2-round2') / (args.workload + '.jsonl')
    output.parent.mkdir(parents=True, exist_ok=True)
    program, symbols, trace = program_and_trace(directory)
    addresses = memory_trace(directory, program, trace)
    divs = {mode: divider_cycles(directory, program, trace, mode)
            for mode in ('radix4', 'early-div', 'radix4-early')}
    with output.open('w') as stream:
        for name in args.names:
            options = dict(CONFIGS[name])
            mode = next((m for m in divs if name.endswith('-' + m)), None)
            if name in ('B0-fix-best', 'B0-fix-parallel-div', 'default2', 'full2',
                        'full2-no-late', 'small2'):
                mode = 'radix4-early'
            if mode:
                options['division_cycles'] = divs[mode]
            icache = IcacheProbe(1)
            memory = MemoryProbe(addresses)
            result = simulate(program, trace, symbols['start_time'], symbols['stop_time'],
                              'V3s', **options, frontend_probe=icache,
                              frontend_registered_margin=True, memory_probe=memory)
            row = dict(workload=args.workload, name=name, **result,
                       dc_misses=memory.misses, **cpi_stack(result, icache.roi_misses))
            stream.write(json.dumps(row) + '\n')
            stream.flush()
            print(args.workload, name, result['cycles'], flush=True)


if __name__ == '__main__':
    main()

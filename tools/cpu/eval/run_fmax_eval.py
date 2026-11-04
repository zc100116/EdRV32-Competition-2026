#!/usr/bin/env python3
# File: run_fmax_eval.py; Spec: cpu-spec 4.1-4.4; Clock: host.
# Evaluate timing cuts against the tuned, hit-only CoreMark trace.
"""Source the toolchain environment; prepare with run_predictor_eval.py first."""
from concurrent.futures import ProcessPoolExecutor
from collections import Counter, defaultdict
import argparse
import json
from pathlib import Path
import subprocess

from analyze import DISASM
from pipe_model import program_and_trace, simulate
from run_predictor_eval import OUT

CONFIGS = {
    'base': {},
    'redirect': {'e_penalty': 4, 'd_penalty': 3},
    'mul4': {'mul_latency': 4},
    'load3': {'load_latency': 3},
    'taken1': {'taken_bubble': 1},
    'A': {'e_penalty': 4, 'd_penalty': 3, 'mul_latency': 4},
    'B': {'e_penalty': 4, 'd_penalty': 3, 'mul_latency': 4,
          'load_latency': 3, 'taken_bubble': 1},
}
LIMITS = {
    'perfect_prediction': {'perfect_prediction': True},
    'perfect_frontend': {'perfect_frontend': True},
    'all_slot1_types': {'all_slot1_types': True},
    'relax_raw': {'relax_raw': True},
    'load1': {'load_latency': 1},
}


def load():
    global PROGRAM, SYMBOLS, TRACE
    PROGRAM, SYMBOLS, TRACE = program_and_trace(OUT / 'tuned')


def evaluate(item):
    name, options = item
    result = simulate(PROGRAM, TRACE, SYMBOLS['start_time'], SYMBOLS['stop_time'],
                      'V3s', btb_entries=128, gshare_entries=4096,
                      ras_entries=4, gshare_pc_shift=2, **options)
    return dict(name=name, options=options, coremark_per_mhz=10000000 / result['cycles'],
                **result)


def trace_statistics():
    program, symbols, trace = program_and_trace(OUT / 'tuned')
    trace = trace[trace.index(symbols['start_time']):trace.index(symbols['stop_time'])]
    disasm = subprocess.check_output(['riscv-none-elf-objdump', '-d', '-M',
                                     'no-aliases,numeric', str(OUT / 'tuned/coremark.elf')],
                                    text=True)
    names = {int(m[1], 16): m[3] for line in disasm.splitlines()
             if (m := DISASM.match(line))}
    pairs, load_use, raw_pairs, loops = Counter(), Counter(), Counter(), Counter()
    branches = defaultdict(list)
    for pc, next_pc in zip(trace, trace[1:]):
        older, younger = program[pc], program[next_pc]
        pairs[(pc, next_pc)] += 1
        if older.rd and older.rd in younger.sources:
            raw_pairs[(names[pc], names[next_pc])] += 1
            if older.kind == 'load':
                load_use[(names[pc], names[next_pc])] += 1
        if older.kind == 'branch':
            taken = next_pc != pc + older.size
            branches[pc].append(taken)
            if taken and next_pc < pc:
                loops[(next_pc, pc)] += 1
    loop_rows = [dict(start=hex(a), end=hex(b), backedges=n,
                      static_instructions=sum(a <= pc <= b for pc in program))
                 for (a, b), n in loops.most_common(5)]
    branch_rows = [dict(pc=hex(pc), executions=len(outcomes), taken=sum(outcomes),
                        transitions=sum(a != b for a, b in zip(outcomes, outcomes[1:])))
                   for pc, outcomes in sorted(branches.items(),
                                              key=lambda item: -len(item[1]))[:5]]
    result = dict(instructions=len(trace),
                  pairs=[dict(pc=hex(a), next_pc=hex(b), names=[names[a], names[b]],
                              count=n) for (a, b), n in pairs.most_common(8)],
                  raw_pairs=raw_pairs.most_common(8), load_use=load_use.most_common(8),
                  load_use_total=sum(load_use.values()), loops=loop_rows,
                  branches=branch_rows)
    Path('build/fmax-eval/trace.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=('cuts', 'explore'), nargs='?', default='cuts')
    phase = parser.parse_args().phase
    destination = Path('build/fmax-eval/' + ('model' if phase == 'cuts' else 'limits') + '.jsonl')
    destination.parent.mkdir(parents=True, exist_ok=True)
    if phase == 'explore':
        trace_statistics()
    with destination.open('w') as output:
        with ProcessPoolExecutor(max_workers=2, initializer=load) as pool:
            for row in pool.map(evaluate, (CONFIGS if phase == 'cuts' else LIMITS).items()):
                line = json.dumps(row)
                output.write(line + '\n')
                output.flush()
                print(line, flush=True)
